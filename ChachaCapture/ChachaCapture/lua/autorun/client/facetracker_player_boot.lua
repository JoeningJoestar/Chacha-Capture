-- Keep a useful command available even when another optional addon component
-- fails during startup. The full implementation in facetracker.lua replaces
-- these handlers when it loads successfully.
local function invokePlayer(method)
	if FaceTracker and FaceTracker.Player and FaceTracker.Player[method] then
		return FaceTracker.Player[method]()
	end

	local message = "茶茶捕捉玩家模块尚未加载。请检查 addons/face-tracker/lua 路径和 GMod 控制台错误。"
	print("[茶茶捕捉·玩家] " .. message)
	if notification and notification.AddLegacy then
		notification.AddLegacy(message, NOTIFY_ERROR, 6)
	end
end

concommand.Add("face_tracker_start", function()
	invokePlayer("Start")
end)

concommand.Add("facetracker_player_start", function()
	invokePlayer("Start")
end)

concommand.Add("face_tracker_stop", function()
	invokePlayer("Stop")
end)

concommand.Add("facetracker_player_stop", function()
	invokePlayer("Stop")
end)
