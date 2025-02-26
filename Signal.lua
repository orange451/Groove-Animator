--!strict

--------------------------------------------------------------------------------
--               Batched Yield-Safe Signal Implementation                     --
-- This is a Signal class which has effectively identical behavior to a       --
-- normal RBXScriptSignal, with the only difference being a couple extra      --
-- stack frames at the bottom of the stack trace when an error is thrown.     --
-- This implementation caches runner coroutines, so the ability to yield in   --
-- the signal handlers comes at minimal extra cost over a naive signal        --
-- implementation that either always or never spawns a thread.                --
--                                                                            --
-- API:                                                                       --
--   local Signal = require(THIS MODULE)                                      --
--   local sig = Signal.new()                                                 --
--   local connection = sig:Connect(function(arg1, arg2, ...) ... end)        --
--   sig:Fire(arg1, arg2, ...)                                                --
--   connection:Disconnect()                                                  --
--   sig:DisconnectAll()                                                      --
--   local arg1, arg2, ... = sig:Wait()                                       --
--                                                                            --
-- Licence:                                                                   --
--   Licenced under the MIT licence.                                          --
--                                                                            --
-- Authors:                                                                   --
--   stravant - July 31st, 2021 - Created the file.                           --
--   CompilerError - October 15th, 2024 - Added Luau typing support       --
--------------------------------------------------------------------------------

-- The currently idle thread to run the next handler on
local freeRunnerThread: thread? = nil

export type Signal<T, O...> = {
	Fire: (self: Signal<T, O...>, O...) -> (),
	Connect: (self: Signal<T, O...>, T) -> Connection,
	Once: (self: Signal<T, O...>, T) -> Connection,
	Wait: (self: Signal<T, O...>) -> (O...),
	DisconnectAll: (self: Signal<T, O...>) -> (),
	Destroy: (self: Signal<T, O...>) -> (),
	_handlerListHead: Connection,
}

export type Connection = {
	_connected: boolean,
	_fn: (...any) -> (),
	_next: Connection?,
	Disconnect: (self: Connection) -> ()
}

-- Function which acquires the currently idle handler runner thread, runs the
-- function fn on it, and then releases the thread, returning it to being the
-- currently idle one.
-- If there was a currently idle runner thread already, that's okay, that old
-- one will just get thrown and eventually GCed.
local function acquireRunnerThreadAndCallEventHandler(fn: (...any) -> (), ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	freeRunnerThread = acquiredRunnerThread
end

-- Coroutine runner that we create coroutines of. The coroutine can be 
-- repeatedly resumed with functions to run followed by the argument to run
-- them with.
local function runEventHandlerInFreeThread()
	-- Note: We cannot use the initial set of arguments passed to
	-- runEventHandlerInFreeThread for a call to the handler, because those
	-- arguments would stay on the stack for the duration of the thread's
	-- existence, temporarily leaking references. Without access to raw bytecode
	-- there's no way for us to clear the "..." references from the stack.
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

-- Connection class
local Connection = {}
Connection.__index = Connection

function Connection.new<T>(signal: Signal<T, ...any>, fn: T): Connection
	local self = setmetatable({
		_connected = true,
		_signal = signal,
		_fn = fn,
		_next = nil,
	} :: any, Connection)

	return self :: Connection
end

function Connection:Disconnect()
	self._connected = false

	-- Unhook the node, but DON'T clear it. That way any fire calls that are
	-- currently sitting on this node will be able to iterate forwards off of
	-- it, but any subsequent fire calls will not hit it, and it will be GCed
	-- when no more fire calls are sitting on it.
	if self._signal._handlerListHead == self then
		self._signal._handlerListHead = self._next
	else
		local prev = self._signal._handlerListHead
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

-- Signal class
local Signal = {}
Signal.__index = Signal

function Signal.new<T, O...>(): Signal<T, O...>
	local self = setmetatable({
		_handlerListHead = nil,
	} :: any, Signal)
	return self :: Signal<T, O...>
end

function Signal:Connect<T, O...>(fn: T): Connection
	local connection = Connection.new(self, fn)
	if self._handlerListHead then
		connection._next = self._handlerListHead
		self._handlerListHead = connection
	else
		self._handlerListHead = connection
	end
	return connection
end

function Signal:DisconnectAll<T, O...>()
	self._handlerListHead = nil
end

function Signal:Destroy<T, O...>()
	self:DisconnectAll()
end

function Signal:Fire<T, O...>(...)
	local item = self._handlerListHead
	while item do
		if item._connected then
			if not freeRunnerThread then
				local newThread: thread = coroutine.create(runEventHandlerInFreeThread)
				freeRunnerThread = newThread
				coroutine.resume(newThread)
			end
			task.spawn(freeRunnerThread :: thread, item._fn, ...)
		end
		item = item._next
	end
end

function Signal:Wait<T, O...>(): (O...)
	local waitingCoroutine = coroutine.running()
	local cn: Connection
	cn = self:Connect(function(...)
		cn:Disconnect()
		task.spawn(waitingCoroutine, ...)
	end)
	return coroutine.yield()
end

function Signal:Once<T, O...>(fn: (T, O...) -> ()): Connection
	local cn: Connection
	cn = self:Connect(function(...)
		if cn._connected then
			cn:Disconnect()
		end
		fn(...)
	end)
	return cn
end

return Signal
