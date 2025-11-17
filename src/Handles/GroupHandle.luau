--!strict
--[[
	Author - RobloxJrTrainer

	'GroupHandle' - A handle for managing groups of ConnectionLike objects created by Binder.
	Provides methods for adding, removing, and batch disconnecting connections within a group.
	This class is typically not instantiated directly but returned from Binder:bindGroup().
]]
-- SERVICES --


-- IMPORTS --
local Types = require(script.Parent.Parent.Types)

-- TYPES --


-- VARIABLES --
local GroupHandle = {}
local GroupHandleMt = {
	__newindex = function(_, key, value)
		error(`Attempt setting key of '{key}' with value '{value}' on immutable Instance: 'GroupHandle'`)
	end,
}
local privateData = {}

GroupHandleMt.__index = function(self, key)
	assert(not self.__destroyed, `Attempt to index destroyed object: 'GroupHandle' with key of '{key}' is likely a bug`)
	local private = privateData[self]
	if private then
		if GroupHandleMt[key] then
			return GroupHandleMt[key]
		end
		-- Check if we can directly index private._connections
		if private._connections[key] then
			return private._connections[key]
		end
	end
	return nil
end

-- CONSTANTS --


-- PRIVATE FUNCTIONS --


-- CONSTRUCTOR --

--[[
	Creates a new GroupHandle instance for managing a group of connections.

	The GroupHandle class provides centralized management for groups of ConnectionLike
	objects, allowing batch operations and organized cleanup. This constructor is typically
	called internally by Binder:bindGroup() rather than being used directly.

	@param connections {Types.ConnectionLike} -- Array of ConnectionLike objects to manage
	@param unbindFunc (Types.ConnectionLike) -> () -- Function to call when unbinding connections
	@return Types.GroupHandle -- A new GroupHandle instance for the connection group

	Example:
	```lua
	-- Usually created via Binder:bindGroup(), not directly:
	local group = binder:bindGroup(connectionArray)
	```
]]
function GroupHandle.new(connections: {Types.ConnectionLike}, unbindFunc: (Types.ConnectionLike) -> ()): Types.GroupHandle
	local self: any = setmetatable({__type = "GroupHandle", __destroyed = false}, GroupHandleMt)
	local private = {
		_connections = connections,
		_unbindFunc = unbindFunc
	}
	privateData[self] = private
	return self
end

-- PUBLIC METHODS --

--[[
	Adds a new ConnectionLike object to the end of the group.

	Appends a new ConnectionLike object to the group's connection array, making it
	part of the group for future batch operations. The connection will be included
	when calling disconnect() or destroy() on this GroupHandle.

	@param connection Types.ConnectionLike -- The connection to add to the group
	@return number -- The index where the connection was inserted

	Example:
	```lua
	local group = binder:bindGroup(existingConnections)
	local newConnection = binder:bind(workspace.ChildRemoved):Connect(onChildRemoved)

	local insertIndex = group:add(newConnection)
	print("Connection added at index:", insertIndex)
	```
]]
function GroupHandleMt:add(connection: Types.ConnectionLike)
	local private = privateData[self]
	local connections = private._connections
	local index = #connections+1
	connections[index] = connection
	return index
end

--[[
	Removes a connection from the group without disconnecting it.

	Removes a connection from the group's internal array by setting the specified
	index to nil. This does NOT disconnect the connection - it only removes it from
	the group's management. The array is not shifted, so other indices remain stable.

	@param index number -- The array index of the connection to remove
	@return Types.ConnectionLike -- The connection that was removed from the group

	Example:
	```lua
	local group = binder:bindGroup(connections)

	-- Remove connection at index 2 but keep it connected:
	local removedConnection = group:remove(2)
	-- Connection is still active, just no longer managed by this group
	```
]]
function GroupHandleMt:remove(index: number)
	local private = privateData[self]
	-- Prevent index shifting (set to nil)
	local connections = private._connections
	local connection = connections[index]
	connections[index] = nil
	return connection
end

--[[
	Disconnects all ConnectionLike objects in the group and clears the array.

	Iterates through all connections in the group, calls the unbind function on each
	to properly disconnect them, and then sets each array slot to nil. After this
	operation, the connections array will be empty but the GroupHandle object itself
	remains in memory. Use destroy() if you want to completely clean up the GroupHandle.

	Example:
	```lua
	local group = binder:bindGroup(connections)

	-- Later, disconnect all connections in the group:
	group:disconnect()
	-- All connections are now disconnected and removed from the group
	```
]]
function GroupHandleMt:disconnect()
	local private = privateData[self]
	local connections = private._connections
	for i = #connections, 1, -1 do
		local con = connections[i]
		if con then
			-- Call the private._unbindFunc
			private._unbindFunc(con)
		end
		connections[i] = nil
	end
end

--[[
	Returns the internal array of ConnectionLike objects for read-only access.

	Provides direct access to the connections array managed by this GroupHandle.
	WARNING: This array is mutable and can be modified directly, which may cause
	unexpected behavior. It's recommended to treat the returned array as read-only
	and use the provided methods (add, remove, disconnect) for modifications.

	@return {Types.ConnectionLike} -- The internal connections array (mutable reference)

	Example:
	```lua
	local group = binder:bindGroup(connections)
	local connectionsArray = group:getConnections()

	print("Group has", #connectionsArray, "connections")
	-- Treat as read-only to avoid issues:
	for i, connection in ipairs(connectionsArray) do
		if connection and connection.Connected then
			print("Connection", i, "is active")
		end
	end
	```
]]
function GroupHandleMt:getConnections()
	return privateData[self]._connections
end

--[[
	Completely destroys the GroupHandle and disconnects all managed connections.

	This method disconnects all connections in the group, clears all private data,
	and marks the GroupHandle as destroyed. After calling this method, the GroupHandle
	should not be used anymore as it will no longer function properly. This is the
	recommended cleanup method when you're completely done with a GroupHandle.

	Example:
	```lua
	local group = binder:bindGroup(connections)
	-- ... use group for connection management ...

	-- When done, clean up completely:
	group:destroy()
	```
]]
function GroupHandleMt:destroy()
	if privateData[self] then
		-- Disconnect all connections
		self:disconnect()
		privateData[self] = nil
		self.__destroyed = true
	end
end

return GroupHandle