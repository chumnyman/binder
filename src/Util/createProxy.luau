--!strict
return function<K, V>(
	indexHandler: (tbl: {[K]: V}, index: K) -> V?
): typeof(setmetatable({} :: {[K]: V}, {} :: {__index: (tbl: {[K]: V}, index: K) -> V?}))
	local proxy = {}
	local proxyMt = {
		__index = indexHandler,
	}
	return setmetatable(proxy, proxyMt)
end