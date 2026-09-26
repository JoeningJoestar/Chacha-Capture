---@diagnostic disable: undefined-global

-- Loading the addon must not abort just because the optional GWSockets DLL is
-- missing.  Player-mode commands and the Q-menu should still be available so
-- the user gets an actionable error instead of "unknown command".
local socketError
if not GWSockets then
	local ok, loaded = pcall(require, "gwsockets")
	if not ok then
		socketError = tostring(loaded)
	elseif loaded and not GWSockets then
		GWSockets = loaded
	end
end

local HOST, PORT = "localhost", 8667

---@class SocketSystem
---@field private _socketTimerId string
---@field private _socket any
---@field private _timeout number
local socket
if GWSockets and isfunction(GWSockets.createWebSocket) then
	local ok, value = pcall(GWSockets.createWebSocket, "ws://" .. HOST .. ":" .. PORT, false)
	if ok and value then
		socket = value
	elseif ok then
		socketError = "GWSockets 未返回有效连接"
	else
		socketError = tostring(value)
	end
else
	socketError = socketError or "GWSockets.createWebSocket 不可用"
end

-- A no-op socket keeps the rest of the addon loadable.  The real socket is
-- installed automatically when the GWSockets client module is available.
socket = socket or {
	isConnected = function()
		return false
	end,
	open = function() end,
	close = function() end,
	write = function() end,
}

local system = {
	_socket = socket,
	_available = socketError == nil,
	_error = socketError,
	_socketTimerId = "facetracker_timeout",
	_timeout = 5,
	_listeners = {
		connected = {},
		disconnected = {},
		error = {},
		message = {},
	},
}

local function emit(event, ...)
	for id, listener in pairs(system._listeners[event]) do
		local ok, err = pcall(listener, ...)
		if not ok then
			ErrorNoHalt(Format("[茶茶捕捉] 监听器 '%s' 执行失败：%s\n", id, tostring(err)))
		end
	end
end

---@package
function system._socket:onMessage(text)
	FaceTracker.Socket:onMessage(text)
	emit("message", text)
end

---@package
function system._socket:onConnected()
	timer.Remove(system._socketTimerId)
	self:write(LocalPlayer():Nick())

	print("[茶茶捕捉] 已连接面捕服务")
	FaceTracker.Socket:onConnected()
	emit("connected")
end

---@package
function system._socket:onDisconnected()
	print("[茶茶捕捉] 已断开面捕服务")
	FaceTracker.Socket:onDisconnected()
	emit("disconnected")
end

---@package
function system._socket:onError(text)
	print("[茶茶捕捉] 连接错误：", text)
	FaceTracker.Socket:onError()
	emit("error", text)
end

function system:onError() end

function system:onConnected() end

function system:onDisconnected() end

---@param text string
function system:onMessage(text) end

---@return boolean
function system:isConnected()
	return self._socket:isConnected()
end

---@param event "connected"|"disconnected"|"error"|"message"
---@param id string
---@param listener function
function system:addListener(event, id, listener)
	if not self._listeners[event] then
		return false
	end
	self._listeners[event][id] = listener
	return true
end

---@param event "connected"|"disconnected"|"error"|"message"
---@param id string
function system:removeListener(event, id)
	if self._listeners[event] then
		self._listeners[event][id] = nil
	end
end

function system:connect()
	if not self._available then
		print("[茶茶捕捉] GWSockets 不可用：" .. tostring(self._error))
		return false
	end
	if self:isConnected() or timer.Exists(self._socketTimerId) then
		return true
	end

	timer.Create(self._socketTimerId, self._timeout, 1, function()
		timer.Remove(system._socketTimerId)
		if not system._socket:isConnected() then
			print("[茶茶捕捉] 连接超时")
			system._socket:close()
		end
	end)

	print("[茶茶捕捉] 正在连接 ws://" .. HOST .. ":" .. PORT)
	self._socket:open()
	return true
end

function system:disconnect()
	timer.Remove(self._socketTimerId)
	if self:isConnected() then
		self._socket:close()
	end
end

function system:toggleConnection()
	if self:isConnected() then
		self:disconnect()
	else
		self:connect()
	end
end

function system:isAvailable()
	return self._available
end

function system:getError()
	return self._error
end

FaceTracker.Socket = system
