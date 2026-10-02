-- 茶茶捕捉: head, waist, arm and wrist bone driver.

local poseEnabledConVar = CreateClientConVar("facetracker_player_pose_enabled", "1", true, false, "启用玩家姿态捕捉")
local headEnabledConVar = CreateClientConVar("facetracker_player_head_enabled", "1", true, false, "启用头部和颈部捕捉")
local upperEnabledConVar = CreateClientConVar("facetracker_player_upperbody_enabled", "0", true, false, "启用腰部、手臂和手腕捕捉")
local strengthConVar = CreateClientConVar("facetracker_player_pose_strength", "1.25", true, false, "姿态幅度", 0, 2)
local smoothingConVar = CreateClientConVar("facetracker_player_pose_smoothing", "24", true, false, "姿态平滑速度", 1, 60)
local sendRateConVar = CreateClientConVar("facetracker_player_pose_sendrate", "30", true, false, "姿态同步帧率", 15, 30)
local horizontalMirrorConVar = CreateClientConVar("facetracker_player_pose_mirror_horizontal", "1", true, false, "镜像左右方向")
local verticalMirrorConVar = CreateClientConVar("facetracker_player_pose_mirror_vertical", "0", true, false, "镜像上下方向")
local bonePresetConVar = CreateClientConVar("facetracker_player_bone_preset", "auto", true, false, "骨骼映射预设名称或 auto")
local tuningVersionConVar = CreateClientConVar("facetracker_player_pose_tuning_version", "0", true, false, "姿态参数迁移版本")
local mappingVersionConVar = CreateClientConVar("facetracker_player_pose_mapping_version", "0", true, false, "姿态映射迁移版本")

-- Older installs saved the heavier 1.0/14 defaults. Migrate only
-- those exact old defaults, preserving values that the player tuned manually.
if tuningVersionConVar:GetInt() < 1 then
	if math.abs(strengthConVar:GetFloat() - 1) < 0.001 then
		RunConsoleCommand("facetracker_player_pose_strength", "1.25")
	end
	if math.abs(smoothingConVar:GetFloat() - 14) < 0.001 then
		RunConsoleCommand("facetracker_player_pose_smoothing", "24")
	end
	RunConsoleCommand("facetracker_player_pose_tuning_version", "1")
end

-- Migrate older installs to the formal third-person default once.
if mappingVersionConVar:GetInt() < 2 then
	RunConsoleCommand("facetracker_player_pose_mirror_horizontal", "1")
	RunConsoleCommand("facetracker_player_pose_mirror_vertical", "0")
	RunConsoleCommand("facetracker_player_pose_mapping_version", "2")
end

local FRAME_TIMEOUT = 1.5
local NETWORK_SCALE = 100
local BONE_PRESET_DIRECTORY = "facetracker/bones/"
local STATIC_BONE_PRESET_DIRECTORY = "data_static/facetracker/bones/"
local POSE_KEYS = {
	"head",
	"neck",
	"waist",
	"spine",
	"left_clavicle",
	"left_upper_arm",
	"left_forearm",
	"left_wrist",
	"right_clavicle",
	"right_upper_arm",
	"right_forearm",
	"right_wrist",
}

local BODY_KEYS = {
	"waist",
	"spine",
	"left_clavicle",
	"left_upper_arm",
	"left_forearm",
	"left_wrist",
	"right_clavicle",
	"right_upper_arm",
	"right_forearm",
	"right_wrist",
}

local BONE_CONFIG = {
	head = {
		names = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Head" },
		limits = Angle(60, 80, 45),
	},
	neck = {
		names = { "ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Neck" },
		limits = Angle(25, 35, 25),
	},
	waist = {
		names = { "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Pelvis" },
		limits = Angle(30, 35, 25),
	},
	spine = {
		names = { "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine1" },
		limits = Angle(35, 45, 35),
	},
	left_clavicle = {
		names = { "ValveBiped.Bip01_L_Clavicle" },
		limits = Angle(35, 45, 30),
	},
	left_upper_arm = {
		names = { "ValveBiped.Bip01_L_UpperArm" },
		limits = Angle(90, 115, 45),
	},
	left_forearm = {
		names = { "ValveBiped.Bip01_L_Forearm" },
		limits = Angle(125, 65, 35),
	},
	left_wrist = {
		names = { "ValveBiped.Bip01_L_Hand" },
		limits = Angle(35, 70, 60),
	},
	right_clavicle = {
		names = { "ValveBiped.Bip01_R_Clavicle" },
		limits = Angle(35, 45, 30),
	},
	right_upper_arm = {
		names = { "ValveBiped.Bip01_R_UpperArm" },
		limits = Angle(90, 115, 45),
	},
	right_forearm = {
		names = { "ValveBiped.Bip01_R_Forearm" },
		limits = Angle(125, 65, 35),
	},
	right_wrist = {
		names = { "ValveBiped.Bip01_R_Hand" },
		limits = Angle(35, 70, 60),
	},
}

local state = {
	model = "",
	presetSetting = "",
	presetName = "",
	mapping = {},
	overrideMapping = nil,
	mappingDirty = true,
	bones = {},
	baselineBones = {},
	-- Keep the PAC3/model angle separate from our current pose contribution.
	-- PAC3 may update the same bone for animation or keybinds every frame.
	externalBoneAngles = {},
	appliedBoneAngles = {},
	raw = {},
	calibration = {},
	current = {},
	target = {},
	lastFrameAt = 0,
	lastSendAt = 0,
	sequence = 0,
	tracking = false,
	bodyChannels = 0,
	needsCalibration = true,
	restored = true,
	stopSent = true,
	targetEntity = nil,
	headBoneSetting = "",
}

local remotePoses = {}

local function copyAngle(value)
	return Angle(value and value.p or 0, value and value.y or 0, value and value.r or 0)
end

local function readTriple(value)
	if not istable(value) then
		return
	end
	local pitch = tonumber(value[1])
	local yaw = tonumber(value[2])
	local roll = tonumber(value[3])
	if not pitch or not yaw or not roll then
		return
	end
	return Angle(pitch, yaw, roll)
end

local function angleDifference(current, baseline)
	return Angle(
		math.AngleDifference(current.p, baseline.p),
		math.AngleDifference(current.y, baseline.y),
		math.AngleDifference(current.r, baseline.r)
	)
end

local function clampAngle(value, limits)
	return Angle(
		math.Clamp(value.p, -limits.p, limits.p),
		math.Clamp(value.y, -limits.y, limits.y),
		math.Clamp(value.r, -limits.r, limits.r)
	)
end

local function addAngles(first, second)
	return Angle(first.p + second.p, first.y + second.y, first.r + second.r)
end

local function sameAngle(first, second)
	if not first or not second then return false end
	return math.abs(math.AngleDifference(first.p, second.p)) < 0.01
		and math.abs(math.AngleDifference(first.y, second.y)) < 0.01
		and math.abs(math.AngleDifference(first.r, second.r)) < 0.01
end

local function isZeroAngle(value)
	return not value or (math.abs(value.p) < 0.01 and math.abs(value.y) < 0.01 and math.abs(value.r) < 0.01)
end

-- PAC3 can write a new ManipulateBoneAngles value between our updates. If the
-- live value still equals our last output, retain the remembered external
-- angle; otherwise treat the live value as PAC3's latest animation/keybind
-- angle before adding our own offset.
local function getExternalBoneAngle(entity, boneId, key)
	local live = copyAngle(entity:GetManipulateBoneAngles(boneId))
	local previous = state.appliedBoneAngles[key]
	if not state.externalBoneAngles[key] or not sameAngle(live, previous) then
		state.externalBoneAngles[key] = live
	end
	return copyAngle(state.externalBoneAngles[key])
end

local function releasePoseContribution(entity)
	if not IsValid(entity) then return end
	for key, bone in pairs(state.bones or {}) do
		if bone.id and state.appliedBoneAngles[key] then
			local external = getExternalBoneAngle(entity, bone.id, key)
			entity:ManipulateBoneAngles(bone.id, external)
			state.appliedBoneAngles[key] = nil
		end
	end
	state.externalBoneAngles = {}
	state.appliedBoneAngles = {}
end

local findBone

local function sanitizePresetName(name)
	name = string.Trim(tostring(name or ""))
	name = string.gsub(name, "%.txt$", "")
	name = string.gsub(name, "/", "_")
	name = string.gsub(name, "\\", "_")
	name = string.gsub(name, "%.%.", "")
	return name
end

local function normalizeMapping(bones, useDefaults)
	local mapping = {}
	bones = istable(bones) and bones or {}
	for _, key in ipairs(POSE_KEYS) do
		local value = bones[key]
		local names = {}
		if isstring(value) and value ~= "" then
			table.insert(names, value)
		elseif istable(value) then
			for _, name in ipairs(value) do
				if isstring(name) and name ~= "" then
					table.insert(names, name)
				end
			end
		end
		if #names == 0 and useDefaults then
			names = table.Copy(BONE_CONFIG[key].names)
		end
		mapping[key] = names
	end
	return mapping
end

local function readBonePreset(name)
	name = sanitizePresetName(name)
	if name == "" then
		return
	end
	local raw = file.Read(BONE_PRESET_DIRECTORY .. name .. ".txt", "DATA")
	local decoded = raw and util.JSONToTable(raw)
	if not istable(decoded) then
		raw = file.Read(STATIC_BONE_PRESET_DIRECTORY .. name .. ".txt", "GAME")
		decoded = raw and util.JSONToTable(raw)
	end
	if not istable(decoded) or not istable(decoded.bones) then
		return
	end
	return normalizeMapping(decoded.bones), decoded
end

local function listBonePresets()
	local names, seen = {}, {}
	local function append(pattern, pathId)
		local files = file.Find(pattern, pathId) or {}
		table.sort(files)
		for _, fileName in ipairs(files) do
			local name = string.sub(fileName, 1, -5)
			local lower = string.lower(name)
			if name ~= "" and not seen[lower] then
				seen[lower] = true
				table.insert(names, name)
			end
		end
	end
	append(BONE_PRESET_DIRECTORY .. "*.txt", "DATA")
	append(STATIC_BONE_PRESET_DIRECTORY .. "*.txt", "GAME")
	return names
end

local function scoreMapping(entity, mapping)
	local score = 0
	for _, key in ipairs(POSE_KEYS) do
		local id = findBone(entity, mapping[key])
		if id then
			score = score + 1
		end
	end
	return score
end

local function chooseBonePreset(entity)
	local requested = sanitizePresetName(bonePresetConVar:GetString())
	if requested ~= "" and string.lower(requested) ~= "auto" then
		local mapping = readBonePreset(requested)
		return requested, mapping, mapping and scoreMapping(entity, mapping) or 0
	end

	local bestName, bestMapping, bestScore
	for _, name in ipairs(listBonePresets()) do
		local mapping = readBonePreset(name)
		if mapping then
			local score = scoreMapping(entity, mapping)
			if not bestScore or score > bestScore then
				bestName, bestMapping, bestScore = name, mapping, score
			end
		end
	end
	if bestMapping then
		return bestName, bestMapping, bestScore
	end
	local fallback = {}
	for _, key in ipairs(POSE_KEYS) do
		fallback[key] = table.Copy(BONE_CONFIG[key].names)
	end
	return "valvebiped", fallback, scoreMapping(entity, fallback)
end

findBone = function(entity, names)
	for _, name in ipairs(names) do
		local id = entity:LookupBone(name)
		if id then
			return id, name
		end
	end
end

local function restoreEntity(entity, bones, baselines)
	if not IsValid(entity) then
		return
	end
	for key, bone in pairs(bones or {}) do
		if bone.id then
			entity:ManipulateBoneAngles(bone.id, copyAngle((baselines or {})[key]))
		end
	end
end

local function rebuildBones(entity)
	if not IsValid(entity) then
		return
	end
	local model = entity:GetModel() or ""
	local presetSetting = bonePresetConVar:GetString()
	local headBoneSetting = FaceTracker.Player and FaceTracker.Player.GetPac3HeadBone and (FaceTracker.Player.GetPac3HeadBone() or "") or ""
	if state.model == model and state.presetSetting == presetSetting and state.headBoneSetting == headBoneSetting and not state.mappingDirty then
		return
	end
	if state.presetSetting ~= "" and state.presetSetting ~= presetSetting then
		state.overrideMapping = nil
	end
	if state.model == model then
		-- Remove only our previous pose offset. PAC3 may have changed the live
		-- angle since the last frame, so restoring a captured baseline would
		-- erase its animation/keybind state.
		releasePoseContribution(entity)
	else
		state.externalBoneAngles = {}
		state.appliedBoneAngles = {}
	end
	state.model = model
	state.presetSetting = presetSetting
	state.headBoneSetting = headBoneSetting
	state.bones = {}
	state.baselineBones = {}
	local score = 0
	if state.overrideMapping then
		state.mapping = normalizeMapping(state.overrideMapping)
		state.presetName = "manual"
		score = scoreMapping(entity, state.mapping)
	else
		local name, mapping, presetScore = chooseBonePreset(entity)
		if not mapping then
			mapping = normalizeMapping({}, true)
			name = "fallback"
		end
		state.mapping = mapping
		state.presetName = name or "none"
		score = presetScore or scoreMapping(entity, mapping)
	end
	if entity ~= LocalPlayer() and FaceTracker.Player and FaceTracker.Player.GetPac3HeadBone then
		local selectedHeadBone = FaceTracker.Player.GetPac3HeadBone()
		if selectedHeadBone and selectedHeadBone ~= "" then
			state.mapping.head = { selectedHeadBone }
		end
	end
	for _, key in ipairs(POSE_KEYS) do
		local id, name = findBone(entity, state.mapping[key])
		if id then
			state.bones[key] = { id = id, name = name }
			local baseline = copyAngle(entity:GetManipulateBoneAngles(id))
			state.baselineBones[key] = baseline
			state.externalBoneAngles[key] = copyAngle(baseline)
		end
	end
	state.mappingDirty = false
	state.resolvedScore = score
	state.restored = true
end

local function resetLocal()
	local target = state.targetEntity or LocalPlayer()
	if IsValid(target) then
		releasePoseContribution(target)
	end
	state.current = {}
	state.target = {}
	state.tracking = false
	state.bodyChannels = 0
	state.restored = true
	state.targetEntity = nil
end

local function applyCurrentPose(entity)
	if not IsValid(entity) then
		return
	end
	for _, key in ipairs(POSE_KEYS) do
		local bone = state.bones[key]
		if bone then
			local offset = state.current[key] or angle_zero
			local external = getExternalBoneAngle(entity, bone.id, key)
			if isZeroAngle(offset) then
				-- Once a channel is disabled or has eased back to neutral, release
				-- the bone entirely so PAC3 can animate it without us rewriting it.
				if state.appliedBoneAngles[key] then
					entity:ManipulateBoneAngles(bone.id, external)
					state.appliedBoneAngles[key] = nil
				end
			else
				local output = addAngles(external, offset)
				entity:ManipulateBoneAngles(bone.id, output)
				state.appliedBoneAngles[key] = copyAngle(output)
			end
		end
	end
	if entity.InvalidateBoneCache then
		entity:InvalidateBoneCache()
	end
end

local function sendStop()
	if state.stopSent then
		return
	end
	net.Start("facetracker_player_pose_stop")
	net.SendToServer()
	state.stopSent = true
end

local function calibrate(silent)
	state.needsCalibration = true
	state.calibration = {}
	state.current = {}
	state.target = {}
	if not silent then
		notification.AddLegacy("请正视镜头并自然放下手臂，正在校准姿态……", NOTIFY_HINT, 4)
	end
end

local function finishCalibration()
	for key, value in pairs(state.raw) do
		state.calibration[key] = copyAngle(value)
	end
	state.needsCalibration = false
	if not state.silentCalibration then
		notification.AddLegacy("头部与上半身姿态校准完成。", NOTIFY_GENERIC, 4)
	end
	state.silentCalibration = false
end

local THIRD_PERSON_PAIRS = {
	left_clavicle = "right_clavicle",
	left_upper_arm = "right_upper_arm",
	left_forearm = "right_forearm",
	left_wrist = "right_wrist",
	right_upper_arm = "left_upper_arm",
	right_forearm = "left_forearm",
	right_wrist = "left_wrist",
	right_clavicle = "left_clavicle",
}

local function applyThirdPersonMirror(key, value)
	local mirrored = copyAngle(value)
	-- Head axes are handled separately from the torso. The incoming head
	-- channels have X/Z exchanged relative to the GMod bone Angle, so map them
	-- explicitly before applying the third-person mirror. The Y channel is the
	-- user's vertical head motion and stays same-direction by default.
	if key == "head" or key == "neck" then
		local x = mirrored.p
		mirrored.p = mirrored.r
		mirrored.r = x
		if horizontalMirrorConVar:GetBool() then
			mirrored.p = -mirrored.p
			mirrored.r = -mirrored.r
		end
		-- Do not apply vertical mirroring to head Y: up must stay up and down
		-- must stay down for the front-facing third-person view.
	elseif key == "waist" or key == "spine" then
		-- Keep the existing torso convention while preserving the head axis mapping.
		if horizontalMirrorConVar:GetBool() then mirrored.y = -mirrored.y end
		if verticalMirrorConVar:GetBool() then mirrored.p = -mirrored.p end
	end
	return mirrored
end

local function decodePose(text)
	local decoded = util.JSONToTable(text)
	if not istable(decoded) or not istable(decoded.pose) then
		return
	end
	local incoming = decoded.pose
	local received = {}
	for _, key in ipairs(POSE_KEYS) do
		local value = readTriple(incoming[key])
		if value then
			received[key] = value
		end
	end
	if not next(received) then
		state.tracking = false
		state.bodyChannels = 0
		return
	end
	state.raw = received
	state.tracking = incoming.tracking == true or received.head ~= nil
	state.bodyChannels = 0
	for _, key in ipairs(BODY_KEYS) do
		if received[key] then
			state.bodyChannels = state.bodyChannels + 1
		end
	end
	state.lastFrameAt = RealTime()
	state.stopSent = false
	if state.needsCalibration then
		finishCalibration()
	end

	local strength = strengthConVar:GetFloat()
	local offsets = {}
	for key, value in pairs(received) do
		if not state.calibration[key] then
			state.calibration[key] = copyAngle(value)
		end
		local offset = angleDifference(value, state.calibration[key])
		offsets[key] = offset
	end
	for _, key in ipairs(POSE_KEYS) do
		-- With the camera facing the player, their physical left appears on the
		-- avatar's visual right in third person. This is the default body mapping;
		-- the correction option restores anatomical left-to-left when required.
		local useAnatomicalSides = not horizontalMirrorConVar:GetBool()
		local sourceKey = useAnatomicalSides and key or (THIRD_PERSON_PAIRS[key] or key)
		local offset = offsets[sourceKey]
		if offset then
			-- Head/neck axis correction is unconditional. The horizontal mirror
			-- switch only controls sign reversal, not whether X/Z are remapped.
			if key == "head" or key == "neck" then
				offset = applyThirdPersonMirror(key, offset)
			elseif useAnatomicalSides then
				offset = copyAngle(offset)
			else
				offset = applyThirdPersonMirror(key, offset)
			end
			offset.p = offset.p * strength
			offset.y = offset.y * strength
			offset.r = offset.r * strength
			state.target[key] = clampAngle(offset, BONE_CONFIG[key].limits)
		else
			state.target[key] = angle_zero
		end
	end
end

local function sendPose()
	local now = RealTime()
	if now - state.lastSendAt < 1 / math.max(sendRateConVar:GetFloat(), 1) then
		return
	end
	state.lastSendAt = now
	state.sequence = (state.sequence + 1) % 65536
	net.Start("facetracker_player_pose_frame", true)
	net.WriteUInt(state.sequence, 16)
	for _, key in ipairs(POSE_KEYS) do
		local value = state.current[key] or angle_zero
		net.WriteInt(math.Round(math.Clamp(value.p, -180, 180) * NETWORK_SCALE), 16)
		net.WriteInt(math.Round(math.Clamp(value.y, -180, 180) * NETWORK_SCALE), 16)
		net.WriteInt(math.Round(math.Clamp(value.r, -180, 180) * NETWORK_SCALE), 16)
	end
	net.SendToServer()
end

FaceTracker.Socket:addListener("message", "pose_mode", decodePose)

hook.Add("Think", "facetracker_player_pose_update", function()
	local playerMode = GetConVar("facetracker_player_enabled")
	local active = playerMode and playerMode:GetBool() and poseEnabledConVar:GetBool()
	local player = LocalPlayer()
	if not active or not IsValid(player) then
		if not state.restored then
			resetLocal()
		end
		sendStop()
		return
	end

	local targetEntity = player
	if FaceTracker.Player and FaceTracker.Player.GetPoseTargetEntity then
		targetEntity = FaceTracker.Player.GetPoseTargetEntity() or player
	end
	if state.targetEntity ~= targetEntity then
		if state.targetEntity then resetLocal() end
		state.targetEntity = targetEntity
		state.model = ""
		state.mappingDirty = true
	end
	rebuildBones(targetEntity)
	-- PAC3 can expose an empty group (or a clientside part without any
	-- compatible head bones).  Do not let that empty target steal pose capture
	-- from the real player model.  This is especially common when PAC3 is
	-- attached only as a container with no model part inside it.
	if targetEntity ~= player and not (state.bones.head or state.bones.neck) then
		resetLocal()
		targetEntity = player
		state.targetEntity = player
		state.model = ""
		state.mappingDirty = true
		rebuildBones(player)
	end
	if RealTime() - state.lastFrameAt > FRAME_TIMEOUT then
		if not state.restored then
			resetLocal()
		end
		sendStop()
		return
	end

	local alpha = 1 - math.exp(-smoothingConVar:GetFloat() * FrameTime())
	for _, key in ipairs(POSE_KEYS) do
		local isHead = key == "head" or key == "neck"
		local enabled = isHead and headEnabledConVar:GetBool() or (not isHead and upperEnabledConVar:GetBool())
		local target = enabled and state.target[key] or angle_zero
		local current = state.current[key] or angle_zero
		state.current[key] = LerpAngle(alpha, current, target)
	end
	applyCurrentPose(targetEntity)
	state.restored = false
	sendPose()
end)

-- PAC3 commonly reapplies its part transforms during PrePlayerDraw. Reapply
-- our final pose after PAC3 has finished its player update so PAC3 cosmetics
-- (brightness, bones, groups, etc.) no longer cancel head capture.
local function reapplyLocalPoseAfterPlayerDraw(player)
	if player ~= LocalPlayer() or not IsValid(state.targetEntity) or state.restored then
		return
	end
	if RealTime() - state.lastFrameAt <= FRAME_TIMEOUT then
		applyCurrentPose(state.targetEntity)
	end
end

hook.Add("PostPlayerDraw", "facetracker_player_pose_after_pac3", reapplyLocalPoseAfterPlayerDraw)

-- Some PAC3 versions rebuild the player's bone cache immediately before the
-- draw callback. Apply once in PrePlayerDraw as well; whichever PAC3 path is
-- active, the local player's final head pose is restored for this frame.
hook.Add("PrePlayerDraw", "facetracker_player_pose_before_pac3", reapplyLocalPoseAfterPlayerDraw)

local function clearRemote(player, remote)
	if not remote then
		return
	end
	restoreEntity(player, remote.bones, remote.baselines)
end

local function buildRemoteBones(player, remote)
	if remote.model == (player:GetModel() or "") then
		clearRemote(player, remote)
	end
	remote.model = player:GetModel() or ""
	remote.bones = {}
	remote.baselines = {}
	local _, mapping = chooseBonePreset(player)
	mapping = mapping or normalizeMapping({}, true)
	for _, key in ipairs(POSE_KEYS) do
		local id, name = findBone(player, mapping[key])
		if id then
			remote.bones[key] = { id = id, name = name }
			remote.baselines[key] = copyAngle(player:GetManipulateBoneAngles(id))
		end
	end
end

hook.Add("PrePlayerDraw", "facetracker_player_remote_pose", function(player)
	local remote = remotePoses[player]
	if not remote then
		return
	end
	if RealTime() - remote.receivedAt > FRAME_TIMEOUT then
		clearRemote(player, remote)
		remotePoses[player] = nil
		return
	end
	if remote.model ~= (player:GetModel() or "") or not next(remote.bones or {}) then
		buildRemoteBones(player, remote)
	end
	for _, key in ipairs(POSE_KEYS) do
		local bone = remote.bones[key]
		if bone then
			player:ManipulateBoneAngles(bone.id, addAngles(remote.baselines[key], remote.values[key] or angle_zero))
		end
	end
end)

net.Receive("facetracker_player_pose_frame", function()
	local player = net.ReadEntity()
	local sequence = net.ReadUInt(16)
	if not IsValid(player) or not player:IsPlayer() or player == LocalPlayer() then
		return
	end
	local values = {}
	for _, key in ipairs(POSE_KEYS) do
		values[key] = Angle(
			net.ReadInt(16) / NETWORK_SCALE,
			net.ReadInt(16) / NETWORK_SCALE,
			net.ReadInt(16) / NETWORK_SCALE
		)
	end
	local remote = remotePoses[player] or { bones = {}, baselines = {} }
	if remote.sequence then
		local difference = (sequence - remote.sequence) % 65536
		if difference == 0 or difference >= 32768 then
			return
		end
	end
	remote.sequence = sequence
	remote.values = values
	remote.receivedAt = RealTime()
	remotePoses[player] = remote
end)

net.Receive("facetracker_player_pose_stop", function()
	local player = net.ReadEntity()
	local remote = remotePoses[player]
	clearRemote(player, remote)
	remotePoses[player] = nil
end)

concommand.Add("facetracker_player_pose_calibrate", function()
	calibrate(false)
end)

concommand.Add("facetracker_player_pose_reset", function()
	resetLocal()
	calibrate(true)
end)

concommand.Add("facetracker_player_dumpbones", function()
	local player = LocalPlayer()
	if not IsValid(player) then
		print("[茶茶捕捉·姿态] 玩家实体尚未准备好")
		return
	end
	local lines = {
		"model=" .. tostring(player:GetModel()),
		"bone_count=" .. tostring(player:GetBoneCount()),
	}
	for id = 0, player:GetBoneCount() - 1 do
		table.insert(lines, Format("%d\t%s", id, player:GetBoneName(id) or ""))
	end
	file.CreateDir("facetracker")
	file.Write("facetracker/player_bones.txt", table.concat(lines, "\n"))
	print("[茶茶捕捉·姿态] 已写入 data/facetracker/player_bones.txt")
end)

local function currentMappingForUI()
	local player = LocalPlayer()
	if IsValid(player) then
		rebuildBones(player)
	end
	local result = {}
	for _, key in ipairs(POSE_KEYS) do
		local resolved = state.bones[key] and state.bones[key].name
		local configured = state.mapping[key] and state.mapping[key][1]
		result[key] = resolved or configured or ""
	end
	return result
end

local function applyBoneMapping(mapping)
	state.overrideMapping = normalizeMapping(mapping)
	state.mappingDirty = true
	local player = LocalPlayer()
	if IsValid(player) then
		rebuildBones(player)
	end
	return table.Count(state.bones)
end

local function saveBonePreset(name, mapping)
	name = sanitizePresetName(name)
	if name == "" or string.lower(name) == "auto" then
		return false, "请输入有效的预设名称"
	end
	local normalized = normalizeMapping(mapping or currentMappingForUI())
	local serialized = {}
	for _, key in ipairs(POSE_KEYS) do
		serialized[key] = #normalized[key] == 1 and normalized[key][1] or normalized[key]
	end
	file.CreateDir("facetracker")
	file.CreateDir("facetracker/bones")
	file.Write(BONE_PRESET_DIRECTORY .. name .. ".txt", util.TableToJSON({
		version = 1,
		displayName = name,
		bones = serialized,
	}, true))
	return true, name
end

local function loadBonePreset(name)
	name = sanitizePresetName(name)
	if name == "" then
		return false
	end
	if string.lower(name) ~= "auto" and not readBonePreset(name) then
		return false
	end
	state.overrideMapping = nil
	state.mappingDirty = true
	RunConsoleCommand("facetracker_player_bone_preset", name)
	timer.Simple(0, function()
		local player = LocalPlayer()
		if IsValid(player) then
			rebuildBones(player)
		end
	end)
	return true
end

FaceTracker.Pose = {
	Calibrate = function()
		calibrate(false)
	end,
	Reset = resetLocal,
	Begin = function()
		state.silentCalibration = true
		calibrate(true)
	end,
	GetTrackedBoneCount = function()
		return table.Count(state.bones)
	end,
	GetTrackedBodyChannelCount = function()
		if RealTime() - state.lastFrameAt > FRAME_TIMEOUT then
			return 0
		end
		return state.bodyChannels
	end,
	IsTracking = function()
		return state.tracking and RealTime() - state.lastFrameAt <= FRAME_TIMEOUT
	end,
	IsCalibrated = function()
		return not state.needsCalibration
	end,
	GetBoneMapping = currentMappingForUI,
	SetBoneMapping = applyBoneMapping,
	SaveBonePreset = saveBonePreset,
	LoadBonePreset = loadBonePreset,
	ListBonePresets = listBonePresets,
	GetBonePresetName = function()
		return state.presetName
	end,
	GetResolvedBoneName = function(key)
		return state.bones[key] and state.bones[key].name or ""
	end,
}
