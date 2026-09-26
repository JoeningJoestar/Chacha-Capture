-- Player Face Tracker
-- Drives LocalPlayer directly and sends only that player's flex weights to the server.

local enabledConVar = CreateClientConVar("facetracker_player_enabled", "0", true, false, "启用玩家面部捕捉")
local presetConVar = CreateClientConVar("facetracker_player_preset", "auto", true, false, "面部预设名称或 auto")
local strengthConVar = CreateClientConVar("facetracker_player_strength", "1", true, false, "Flex 强度", 0, 2)
local smoothingConVar = CreateClientConVar(
	"facetracker_player_smoothing",
	"18",
	true,
	false,
	"平滑速度，数值越大响应越快",
	1,
	60
)
local sendRateConVar = CreateClientConVar("facetracker_player_sendrate", "30", true, false, "多人同步帧率", 10, 30)
local reconnectConVar = CreateClientConVar("facetracker_player_reconnect", "1", true, false, "面捕服务断开后自动重连")
local facePac3ConVar = CreateClientConVar("facetracker_player_face_pac3", "0", true, false, "将面部 Flex 驱动到 PAC3 目标")
local posePac3ConVar = CreateClientConVar("facetracker_player_pose_pac3", "0", true, false, "将头部和身体骨骼驱动到 PAC3 目标")
local pac3TargetEntConVar = CreateClientConVar("facetracker_player_pac3_target_ent", "0", true, false, "PAC3 目标实体编号，0 为自动选择")
local pac3HeadBoneConVar = CreateClientConVar("facetracker_player_pac3_head_bone", "", true, false, "PAC3 目标头部骨骼名称")
local eyeHorizontalMirrorConVar = CreateClientConVar("facetracker_player_eye_mirror_horizontal", "1", true, false, "镜像眼睛水平方向")
local eyeVerticalMirrorConVar = CreateClientConVar("facetracker_player_eye_mirror_vertical", "0", true, false, "镜像眼睛竖直方向")

local PRESET_DIRECTORY = "facetracker/presets/"
local STATIC_PRESET_DIRECTORY = "data_static/facetracker/presets/"
local MANUAL_DIRECTORY = "facetracker/manual/"
local BUILTIN_PRESETS = { "facs", "hwm", "arkit" }
local FRAME_TIMEOUT = 1.5
local NETWORK_UNTOUCHED = 255
local NETWORK_MAX_VALUE = 254
local FLEX_OUTPUT_MAX = 2

local channelNames = FaceTracker.Parser.blendshapes
local state = {
	lastFrameAt = 0,
	lastSendAt = 0,
	sequence = 0,
	model = "",
	presetSetting = "",
	presetName = "",
	mapping = {},
	mappedIds = {},
	manualFlexes = {},
	manualInitialWeights = {},
	weights = {},
	initialWeights = {},
	eyeExpressions = {},
	eyeX = 0.5,
	eyeY = 0.5,
	initialEyeTarget = nil,
	hadFrame = false,
	timeoutSent = false,
	targetEntity = nil,
	targetKind = "player",
	targetScanAt = 0,
	manualKey = "",
}

local remotePlayers = {}

local function notify(message, kind)
	notification.AddLegacy(message, kind or NOTIFY_GENERIC, 5)
	MsgC(Color(90, 200, 255), "[茶茶捕捉·玩家] ", color_white, message .. "\n")
end

local function safeModelFileName(model)
	model = string.lower(string.Trim(tostring(model or "")))
	model = string.gsub(model, "[^%w%._%-]", "_")
	return model ~= "" and model or "default"
end

local function manualStorageKey(entity)
	local kind = state.targetKind == "pac3" and "pac3" or "player"
	local model = safeModelFileName(entity and entity.GetModel and entity:GetModel() or "")
	return kind .. "_" .. model
end

local function loadManualFlexes(entity)
	state.manualFlexes = {}
	state.manualInitialWeights = {}
	state.manualKey = ""
	if not IsValid(entity) or not entity.GetFlexNum then
		return
	end
	local key = manualStorageKey(entity)
	state.manualKey = key
	local path = MANUAL_DIRECTORY .. key .. ".txt"
	local decoded = util.JSONToTable(file.Read(path, "DATA") or "")
	if istable(decoded) then
		for name, value in pairs(decoded) do
			if isstring(name) and isnumber(tonumber(value)) then
				state.manualFlexes[name] = math.Clamp(tonumber(value), -1, FLEX_OUTPUT_MAX)
			end
		end
	end
	for id = 0, entity:GetFlexNum() - 1 do
		local name = entity:GetFlexName(id)
		if state.manualFlexes[name] and math.abs(state.manualFlexes[name]) > 0.0001 then
			state.manualInitialWeights[id] = entity:GetFlexWeight(id)
		end
	end
end

local function saveManualFlexes(entity)
	if not IsValid(entity) then
		return
	end
	file.CreateDir("facetracker")
	file.CreateDir(MANUAL_DIRECTORY)
	local values = {}
	for name, value in pairs(state.manualFlexes) do
		if isnumber(value) and math.abs(value) > 0.0001 then
			values[name] = math.Round(value, 4)
		end
	end
	local path = MANUAL_DIRECTORY .. (state.manualKey ~= "" and state.manualKey or manualStorageKey(entity)) .. ".txt"
	file.Write(path, util.TableToJSON(values, true))
end

local function readPreset(name)
	name = string.lower(string.Trim(name or ""))
	name = string.gsub(name, "%.txt$", "")
	-- Preserve spaces and UTF-8 names used by the original preset saver,
	-- while preventing path traversal when the name comes from a convar.
	name = string.gsub(name, "/", "_")
	name = string.gsub(name, "\\", "_")
	name = string.gsub(name, "%.%.", "")
	if name == "" then
		return
	end

	local raw = file.Read(PRESET_DIRECTORY .. name .. ".txt", "DATA")
	local decoded = raw and util.JSONToTable(raw)
	if not istable(decoded) then
		raw = file.Read(STATIC_PRESET_DIRECTORY .. name .. ".txt", "GAME")
		decoded = raw and util.JSONToTable(raw)
	end
	if not istable(decoded) then
		return
	end

	local expressions = decoded.expressions or decoded
	local eyeExpressions = decoded.eyeExpressions or {}
	if not istable(expressions) or not istable(eyeExpressions) then
		return
	end

	return expressions, eyeExpressions
end

local function scorePreset(entity, expressions)
	local score = 0
	local lowerExpressions = {}
	for name in pairs(expressions) do
		if isstring(name) then
			lowerExpressions[string.lower(name)] = true
		end
	end
	for id = 0, entity:GetFlexNum() - 1 do
		if lowerExpressions[string.lower(entity:GetFlexName(id))] then
			score = score + 1
		end
	end
	return score
end

local function choosePreset(entity)
	local requested = string.lower(string.Trim(presetConVar:GetString()))
	if requested ~= "" and requested ~= "auto" then
		local expressions, eyes = readPreset(requested)
		return requested, expressions, eyes
	end

	-- Prefer presets the user saved in DATA, then fall back to the three
	-- shipped standards. This makes the existing preset-saver workflow work
	-- without requiring a second manual copy.
	local candidates, seen = {}, {}
	local builtinNames = {}
	for _, name in ipairs(BUILTIN_PRESETS) do
		builtinNames[string.lower(name)] = true
	end
	local function appendPresetFiles(pattern, pathId)
		local files = file.Find(pattern, pathId) or {}
		table.sort(files)
		for _, fileName in ipairs(files) do
			local name = string.sub(fileName, 1, -5)
			local key = string.lower(name)
			if name ~= "" and not builtinNames[key] and not seen[key] then
				seen[key] = true
				table.insert(candidates, name)
			end
		end
	end
	appendPresetFiles(PRESET_DIRECTORY .. "*.txt", "DATA")
	appendPresetFiles(STATIC_PRESET_DIRECTORY .. "*.txt", "GAME")
	for _, name in ipairs(BUILTIN_PRESETS) do
		local key = string.lower(name)
		if not seen[key] then
			seen[key] = true
			table.insert(candidates, name)
		end
	end

	local bestName, bestExpressions, bestEyes, bestScore
	for _, name in ipairs(candidates) do
		local expressions, eyes = readPreset(name)
		if expressions then
			local score = scorePreset(entity, expressions)
			if not bestScore or score > bestScore then
				bestName, bestExpressions, bestEyes, bestScore = name, expressions, eyes, score
			end
		end
	end

	return bestName, bestExpressions, bestEyes, bestScore or 0
end

local function restoreTarget(entity, keepManual)
	if not IsValid(entity) then
		return
	end
	for _, item in ipairs(state.mapping) do
		if item.id < entity:GetFlexNum() then
			entity:SetFlexWeight(item.id, state.initialWeights[item.id] or 0)
		end
	end
	for id, value in pairs(state.manualInitialWeights) do
		if not keepManual and id < entity:GetFlexNum() then
			entity:SetFlexWeight(id, value or 0)
		end
	end
	if keepManual then
		-- Return live-tracking Flexes to their baseline, then re-apply the
		-- persistent manual offsets so a manual smile survives socket stops.
		for id = 0, entity:GetFlexNum() - 1 do
			local name = entity:GetFlexName(id)
			local manual = state.manualFlexes[name]
			if manual then
				local base = state.initialWeights[id]
					or state.manualInitialWeights[id]
					or entity:GetFlexWeight(id)
				entity:SetFlexWeight(id, math.Clamp(base + manual, 0, FLEX_OUTPUT_MAX))
			end
		end
	end
	if state.initialEyeTarget and entity.SetEyeTarget then
		entity:SetEyeTarget(state.initialEyeTarget)
	end
	state.weights = {}
	state.initialWeights = {}
	if not keepManual then
		state.manualFlexes = {}
		state.manualInitialWeights = {}
	end
	state.initialEyeTarget = nil
	state.hadFrame = false
	state.timeoutSent = false
end

local function partEntity(part)
	if not part then return end
	if IsValid(part) and (part.GetFlexNum or part.GetBoneCount) then return part end
	if part.GetEntity then
		local ok, entity = pcall(part.GetEntity, part)
		if ok and IsValid(entity) and (entity.GetFlexNum or entity.GetBoneCount) then return entity end
	end
	for _, key in ipairs({ "Entity", "entity", "ent", "_entity" }) do
		local entity = part[key]
		if IsValid(entity) and (entity.GetFlexNum or entity.GetBoneCount) then return entity end
	end
end

local function findPac3Candidates(requireFlex)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local headBone = ply:LookupBone("ValveBiped.Bip01_Head1") or ply:LookupBone("ValveBiped.Bip01_Head")
	local headPos = ply:EyePos()
	if headBone then
		local bonePos = select(1, ply:GetBonePosition(headBone))
		if isvector(bonePos) then headPos = bonePos end
	end
	local candidates, seen = {}, {}
	local function add(entity)
		if not IsValid(entity) or entity == ply or seen[entity] then return end
		if not entity.GetModel or (entity:GetModel() or "") == "" then return end
		local flexCount = entity.GetFlexNum and entity:GetFlexNum() or 0
		local boneCount = entity.GetBoneCount and entity:GetBoneCount() or 0
		if requireFlex and flexCount <= 0 then return end
		if not requireFlex and flexCount <= 0 and boneCount <= 0 then return end
		seen[entity] = true
		table.insert(candidates, entity)
	end
	if pac and pac.GetParts then
		local ok, parts = pcall(pac.GetParts, ply)
		if ok and istable(parts) then
			for _, part in pairs(parts) do
				if istable(part) and part.GetParts then
					local okNested, nested = pcall(part.GetParts, part)
					if okNested and istable(nested) then for _, child in pairs(nested) do add(partEntity(child)) end end
				end
				add(partEntity(part))
			end
		end
	end
	for _, entity in ipairs(ents.GetAll()) do
		if IsValid(entity) and entity ~= ply and entity.GetModel then
			if entity:GetPos():DistToSqr(headPos) <= (110 * 110) then
				local owner = entity.GetOwner and entity:GetOwner() or nil
				if not IsValid(owner) or owner == ply then add(entity) end
			end
		end
	end
	table.sort(candidates, function(a, b)
		local ad = a:GetPos():DistToSqr(headPos)
		local bd = b:GetPos():DistToSqr(headPos)
		local af = a.GetFlexNum and a:GetFlexNum() or 0
		local bf = b.GetFlexNum and b:GetFlexNum() or 0
		local ab = a.GetBoneCount and a:GetBoneCount() or 0
		local bb = b.GetBoneCount and b:GetBoneCount() or 0
		return (af * 1000 + ab * 10 - ad) > (bf * 1000 + bb * 10 - bd)
	end)
	return candidates
end

local function findPac3Target(requireFlex)
	local requested = pac3TargetEntConVar:GetInt()
	if requested > 0 then
		local entity = Entity(requested)
		if IsValid(entity) and entity ~= LocalPlayer() then
			local flexCount = entity.GetFlexNum and entity:GetFlexNum() or 0
			local boneCount = entity.GetBoneCount and entity:GetBoneCount() or 0
			if (requireFlex and flexCount > 0) or (not requireFlex and (flexCount > 0 or boneCount > 0)) then
				return entity
			end
		end
	end
	return findPac3Candidates(requireFlex)[1]
end

local function resolveFaceTarget()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	if not facePac3ConVar:GetBool() then return ply, "player" end
	local requested = pac3TargetEntConVar:GetInt()
	if requested > 0 then
		local selected = Entity(requested)
		if IsValid(selected) and selected ~= ply and selected.GetFlexNum and selected:GetFlexNum() > 0 then
			return selected, "pac3"
		end
	end
	if RealTime() < (state.targetScanAt or 0) and IsValid(state.targetEntity) then
		return state.targetEntity, state.targetKind
	end
	state.targetScanAt = RealTime() + 0.5
	local target = findPac3Target(true)
	if IsValid(target) then return target, "pac3" end
	return ply, "player"
end

local function resolvePoseTarget()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	if not posePac3ConVar:GetBool() then return ply, "player" end
	local requested = pac3TargetEntConVar:GetInt()
	if requested > 0 then
		local selected = Entity(requested)
		if IsValid(selected) and selected ~= ply then
			local flexCount = selected.GetFlexNum and selected:GetFlexNum() or 0
			local boneCount = selected.GetBoneCount and selected:GetBoneCount() or 0
			if flexCount > 0 or boneCount > 0 then
				return selected, "pac3"
			end
		end
	end
	-- Never auto-select a PAC3 part for pose capture. PAC3 can create valid
	-- clientside model entities for lighting, bones, or an otherwise empty
	-- group; driving one of those silently steals head capture from the player.
	-- A PAC3 pose target must therefore be explicitly selected in the UI.
	return ply, "player"
end

local function rebuildMapping(entity)
	-- Preset changes reuse the same entity. Restore every previously edited
	-- Flex first so an old manual offset cannot be captured as the new
	-- baseline. A model change is intentionally left alone because its Flex
	-- indices may already refer to a different model.
	if state.model ~= "" and state.model == (entity:GetModel() or "") then
		restoreTarget(entity, false)
	end

	state.mapping = {}
	state.mappedIds = {}
	state.manualFlexes = {}
	state.manualInitialWeights = {}
	state.weights = {}
	state.initialWeights = {}
	state.initialEyeTarget = nil
	state.eyeExpressions = {}
	state.hadFrame = false
	state.model = entity:GetModel() or ""
	state.presetSetting = presetConVar:GetString()
	loadManualFlexes(entity)

	local presetName, expressions, eyeExpressions, score = choosePreset(entity)
	if not expressions then
		state.presetName = ""
		notify("找不到预设 '" .. state.presetSetting .. "'。请检查 garrysmod/data/facetracker/presets。", NOTIFY_ERROR)
		return false
	end

	local caseInsensitive = {}
	for flexName, expression in pairs(expressions) do
		if isstring(flexName) then
			caseInsensitive[string.lower(flexName)] = expression
		end
	end

	for id = 0, entity:GetFlexNum() - 1 do
		local flexName = entity:GetFlexName(id)
		-- Keep a stable pre-manual baseline for every Flex, including Flexes
		-- that are not mapped by the active live-tracking preset.
		state.initialWeights[id] = entity:GetFlexWeight(id)
		local expression = expressions[flexName] or caseInsensitive[string.lower(flexName)]
		if isnumber(expression) then
			expression = tostring(expression)
		end
		if isstring(expression) and expression ~= "" then
			table.insert(state.mapping, {
				id = id,
				name = flexName,
				expression = expression,
			})
			state.mappedIds[id] = true
			state.weights[id] = entity:GetFlexWeight(id)
			state.initialWeights[id] = entity:GetFlexWeight(id)
		end
	end

	state.presetName = presetName
	state.eyeExpressions = eyeExpressions
	if entity.GetEyeTarget then
		state.initialEyeTarget = entity:GetEyeTarget()
	end
	if #state.mapping == 0 then
		notify("预设 '" .. presetName .. "' 与当前玩家模型没有同名 Flex。", NOTIFY_ERROR)
		return false
	end

	return true
end

-- Resolve the current face target for tools such as the manual Flex editor.
-- This deliberately does not require the face-tracking socket to be running.
local function ensureFaceTarget()
	local target, kind = resolveFaceTarget()
	if not IsValid(target) or not target.GetFlexNum then
		return
	end
	if state.targetEntity ~= target then
		if IsValid(state.targetEntity) then
			restoreTarget(state.targetEntity)
		end
		state.targetEntity = target
		state.targetKind = kind or "player"
		state.manualKey = ""
		state.model = ""
	end
	if state.model ~= (target:GetModel() or "") or state.presetSetting ~= presetConVar:GetString() then
		rebuildMapping(target)
	end
	return target, state.targetKind
end

local function decodeFrame(text)
	local decoded = util.JSONToTable(text)
	if not istable(decoded) then
		return
	end
	local source = istable(decoded.blendshapes) and decoded.blendshapes or decoded

	local coefficients = {}
	if isnumber(source[1]) then
		for i = 1, #channelNames do
			coefficients[i] = tonumber(source[i]) or 0
		end
	else
		-- Also accept the named-object format emitted by compatible trackers.
		for i, name in ipairs(channelNames) do
			coefficients[i] = tonumber(source[name]) or 0
		end
	end

	FaceTracker.Parser:updateVariables(coefficients)
	state.lastFrameAt = RealTime()
	state.hadFrame = true
	state.timeoutSent = false
end

local function solve(expression, fallback)
	if isnumber(expression) then
		return expression
	end
	if not isstring(expression) then
		return fallback or 0
	end
	local ok, value = pcall(FaceTracker.Parser.solve, FaceTracker.Parser, expression)
	if not ok or not isnumber(value) or value ~= value or value == math.huge or value == -math.huge then
		return fallback or 0
	end
	return value
end

local function updateEyeTarget(ply)
	local eyes = state.eyeExpressions
	local x = eyes.x and solve(eyes.x, 0.5) or 0.5
	local y = eyes.y and solve(eyes.y, 0.5) or 0.5
	-- Eye gaze uses the same camera-to-third-person rule as neck yaw: only
	-- horizontal is mirrored by default; pitch stays natural.
	state.eyeX = math.Clamp(eyeHorizontalMirrorConVar:GetBool() and (1 - x) or x, 0, 1)
	state.eyeY = math.Clamp(eyeVerticalMirrorConVar:GetBool() and (1 - y) or y, 0, 1)
	local direction = Angle((state.eyeY - 0.5) * 90, (state.eyeX - 0.5) * 90, 0):Forward()
	if ply.SetEyeTarget then
		ply:SetEyeTarget(direction * 1000)
	end
end

local function sendFrame(ply)
	if ply ~= LocalPlayer() then
		return
	end
	local now = RealTime()
	local interval = 1 / math.max(sendRateConVar:GetFloat(), 1)
	if now - state.lastSendAt < interval then
		return
	end
	state.lastSendAt = now
	state.sequence = (state.sequence + 1) % 65536

	local mapped = {}
	for _, item in ipairs(state.mapping) do
		mapped[item.id] = true
	end

	local count = math.min(ply:GetFlexNum(), 255)
	net.Start("facetracker_player_frame", true)
	net.WriteUInt(state.sequence, 16)
	net.WriteUInt(count, 8)
	for id = 0, count - 1 do
		if mapped[id] then
			local quantized = math.floor(math.Clamp(state.weights[id] or 0, 0, 1) * NETWORK_MAX_VALUE + 0.5)
			net.WriteUInt(quantized, 8)
		else
			net.WriteUInt(NETWORK_UNTOUCHED, 8)
		end
	end
	net.WriteUInt(math.floor(state.eyeX * NETWORK_MAX_VALUE + 0.5), 8)
	net.WriteUInt(math.floor(state.eyeY * NETWORK_MAX_VALUE + 0.5), 8)
	net.SendToServer()
end

local function stopBroadcast()
	if not IsValid(LocalPlayer()) then
		return
	end
	net.Start("facetracker_player_stop")
	net.SendToServer()
end

local function clearRemote(ply, remote)
	if not remote or not IsValid(ply) then
		return
	end
	local baseline = remote.baseline or {}
	for id in pairs(remote.touched) do
		if id < ply:GetFlexNum() then
			ply:SetFlexWeight(id, baseline[id] or 0)
		end
	end
end

local function start()
	if FaceTracker.Socket.isAvailable and not FaceTracker.Socket:isAvailable() then
		notify("GWSockets 未加载，无法连接面捕。请安装 64 位客户端 DLL gmcl_gwsockets_win64.dll，然后重启 GMod。", NOTIFY_ERROR)
		local socketDetail = FaceTracker.Socket.getError and FaceTracker.Socket:getError() or "unknown"
		print("[茶茶捕捉·玩家] GWSockets 错误：" .. tostring(socketDetail))
		return false
	end
	RunConsoleCommand("facetracker_player_enabled", "1")
	local target, kind = resolveFaceTarget()
	if IsValid(target) then
		state.targetEntity = target
		state.targetKind = kind
		rebuildMapping(target)
	end
	if FaceTracker.Pose and FaceTracker.Pose.Begin then
		FaceTracker.Pose.Begin()
	end
	FaceTracker.Socket:connect()
	notify("玩家面捕已启用；正在连接本机 8667 端口。")
	return true
end

local function stop()
	RunConsoleCommand("facetracker_player_enabled", "0")
	restoreTarget(state.targetEntity or LocalPlayer(), true)
	state.targetEntity = nil
	state.targetKind = "player"
	state.targetScanAt = 0
	state.manualKey = ""
	if FaceTracker.Pose and FaceTracker.Pose.Reset then
		FaceTracker.Pose.Reset()
	end
	stopBroadcast()
	FaceTracker.Socket:disconnect()
	notify("玩家面捕已停止。")
end

FaceTracker.Socket:addListener("message", "player_mode", decodeFrame)
FaceTracker.Socket:addListener("connected", "player_mode", function()
	if enabledConVar:GetBool() then
		notify("已连接面捕程序。", NOTIFY_HINT)
	end
end)
FaceTracker.Socket:addListener("disconnected", "player_mode", function()
	if not enabledConVar:GetBool() or not reconnectConVar:GetBool() then
		return
	end
	timer.Create("facetracker_player_reconnect", 3, 1, function()
		if enabledConVar:GetBool() and not FaceTracker.Socket:isConnected() then
			FaceTracker.Socket:connect()
		end
	end)
end)

hook.Add("Think", "facetracker_player_update", function()
	if not enabledConVar:GetBool() then
		return
	end

	local player = LocalPlayer()
	if not IsValid(player) then
		return
	end
	local targetEntity, kind = resolveFaceTarget()
	if not IsValid(targetEntity) then return end
	if state.targetEntity ~= targetEntity then
		restoreTarget(state.targetEntity)
		state.targetEntity = targetEntity
		state.targetKind = kind
		state.manualKey = ""
		state.model = ""
		notify(kind == "pac3" and "已锁定 PAC3 头部作为面捕目标。" or "已锁定玩家模型作为面捕目标。", NOTIFY_HINT)
	end

	if state.model ~= (targetEntity:GetModel() or "") or state.presetSetting ~= presetConVar:GetString() then
		rebuildMapping(targetEntity)
	end

	local alpha = 1 - math.exp(-smoothingConVar:GetFloat() * FrameTime())
	if RealTime() - state.lastFrameAt > FRAME_TIMEOUT then
		for _, item in ipairs(state.mapping) do
			local targetValue = math.Clamp((state.initialWeights[item.id] or 0) + (state.manualFlexes[item.name] or 0), 0, FLEX_OUTPUT_MAX)
			state.weights[item.id] = Lerp(alpha, state.weights[item.id] or targetValue, targetValue)
			if item.id < targetEntity:GetFlexNum() then targetEntity:SetFlexWeight(item.id, state.weights[item.id]) end
		end
		for id = 0, targetEntity:GetFlexNum() - 1 do
			local name = targetEntity:GetFlexName(id)
			local manualValue = state.manualFlexes[name]
			if manualValue then
				local targetValue = math.Clamp((state.initialWeights[id] or 0) + manualValue, 0, FLEX_OUTPUT_MAX)
				targetEntity:SetFlexWeight(id, Lerp(alpha, targetEntity:GetFlexWeight(id), targetValue))
			end
		end
		if not state.timeoutSent then
			stopBroadcast()
			state.timeoutSent = true
		end
		return
	end

	local strength = strengthConVar:GetFloat()
	for _, item in ipairs(state.mapping) do
		local manualValue = state.manualFlexes[item.name] or 0
		local targetValue = math.Clamp(solve(item.expression, state.weights[item.id]) * strength + manualValue, 0, FLEX_OUTPUT_MAX)
		state.weights[item.id] = Lerp(alpha, state.weights[item.id] or targetValue, targetValue)
		if item.id < targetEntity:GetFlexNum() then targetEntity:SetFlexWeight(item.id, state.weights[item.id]) end
	end
	for id = 0, targetEntity:GetFlexNum() - 1 do
		local name = targetEntity:GetFlexName(id)
		local manualValue = state.manualFlexes[name]
		if manualValue and not state.mappedIds[id] then
			local targetValue = math.Clamp((state.initialWeights[id] or 0) + manualValue, 0, FLEX_OUTPUT_MAX)
			targetEntity:SetFlexWeight(id, Lerp(alpha, targetEntity:GetFlexWeight(id), targetValue))
		end
	end
	updateEyeTarget(targetEntity)
	sendFrame(targetEntity)
end)

hook.Add("PrePlayerDraw", "facetracker_player_remote_draw", function(ply)
	local remote = remotePlayers[ply]
	if not remote then
		return
	end
	if RealTime() - remote.receivedAt > FRAME_TIMEOUT then
		clearRemote(ply, remote)
		remotePlayers[ply] = nil
		return
	end
	if remote.count ~= math.min(ply:GetFlexNum(), 255) then
		clearRemote(ply, remote)
		remotePlayers[ply] = nil
		return
	end
	for id = 0, remote.count - 1 do
		local value = remote.values[id + 1]
		if value and value < NETWORK_UNTOUCHED then
			ply:SetFlexWeight(id, value / NETWORK_MAX_VALUE)
		end
	end
	local direction = Angle((remote.eyeY - 0.5) * 90, (remote.eyeX - 0.5) * 90, 0):Forward()
	ply:SetEyeTarget(direction * 1000)
end)

net.Receive("facetracker_player_frame", function()
	local ply = net.ReadEntity()
	local sequence = net.ReadUInt(16)
	local count = net.ReadUInt(8)
	if not IsValid(ply) or not ply:IsPlayer() or count > 255 then
		return
	end

	local values, touched = {}, {}
	for i = 1, count do
		values[i] = net.ReadUInt(8)
		if values[i] < NETWORK_UNTOUCHED then
			touched[i - 1] = true
		end
	end
	local previous = remotePlayers[ply]
	if previous and previous.sequence then
		local difference = (sequence - previous.sequence) % 65536
		if difference == 0 or difference >= 32768 then
			return
		end
	end
	clearRemote(ply, previous)
	local baseline = previous and previous.baseline or {}
	for id in pairs(touched) do
		if baseline[id] == nil then
			baseline[id] = ply:GetFlexWeight(id)
		end
	end
	remotePlayers[ply] = {
		sequence = sequence,
		count = count,
		values = values,
		touched = touched,
		baseline = baseline,
		eyeX = net.ReadUInt(8) / NETWORK_MAX_VALUE,
		eyeY = net.ReadUInt(8) / NETWORK_MAX_VALUE,
		receivedAt = RealTime(),
	}
end)

net.Receive("facetracker_player_stop", function()
	local ply = net.ReadEntity()
	local remote = remotePlayers[ply]
	clearRemote(ply, remote)
	remotePlayers[ply] = nil
end)

concommand.Add("facetracker_player_start", start)
concommand.Add("face_tracker_start", start)
concommand.Add("facetracker_player_stop", stop)
concommand.Add("face_tracker_stop", stop)
concommand.Add("facetracker_player_toggle", function()
	if enabledConVar:GetBool() then
		stop()
	else
		start()
	end
end)
concommand.Add("facetracker_player_status", function()
	local connection = FaceTracker.Socket:isConnected() and "connected" or "disconnected"
	local age = state.hadFrame and Format("%.2fs", RealTime() - state.lastFrameAt) or "never"
	local poseTracking = FaceTracker.Pose and FaceTracker.Pose.IsTracking and FaceTracker.Pose.IsTracking() or false
	local poseBones = FaceTracker.Pose and FaceTracker.Pose.GetTrackedBoneCount and FaceTracker.Pose.GetTrackedBoneCount() or 0
	local bonePreset = FaceTracker.Pose and FaceTracker.Pose.GetBonePresetName and FaceTracker.Pose.GetBonePresetName() or "none"
	local faceTarget, faceKind = resolveFaceTarget()
	local poseTarget, poseKind = resolvePoseTarget()
	print(Format(
		"[茶茶捕捉] enabled=%s socket=%s available=%s face_target=%s face_model=%s flex_preset=%s mapped=%d pose_target=%s pose_model=%s pose=%s bone_preset=%s bones=%d/12 last_frame=%s",
		tostring(enabledConVar:GetBool()),
		connection,
		tostring(not FaceTracker.Socket.isAvailable or FaceTracker.Socket:isAvailable()),
		faceKind,
		IsValid(faceTarget) and faceTarget:GetModel() or "none",
		state.presetName ~= "" and state.presetName or "none",
		#state.mapping,
		poseKind,
		IsValid(poseTarget) and poseTarget:GetModel() or "none",
		tostring(poseTracking),
		bonePreset,
		poseBones,
		age
	))
end)
concommand.Add("facetracker_player_dumpflexes", function()
	local target = state.targetEntity
	if not IsValid(target) then target = resolveFaceTarget() end
	if not IsValid(target) then
		print("[茶茶捕捉·玩家] 面捕目标尚未找到")
		return
	end
	local lines = {
		"target=" .. tostring(state.targetKind),
		"model=" .. tostring(target:GetModel()),
		"flex_count=" .. tostring(target:GetFlexNum()),
	}
	for id = 0, target:GetFlexNum() - 1 do
		table.insert(lines, Format("%d\t%s\t%.6f", id, target:GetFlexName(id), target:GetFlexWeight(id)))
	end
	file.CreateDir("facetracker")
	file.Write("facetracker/player_flexes.txt", table.concat(lines, "\n"))
	print("[茶茶捕捉·玩家] 已写入 data/facetracker/player_flexes.txt")
end)
concommand.Add("facetracker_player_pac3_target", function()
	local target, kind = resolveFaceTarget()
	if IsValid(target) then
		print(Format("[茶茶捕捉·玩家] target=%s model=%s flexes=%d index=%s", kind, target:GetModel() or "", target:GetFlexNum(), tostring(target:EntIndex())))
	else
		print("[茶茶捕捉·玩家] 未找到带 Flex 的 PAC3 头部部件")
	end
end)

hook.Add("InitPostEntity", "facetracker_player_autostart", function()
	if enabledConVar:GetBool() then
		timer.Simple(1, function()
			if enabledConVar:GetBool() then
				start()
			end
		end)
	end
end)

FaceTracker.Player = {
	Start = start,
	Stop = stop,
	RebuildMapping = rebuildMapping,
	GetTargetEntity = function()
		local target = ensureFaceTarget()
		return IsValid(target) and target or LocalPlayer()
	end,
	GetFaceTargetEntity = function()
		local target = ensureFaceTarget()
		return IsValid(target) and target or nil
	end,
	RefreshFaceTarget = function()
		local target, kind = ensureFaceTarget()
		return IsValid(target) and target or nil, kind
	end,
	GetPoseTargetEntity = function()
		local target = resolvePoseTarget()
		return IsValid(target) and target or LocalPlayer()
	end,
	GetFaceTargetKind = function()
		local _, kind = resolveFaceTarget()
		return kind
	end,
	GetPoseTargetKind = function()
		local _, kind = resolvePoseTarget()
		return kind
	end,
	GetTargetKind = function()
		return state.targetKind
	end,
	GetPac3Candidates = function()
		return findPac3Candidates(false) or {}
	end,
	GetPac3Bones = function(entity)
		local result = {}
		if not IsValid(entity) or not entity.GetBoneCount then return result end
		for id = 0, entity:GetBoneCount() - 1 do
			local name = entity:GetBoneName(id)
			if isstring(name) and name ~= "" and name ~= "__INVALIDBONE__" then
				table.insert(result, {id = id, name = name})
			end
		end
		return result
	end,
	GetPac3HeadBone = function()
		local name = string.Trim(pac3HeadBoneConVar:GetString() or "")
		return name ~= "" and name or nil
	end,
	GetPresetName = function()
		return state.presetName
	end,
	GetMappedFlexCount = function()
		return #state.mapping
	end,
	GetManualFlexes = function()
		ensureFaceTarget()
		return table.Copy(state.manualFlexes)
	end,
	GetFlexes = function()
		local entity = ensureFaceTarget()
		local result = {}
		if not IsValid(entity) or not entity.GetFlexNum then return result end
		for id = 0, entity:GetFlexNum() - 1 do
			local name = entity:GetFlexName(id)
			table.insert(result, {
				id = id,
				name = name,
				weight = entity:GetFlexWeight(id) or 0,
				manual = state.manualFlexes[name] or 0,
				mapped = state.mappedIds[id] == true,
			})
		end
		return result
	end,
	SetManualFlex = function(name, value)
		local entity = ensureFaceTarget()
		if not IsValid(entity) or not entity.GetFlexNum or not isstring(name) then
			return false
		end
		local id = nil
		for flexId = 0, entity:GetFlexNum() - 1 do
			if entity:GetFlexName(flexId) == name then
				id = flexId
				break
			end
		end
		if not id then return false end
		value = math.Clamp(tonumber(value) or 0, -1, FLEX_OUTPUT_MAX)
		state.manualFlexes[name] = math.abs(value) > 0.0001 and value or nil
		if state.manualInitialWeights[id] == nil then
			state.manualInitialWeights[id] = state.initialWeights[id] or entity:GetFlexWeight(id)
		end
		if not state.manualFlexes[name] then
			local baseline = state.initialWeights[id] or state.manualInitialWeights[id] or 0
			entity:SetFlexWeight(id, math.Clamp(baseline, 0, FLEX_OUTPUT_MAX))
			state.manualInitialWeights[id] = nil
		end
		saveManualFlexes(entity)
		return true
	end,
	ClearManualFlexes = function()
		local entity = ensureFaceTarget()
		state.manualFlexes = {}
		if IsValid(entity) then
			for id = 0, entity:GetFlexNum() - 1 do
				if state.manualInitialWeights[id] ~= nil then
					entity:SetFlexWeight(id, math.Clamp(state.manualInitialWeights[id], 0, FLEX_OUTPUT_MAX))
				end
			end
			saveManualFlexes(entity)
		end
		state.manualInitialWeights = {}
	end,
}
