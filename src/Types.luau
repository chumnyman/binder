--!strict
local Types = {}

export type ConnectionLike = {
	Connected: boolean,
	Disconnect: (self: ConnectionLike) -> ()
}

export type SignalLike<T...> = {
	Connect: (self: SignalLike<T...>, func: (T...) -> ()) -> ConnectionLike,
	ConnectParallel: (self: SignalLike<T...>, func: (T...) -> ()) -> ConnectionLike,
	Once: (self: SignalLike<T...>, func: (T...) -> ()) -> ConnectionLike,
}

-- This is the 'Binder' object public type
export type Binder = {
	__type: "Binder",
	__destroyed: boolean,
	bind: <T...>(self: Binder, signal: SignalLike<T...>) -> SignalLike<T...>,
	bindGroup: (self: Binder, connections: {ConnectionLike}) -> GroupHandle,
	unbind: (self: Binder, connection: ConnectionLike) -> (),
	unbindGroup: (self: Binder, group: GroupHandle) -> (),
	unbindAll: (self: Binder) -> (),
	destroy: (self: Binder) -> ()
}

-- This is the type for group control object 'GroupHandle'
export type GroupHandle = {
	[number]: ConnectionLike,
	__type: "GroupHandle",
	__destroyed: boolean,
	add: (self: GroupHandle, connection: ConnectionLike) -> number,
	remove: (self: GroupHandle, index: number) -> ConnectionLike,
	disconnect: (self: GroupHandle) -> (),
	getConnections: (self: GroupHandle) -> {ConnectionLike},
	destroy: (self: GroupHandle) -> (),
}

return Types