--!strict

--[[
	Author - RobloxJrTrainer

	Util module with functions for checking anything that the 'Binder' implementation requires.
	For example, 'Connection' objects need a .Connected or ._connected property, and a :Disconnect() method.
	Uses caching for maximum performance when detecting connection property types.
]]
local Types = require(script.Parent.Parent.Types)

local function isCallable(value)
	if type(value) == "function" then
		return true
	end
    return false
end

-- Gets the connection property name for a __pure__ connection object
local function getConnectionProperty(conLike)
	local prop
	if rawget(conLike, "Connected") then
		prop = "Connected"
	elseif rawget(conLike, "_connected") then
		prop = "_connected"
	end
	return prop
end


-- validates if an object implements the 'ConnectionLike' interface
local function isValidConLike(conLike: Types.ConnectionLike)
	-- Must be a table or RBXScriptConnection
	assert(type(conLike) == "table" or typeof(conLike) == "RBXScriptConnection",
		`Expected table or RBXScriptConnection, got {conLike}`)
	-- Must have a Disconnect method
	local disconnectMethod = conLike.Disconnect
	assert(type(disconnectMethod) == "function", "Missing or invalid 'Disconnect' method")
	-- Validate the connection property value
	local connectedValue = conLike.Connected
	assert(type(connectedValue) == "boolean",
		`Connection property '{connectedValue}' must be a boolean, got {connectedValue}`)
end

-- Validates if an object implements/resembles the 'GroupHandle' interface.
local function isValidGroupHandle(group: Types.GroupHandle)
	assert(type(group) == "table", `Expected a table, got '{group}'`)
	assert(group.__type == "GroupHandle", `Expected a 'GroupHandle' object with __type of 'GroupHandle', got '{group.__type}'`)
	assert(type(group.disconnect) == "function", `Expected a 'disconnect' function, got '{group.disconnect}'`)
end

-- Checks if a connection object is connected, using cached property detection
local function isConnected(conLike: Types.ConnectionLike)
	return conLike.Connected or false
end

local function connectionImpl(conLike: Types.ConnectionLike)
	assert(type(conLike) == "table" or typeof(conLike) == "RBXScriptConnection", `Expected a table or RBXScriptConnection, got '{conLike}'`)
	assert(conLike.Connected, `Connection object must have 'Connected' property`)
	assert(type(conLike.Connected) == "boolean", `Expected connection property '{conLike.Connected}' to be boolean, got '{conLike.Connected}'`)
	assert(isCallable(conLike.Disconnect), `Expected a function for Disconnect method, got '{conLike.Disconnect}'`)
end


return {
	conImpl = connectionImpl,
	isCallable = isCallable,
	isConnected = isConnected,
	isValidConLike = isValidConLike,
	isValidGroupHandle = isValidGroupHandle,
	getConnectionProperty = getConnectionProperty
}