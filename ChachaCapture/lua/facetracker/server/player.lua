util.AddNetworkString("facetracker_player_frame")
util.AddNetworkString("facetracker_player_stop")
util.AddNetworkString("facetracker_player_pose_frame")
util.AddNetworkString("facetracker_player_pose_stop")

local enabledConVar = CreateConVar(
	"sv_facetracker_player_enabled",
	"1",
	FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"允许玩家同步自己的面部表情"
)
local maxRateConVar = CreateConVar(
	"sv_facetracker_player_maxrate",
	"30",
	FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"每名玩家允许的最高面捕同步帧率",
	10,
	60
)

local lastFrame = {}
local lastPacket = {}
local lastPoseFrame = {}
local lastPosePacket = {}
local activeFlexes = {}
local FRAME_TIMEOUT = 2

local function resetPlayerFlexes(ply)
	local touched = activeFlexes[ply]
	if not touched then
		return
	end
	for id in pairs(touched) do
		if id < ply:GetFlexNum() then
			ply:SetFlexWeight(id, tonumber(touched[id]) or 0)
		end
	end
	activeFlexes[ply] = nil
end

net.Receive("facetracker_player_frame", function(_, ply)
	if not enabledConVar:GetBool() or not IsValid(ply) or not ply:IsPlayer() then
		return
	end

	local now = RealTime()
	local minimumInterval = 1 / math.max(maxRateConVar:GetInt(), 1)
	if now - (lastPacket[ply] or 0) < minimumInterval then
		return
	end
	lastPacket[ply] = now

	local sequence = net.ReadUInt(16)
	local count = net.ReadUInt(8)
	local expected = math.min(ply:GetFlexNum(), 255)
	if count ~= expected then
		lastFrame[ply] = nil
		resetPlayerFlexes(ply)
		return
	end

	local values = {}
	for i = 1, count do
		values[i] = net.ReadUInt(8)
	end
	local eyeX = net.ReadUInt(8)
	local eyeY = net.ReadUInt(8)
	lastFrame[ply] = now

	local touched = activeFlexes[ply] or {}
	for id = 0, count - 1 do
		local value = values[id + 1]
		if value < 255 then
			if touched[id] == nil then
				touched[id] = tonumber(ply:GetFlexWeight(id)) or 0
			end
			ply:SetFlexWeight(id, value / 254)
		elseif touched[id] ~= nil then
			ply:SetFlexWeight(id, tonumber(touched[id]) or 0)
			touched[id] = nil
		end
	end
	activeFlexes[ply] = touched

	net.Start("facetracker_player_frame", true)
	net.WriteEntity(ply)
	net.WriteUInt(sequence, 16)
	net.WriteUInt(count, 8)
	for i = 1, count do
		net.WriteUInt(values[i], 8)
	end
	net.WriteUInt(eyeX, 8)
	net.WriteUInt(eyeY, 8)
	net.SendOmit(ply)
end)

net.Receive("facetracker_player_stop", function(_, ply)
	if not IsValid(ply) or not ply:IsPlayer() then
		return
	end
	lastFrame[ply] = nil
	lastPacket[ply] = nil
	resetPlayerFlexes(ply)
	net.Start("facetracker_player_stop")
	net.WriteEntity(ply)
	net.Broadcast()
	lastPoseFrame[ply] = nil
	lastPosePacket[ply] = nil
	net.Start("facetracker_player_pose_stop")
	net.WriteEntity(ply)
	net.Broadcast()
end)

net.Receive("facetracker_player_pose_frame", function(_, ply)
	if not enabledConVar:GetBool() or not IsValid(ply) or not ply:IsPlayer() then
		return
	end
	local now = RealTime()
	local minimumInterval = 1 / math.max(maxRateConVar:GetInt(), 1)
	if now - (lastPosePacket[ply] or 0) < minimumInterval then
		return
	end
	lastPosePacket[ply] = now

	local sequence = net.ReadUInt(16)
	local values = {}
	for index = 1, 36 do
		values[index] = net.ReadInt(16)
	end
	lastPoseFrame[ply] = now

	net.Start("facetracker_player_pose_frame", true)
	net.WriteEntity(ply)
	net.WriteUInt(sequence, 16)
	for index = 1, 36 do
		net.WriteInt(values[index], 16)
	end
	net.SendOmit(ply)
end)

net.Receive("facetracker_player_pose_stop", function(_, ply)
	if not IsValid(ply) or not ply:IsPlayer() then
		return
	end
	lastPoseFrame[ply] = nil
	lastPosePacket[ply] = nil
	net.Start("facetracker_player_pose_stop")
	net.WriteEntity(ply)
	net.Broadcast()
end)

hook.Add("PlayerDisconnected", "facetracker_player_cleanup", function(ply)
	lastFrame[ply] = nil
	lastPacket[ply] = nil
	activeFlexes[ply] = nil
	lastPoseFrame[ply] = nil
	lastPosePacket[ply] = nil
end)

timer.Create("facetracker_player_timeout", 0.5, 0, function()
	local now = RealTime()
	for ply, timestamp in pairs(lastFrame) do
		if not IsValid(ply) or now - timestamp > FRAME_TIMEOUT then
			if IsValid(ply) then
				resetPlayerFlexes(ply)
				net.Start("facetracker_player_stop")
				net.WriteEntity(ply)
				net.Broadcast()
			end
			lastFrame[ply] = nil
			lastPacket[ply] = nil
		end
	end
	for ply, timestamp in pairs(lastPoseFrame) do
		if not IsValid(ply) or now - timestamp > FRAME_TIMEOUT then
			if IsValid(ply) then
				net.Start("facetracker_player_pose_stop")
				net.WriteEntity(ply)
				net.Broadcast()
			end
			lastPoseFrame[ply] = nil
			lastPosePacket[ply] = nil
		end
	end
end)
