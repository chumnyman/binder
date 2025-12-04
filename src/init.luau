--!strict
--[[
	Author - RobloxJrTrainer

	'Binder' - A connection management util that provides automatic intelligent cleanup and tracking of
	signal connections. Supports both RBXScriptSignals and 'GoodSignal' (by stravant) implementation with automatic
	polling for externally disconnected connections, group management, and cleanup operations.

	'GoodSignal' version compatibility:

	https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f (July 31st, 2021)

	In order for 'Binder' to work, it needs to access the 'private' '_connected' variable of 'GoodSignal' - no direct
	modification is happening to '_connected', the 'Binder' just reads it for info.

	'Binder' is provided under the MIT License
	V1.0.0 - September 6, 2024
]]
-- IMPORTS --
local GroupHandle = require(script.Handles.GroupHandle)
local Types = require(script.Types)
local check = require(script.Util.check)
local createProxy = require(script.Util.createProxy)
local ConnectionPoller = require(script.Util.ConnectionPoller)

-- TYPES --
export type ConnectionLike = Types.ConnectionLike
export type SignalLike<T...> = Types.SignalLike<T...>
export type Binder = Types.Binder
export type GroupHandle = Types.GroupHandle

-- VARIABLES --
local Binder = {}
local BinderMt = {
	__newindex = function(_, key, value)
		error(`Attempt setting key of '{key}' with value '{value}' on immutable Instance: 'Binder'`)
	end,
}
BinderMt.__index = BinderMt

local privateData = {}

-- CONSTANTS --

local COMPATIBLE_CONNECTION_METHODS = {Connect = true, Once = true, ConnectParallel = true}

-- PRIVATE FUNCTIONS --

local function updateSwappedConnectionIndex(list, index, lastIndex)
	if index ~= lastIndex and list[index] then
		local swapped = list[index]
		ConnectionPoller.updateIndex(swapped, index)
	end
end

local function cleanupConFromGroups(private, connection)
	local conToGroups = private._conToGroups
	local groups = conToGroups[connection]
	if not groups then
		return
	end
	for i = 1, #groups do
		local group = groups[i]
		if group then
			local indexToRemove = table.find(group:getConnections(), connection)
			if indexToRemove then
				group:remove(indexToRemove)
			end
		end
	end
	conToGroups[connection] = nil
end

local function removeConFromList(private, connection)
	-- Remove from private._list
	local conIndex = private._conIndexes[connection]
	if conIndex then
		local lastIndex = #private._list
		local swapped = private._list[lastIndex]
		-- Move last element to the removed pos
		private._list[conIndex] = swapped
		if swapped then
			private._conIndexes[swapped] = conIndex
			updateSwappedConnectionIndex(private._list, conIndex, lastIndex)
		end
		-- Remove last element and index entry
		private._list[lastIndex] = nil
		private._conIndexes[connection] = nil
	end
	-- Remove from an existing group... (this is O(1) lookup )
	cleanupConFromGroups(private, connection)
end

local function disconnectConnection(private, connection)
	-- Unreg from polling system for any ConnectionLike object
	ConnectionPoller.unreg(connection)
	if check.isConnected(connection) then
		connection:Disconnect()
	end
	removeConFromList(private, connection)
end

-- CONSTRUCTOR --

--[[
	Creates a new Binder instance for managing signal connections.

	The Binder class provides intelligent connection management with automatic cleanup,
	tracking, and group operations. It works with both RBXScriptSignals and GoodSignal
	implementations, automatically detecting connection types and handling them appropriately.

	@return Binder -- A new Binder instance ready for connection management

	Example:
	```lua
	local binder = Binder.new()
	local boundSignal = binder:bind(workspace.ChildAdded)
	boundSignal:Connect(function(child)
		print("Child added:", child.Name)
	end)
	```
]]
function Binder.new(): Binder
	local self: any = setmetatable({__type = "Binder", __destroyed = false}, BinderMt)
	local private = {
		_list = {}, -- {[number]: ConnectionLike}
		_conToGroups = {}, -- {[ConnectionLike]: {GroupHandle}}
		_conIndexes = {}, -- {[ConnectionLike]: number} -- Direct index lookup table for O(1) check
	}
	privateData[self] = private
	return self
end

-- PUBLIC METHODS --

--[[
	Creates a proxy wrapper around a signal for automatic connection tracking.

	Returns a proxy/wrapper around the original signal that forwards all original methods
	while automatically tracking any connections made through it. The proxy maintains
	full compatibility with the original signal API while adding intelligent cleanup

	Supported connection methods:
	- RBXScriptSignal: Connect, ConnectParallel, Once
	- GoodSignal: Connect, Once


	Cleanup Timing Behavior on external Disconnect:
	- Table-based connections (GoodSignal): Instant cleanup via metatable proxies
	- RBXScriptConnection: Small delay (~0.33ms) via polling system

	@param signal SignalLike<T...> -- The signal to wrap (RBXScriptSignal or GoodSignal)
	@return SignalLike<T...> -- A proxied version of the original signal with automatic connection tracking

	Example:
	```lua
	local boundSignal = binder:bind(workspace.ChildAdded)
	local connection = boundSignal:Connect(function(child)
		print("New child:", child.Name)
	end)
	-- Connection is automatically tracked and contained!
	```
]]
function BinderMt:bind<T...>(signal: SignalLike<T...>)
	assert(type(signal) == "table" or typeof(signal) == "RBXScriptSignal", `Expected a table or RBXScriptSignal, got '{signal}'`)
	local private = privateData[self]
	-- Return a proxy that intercepts expected calls
	return createProxy(function(_, signalKey)
		-- Does this exist?
		assert((signal :: any)[signalKey] ~= nil, `Key of '{signalKey}' doesn't exist on the provided signal implementation`)
		-- Is this key actually compatible with "Binder"?
		assert(COMPATIBLE_CONNECTION_METHODS[signalKey], `Key of '{signalKey}' is not compatible with 'Binder'. Use the original 'Signal' object instead.`)
		-- Intercept connection methods to track them here instead
		return function(_, func)
			-- This most likely has a connectable method
			local con = (signal :: any)[signalKey](signal, func) -- {[Disconnect=function, Connected|_connected=boolean]}
			local wrappedCon = con
			-- if it's a custom impl, we can create a proxy over it to maintain consistent API design
			if type(con) == "table" then
				-- Determine the connection property once at creation time
				local connectionProp = "Connected"
				if con._connected ~= nil and type(con._connected) == "boolean" then
					connectionProp = "_connected"
				end
				-- Internal proxy code can use the connectionProp variable, also known as an "upvalue"
				wrappedCon = createProxy(function(_, key)
					if key == "Connected" then
						return con[connectionProp]
					elseif key == "Disconnect" then
						-- Return a closure - ensures 'con' gets passed correctly for 'self'.
						-- We can't just return con[key], as 'wrappedCon' would be used for self, when we need 'con' to be used instead
						return function()
							removeConFromList(private, wrappedCon)
							ConnectionPoller.unreg(wrappedCon)
							return con:Disconnect()
						end
					else
						return con[key]
					end
				end)
			end
			-- If it's a RBXScriptConnection, polling will automatically take care of it with a few frames of delay...
			check.conImpl(wrappedCon)
			-- Optimized polling for all ConnectionLike objects. (Handles potential external disconnections)
			local connectionIndex = (#private._list+1)
			private._list[connectionIndex] = wrappedCon
			private._conIndexes[wrappedCon] = connectionIndex
			ConnectionPoller.reg(wrappedCon, function(connection, index)
				-- Handle external disconnection
				removeConFromList(private, connection)
			end, connectionIndex)
			return wrappedCon
		end
	end)
end

--[[
	Creates a group from an array of ConnectionLike objects for batch management.

	Binds an array of ConnectionLike objects and assigns them to a group, returning
	a GroupHandle object that can be used for centralized control over all connections
	in the group. This is useful for managing related connections that should be
	handled together.

	For detailed information about GroupHandle methods (add, remove, disconnect, etc.),
	refer to the GroupHandle module documentation.

	@param connections {ConnectionLike} -- Array of ConnectionLike objects to group
	@return GroupHandle -- A GroupHandle for managing the connection group

	Example:
	```lua
	local boundSignal = binder:bind(workspace.ChildAdded)
	local connections = {
		boundSignal:Connect(onChildAdded),
		boundSignal:Connect(onChildAddedSecondHandler),
		boundSignal:Connect(onChildAddedThirdHandler)
	}

	local group = binder:bindGroup(connections)
	-- Later, disconnect all at once:
	group:disconnect()
	```
]]
function BinderMt:bindGroup(connections: {ConnectionLike})
	assert(type(connections) == "table", `Expected a table, got '{connections}'`)
	assert(#connections > 0, `Expected an array of 'ConnectionLike' objects greater than 0`)
	-- Check for proper array format
	for key, _ in pairs(connections) do
		assert(type(key) == "number" and key > 0 and key <= #connections and key == math.floor(key),
			`Expected key to be a positive integer within array bounds, got '{key}'`
		)
	end
	local private = privateData[self]
	-- Construct a new 'GroupHandle'
	local group = GroupHandle.new(connections, function(con) self:unbind(con) end)
	-- Map each connection to this group
	local conToGroups = private._conToGroups
	for i = 1, #connections do
		local con = connections[i]
		local conGroups = conToGroups[con]
		if conGroups then
			conGroups[#conGroups+1] = group
		else
			conToGroups[con] = {group}
		end
	end
	return group
end

--[[
	Unbinds and disconnects a specific ConnectionLike object.

	This is the optimal way to disconnect individual connections as it immediately
	removes the connection from internal tracking and disconnects it. RBXScriptConnections
	that are disconnected externally have a small polling delay before removal, so using
	this method is preferred when possible.

	Note: Some connection methods like Once() handle disconnection internally, so external
	Disconnect() calls are not forbidden but may be less optimal.

	@param connection ConnectionLike -- The connection to unbind and disconnect

	Example:
	```lua
	local boundSignal = binder:bind(workspace.ChildAdded)
	local connection = boundSignal:Connect(onChildAdded)

	-- Later, unbind the specific connection:
	binder:unbind(connection)
	```
]]
function BinderMt:unbind(connection: ConnectionLike)
	check.isValidConLike(connection)
	disconnectConnection(privateData[self], connection)
end

--[[
	Unbinds and disconnects all connections in a GroupHandle.

	This method provides an alternative way to disconnect all connections in a group
	by calling it on the Binder instance. It's functionally equivalent to calling
	group:disconnect() directly on the GroupHandle object, though calling disconnect()
	directly on the GroupHandle may be slightly faster.

	@param group GroupHandle -- The GroupHandle containing connections to unbind

	Example:
	```lua
	local group = binder:bindGroup(connections)

	-- These two calls are equivalent:
	binder:unbindGroup(group)  -- Method 1
	group:disconnect()         -- Method 2 (slightly faster)
	```
]]
function BinderMt:unbindGroup(group: GroupHandle)
	check.isValidGroupHandle(group)
	group:disconnect()
end

--[[
	Unbinds and disconnects every tracked connection in the Binder.

	This method disconnects all ConnectionLike objects that have been tracked by this
	Binder instance, including individual connections and those in groups. This is
	useful for complete cleanup when you're done with a Binder but don't want to
	destroy it yet.

	Example:
	```lua
	-- After creating many connections...
	local boundSignal = binder:bind(workspace.ChildAdded)
	boundSignal:Connect(handler1)
	boundSignal:Connect(handler2)

	-- Disconnect everything at once:
	binder:unbindAll()
	```
]]
function BinderMt:unbindAll()
	local private = privateData[self]
	local list = private._list
	for i = #list, 1, -1 do
		local con = list[i]
		disconnectConnection(private, con)
	end
end

--[[
	Completely destroys the Binder instance and cleans up all resources.

	This method disconnects all tracked connections, clears all private data,
	and marks the instance as destroyed. After calling this method, the Binder
	instance should not be used anymore as it will no longer function properly.
	This is the recommended cleanup method when you're completely done with a Binder.

	Example:
	```lua
	local binder = Binder.new()
	-- ... use binder for connection management ...

	-- When done, clean up completely:
	binder:destroy()
	binder = nil -- Good practice to nil the reference
	```
]]
function BinderMt:destroy()
	if privateData[self] then
		-- Disconnect all connections
		self:unbindAll()
		-- Set the table to nil (gc will handle the rest)
		privateData[self] = nil
		self.__destroyed = true
	end
end

return Binder