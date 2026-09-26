local enableSystem = CreateConVar("sv_facetracker_enablesystem", "1", FCVAR_NOTIFY + FCVAR_LUA_SERVER)
local allowLegacyEntities = CreateConVar(
	"sv_facetracker_legacy_entities",
	"0",
	FCVAR_NOTIFY + FCVAR_LUA_SERVER,
	"允许旧工具枪在多人游戏中驱动发送者以外的实体"
)
local enabled = enableSystem:GetBool()
cvars.AddChangeCallback("sv_facetracker_enablesystem", function(convar, oldValue, newValue)
	enabled = tobool(Either(tonumber(newValue) ~= nil, tonumber(newValue) > 0, false))
end)

net.Receive("facetracker_replicate", function(len, ply)
	if not enabled then
		return
	end

	local entIndex = net.ReadUInt(14)
	local entity = Entity(entIndex)
	if not IsValid(entity) then
		return
	end

	-- The original receiver trusted an arbitrary entity index supplied by a
	-- client. Keep prop/NPC animation in singleplayer, but do not allow one
	-- multiplayer client to change another player or arbitrary server entity.
	if not game.SinglePlayer() and entity ~= ply and not allowLegacyEntities:GetBool() then
		return
	end

	for i = 0, entity:GetFlexNum() - 1 do
		entity:SetFlexWeight(i, net.ReadFloat())
	end

	local eyeTarget = net.ReadVector()
	entity:SetEyeTarget(eyeTarget)
end)
