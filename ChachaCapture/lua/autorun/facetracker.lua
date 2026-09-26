---@diagnostic disable-next-line: undefined-global
FaceTracker = FaceTracker or {}

if SERVER then
	print("正在加载茶茶捕捉（服务器）")

	AddCSLuaFile("facetracker/shared/helpers.lua")
	AddCSLuaFile("facetracker/shared/mathparser.lua")

	AddCSLuaFile("facetracker/client/parser.lua")
	AddCSLuaFile("facetracker/client/socket.lua")
	AddCSLuaFile("facetracker/client/system.lua")
	AddCSLuaFile("facetracker/client/ui.lua")
	AddCSLuaFile("facetracker/client/player.lua")
	AddCSLuaFile("facetracker/client/manual_menu.lua")
	AddCSLuaFile("facetracker/client/flex_creator.lua")
	AddCSLuaFile("weapons/gmod_tool/stools/facetracker_flex.lua")
	AddCSLuaFile("facetracker/client/pose.lua")
	AddCSLuaFile("facetracker/client/player_menu.lua")

	include("facetracker/shared/presets.lua")

	include("facetracker/server/net.lua")
	include("facetracker/server/system.lua")
	include("facetracker/server/player.lua")
else
	print("正在加载茶茶捕捉（客户端）")

	include("facetracker/client/parser.lua")
	include("facetracker/client/socket.lua")
	include("facetracker/client/system.lua")
	include("facetracker/client/player.lua")
	include("facetracker/client/manual_menu.lua")
	include("facetracker/client/flex_creator.lua")
	include("facetracker/client/pose.lua")
	include("facetracker/client/player_menu.lua")
	print("茶茶捕捉已加载（面部捕捉 + 头部捕捉；PAC3 兼容优化）")
end
