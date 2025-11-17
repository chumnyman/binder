--!strict
--[[
	Author - RobloxJrTrainer

	ConnectionPoller for highly optimized polling of ConnectionLike objects
	Handles cleanup of externally disconnected connections using a global, batched polling system
	Works with both RBXScriptConnections and custom connection implementations
]]

-- SERVICES --
local RunService = game:GetService("RunService")

-- IMPORTS --
local Types = require(script.Parent.Parent.Types)
local check = require(script.Parent.check)

-- TYPES --
export type ConnectionLike = Types.ConnectionLike
export type PollerCallback = (connection: ConnectionLike, binderIndex: number) -> ()

-- VARIABLES --
local ConnectionPoller = {}

local connections = {}
local isRunning = false
local connection = nil
local lastCleanup = 0

-- CONSTANTS --
local CLEANUP_INTERVAL = 60
local BATCH_SIZE = 100
local POLL_INTERVAL = 1/30 -- Poll at 30hz (~33.33ms)

-- PRIVATE FUNCTIONS --


local function invokeAndCleanup(con, connections)
	local data = connections[con]
	if data then
		local callback, index = data.callback, data.index
		connections[con] = nil -- Same as unregistering
		callback(con, index)
	end
end

local function startPolling()
	if isRunning then
		return
	end
	isRunning = true
	local currentIndex = 1
	local lastPollTime = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		lastPollTime += dt
		if lastPollTime < POLL_INTERVAL then
			return
		end
		lastPollTime = 0
		local currentFrameConnections = connections
		local currentFrameConnectionList = {}
		local ct = 0
		-- Convert to array for efficient iteration (do this once per frame)
		for con in pairs(currentFrameConnections) do
			ct+=1
			currentFrameConnectionList[ct] = con
		end
		if ct == 0 then
			-- No connections to poll, stop global polling
			connection:Disconnect()
			isRunning = false
			lastCleanup = 0
		else
			-- Process batch of connections
			local endIndex = math.min(currentIndex+BATCH_SIZE-1, ct)
			for i = currentIndex, endIndex do
				local con = currentFrameConnectionList[i]
				local data = currentFrameConnections[con]
				if data and not check.isConnected(con) then
					-- Connection was disconnected externally
					invokeAndCleanup(con, connections)
				end
			end
			-- Update current index for next frame
			currentIndex = (endIndex+1)
			if currentIndex > ct then
				currentIndex = 1
				-- Periodic cleanup of stale refs
				local currentTime = os.clock()
				if currentTime-lastCleanup > CLEANUP_INTERVAL then
					lastCleanup = currentTime
					-- Clean up any cons that might have been missed
					for con, data in pairs(connections) do
						if not check.isConnected(con) then
							invokeAndCleanup(con, connections)
						end
					end
				end
			end
		end
	end)
end

-- PUBLIC FUNCTIONS --

-- Registers a ConnectionLike object for polling.
-- The callback will get invoked when the connection is detected as disconnected
function ConnectionPoller.reg(connection: ConnectionLike, callback: PollerCallback, index: number)
	connections[connection] = {
		callback = callback,
		index = index
	}
	startPolling()
end

-- Unregisters a ConnectionLike object from polling
function ConnectionPoller.unreg(connection: ConnectionLike)
	connections[connection] = nil
end

-- Updates the index associated with a registered connection
-- Useful when connections are moved around in arrays
function ConnectionPoller.updateIndex(connection: ConnectionLike, newIndex: number)
	local data = connections[connection]
	if data then
		data.index = newIndex
	end
end

-- Gets the current number of cons being polled
function ConnectionPoller.getPolledCt()
	local ct = 0
	for _ in pairs(connections) do ct+=1 end
	return ct
end

-- Forces an immediate cleanup cycle
function ConnectionPoller.forceCleanup()
	for con, data in pairs(connections) do
		if not check.isConnected(con) then
			invokeAndCleanup(con, connections)
		end
	end
end

-- Stops all polling and clears all registered connections
function ConnectionPoller.shutdown()
	if connection and connection.Connected then
		connection:Disconnect()
	end
	isRunning = false
	connections = {}
	lastCleanup = 0
end

return ConnectionPoller