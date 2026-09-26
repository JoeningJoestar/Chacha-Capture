---@module "facetracker.shared.helpers"
local helpers = include("facetracker/shared/helpers.lua")

local getValidModelChildren = helpers.getValidModelChildren
local getModelName, getModelNameNice, getModelNodeIconPath =
	helpers.getModelName, helpers.getModelNameNice, helpers.getModelNodeIconPath
local ui = {}

local PRESETS_DIR = "facetracker/presets"

---Add hooks and model tree pointers
---@param parent TreePanel_Node
---@param entity Entity
---@param info EntityTree
---@param rootInfo EntityTree
---@return TreePanel_Node
local function addEntityNode(parent, entity, info, rootInfo)
	local node = parent:AddNode(getModelNameNice(entity))
	---@cast node TreePanel_Node

	node:SetExpanded(true, true)

	node.Icon:SetImage(getModelNodeIconPath(entity))
	node.info = info

	return node
end

---Construct the model tree
---@param parent Entity
---@return EntityTree
local function entityHierarchy(parent)
	local tree = {}
	if not IsValid(parent) then
		return tree
	end

	---@type Entity[]
	local children = getValidModelChildren(parent)

	for i, child in ipairs(children) do
		if child.GetModel and child:GetModel() ~= "models/error.mdl" then
			---@type EntityTree
			local node = {
				parent = parent:EntIndex(),
				entity = child:EntIndex(),
				children = entityHierarchy(child),
			}
			table.insert(tree, node)
		end
	end

	return tree
end

---Construct the DTree from the entity model tree
---@param tree EntityTree
---@param nodeParent TreePanel_Node
---@param root EntityTree
local function hierarchyPanel(tree, nodeParent, root)
	for _, child in ipairs(tree) do
		local childEntity = Entity(child.entity)
		if not IsValid(childEntity) or not childEntity.GetModel or not childEntity:GetModel() then
			continue
		end

		local node = addEntityNode(nodeParent, childEntity, child, root)

		if #child.children > 0 then
			hierarchyPanel(child.children, node, root)
		end
	end
end

---Construct the `entity`'s model tree
---@param treePanel TreePanel
---@param entity Entity
---@returns EntityTree
local function buildTree(treePanel, entity)
	if IsValid(treePanel.ancestor) then
		treePanel.ancestor:Remove()
	end

	---@type EntityTree
	local hierarchy = {
		entity = entity:EntIndex(),
		children = entityHierarchy(entity),
	}

	---@type TreePanel_Node
	---@diagnostic disable-next-line
	treePanel.ancestor = addEntityNode(treePanel, entity, hierarchy, hierarchy)
	treePanel.ancestor.Icon:SetImage(getModelNodeIconPath(entity))
	treePanel.ancestor.info = hierarchy
	hierarchyPanel(hierarchy.children, treePanel.ancestor, hierarchy)

	return hierarchy
end

---Helper for DForm
---@param cPanel ControlPanel|DForm
---@param name string
---@param type "ControlPanel"|"DForm"
---@return ControlPanel|DForm
local function makeCategory(cPanel, name, type)
	---@type DForm|ControlPanel
	local category = vgui.Create(type, cPanel)

	category:SetLabel(name)
	cPanel:AddItem(category)
	return category
end

local function addHelp(panel, text)
	local label = panel:Help(text)
	if IsValid(label) then
		label:SetWrap(true)
		label:SetAutoStretchVertical(true)
		label:DockMargin(4, 2, 4, 2)
	end
	return label
end

local function addPac3Binding(form)
	addHelp(form, "PAC3 目标绑定：选择模型后，可分别用于面部 Flex 和头部骨骼。")
	local models = form:ComboBox("PAC3 模型", "")
	local bones = form:ComboBox("头部骨骼", "")
	local refresh = form:Button("刷新 PAC3 模型")
	local automatic = form:Button("恢复自动选择")

	local function loadBones(entity)
		bones:Clear()
		bones:AddChoice("自动匹配", "")
		if not IsValid(entity) or not FaceTracker.Player or not FaceTracker.Player.GetPac3Bones then return end
		for _, bone in ipairs(FaceTracker.Player.GetPac3Bones(entity)) do
			bones:AddChoice(bone.name, bone.name)
		end
	end

	local function refreshModels()
		models:Clear()
		models:SetValue("选择 PAC3 模型")
		if not FaceTracker.Player or not FaceTracker.Player.GetPac3Candidates then return end
		for _, entity in ipairs(FaceTracker.Player.GetPac3Candidates() or {}) do
			local flexCount = entity.GetFlexNum and entity:GetFlexNum() or 0
			local boneCount = entity.GetBoneCount and entity:GetBoneCount() or 0
			models:AddChoice(Format("[%d] %s  Flex:%d  骨骼:%d", entity:EntIndex(), entity:GetModel() or "unknown", flexCount, boneCount), entity)
		end
	end

	models.OnSelect = function(_, _, _, entity)
		if not IsValid(entity) then return end
		RunConsoleCommand("facetracker_player_pac3_target_ent", tostring(entity:EntIndex()))
		loadBones(entity)
	end
	bones.OnSelect = function(_, _, _, value)
		RunConsoleCommand("facetracker_player_pac3_head_bone", tostring(value or ""))
	end
	refresh.DoClick = refreshModels
	automatic.DoClick = function()
		RunConsoleCommand("facetracker_player_pac3_target_ent", "0")
		RunConsoleCommand("facetracker_player_pac3_head_bone", "")
		refreshModels()
	end
	refreshModels()
end

---@param form DForm|ControlPanel
---@return EyeSlider eyeSlider
---@return DNumSlider strabismus
local function eyePanel(form)
	local sliderBackground = vgui.Create("DPanel", form)
	sliderBackground:Dock(TOP)
	sliderBackground:SetTall(225)
	form:AddItem(sliderBackground)

	-- 2 axis slider for the eye position
	---@class EyeSlider: DSlider
	---@field Knob Panel
	local eyeSlider = vgui.Create("DSlider", sliderBackground)
	eyeSlider:Dock(FILL)
	eyeSlider:SetLockY()
	eyeSlider:SetSlideX(0.5)
	eyeSlider:SetSlideY(0.5)
	eyeSlider:SetTrapInside(true)
	-- Draw the 'button' different from the slider
	eyeSlider.Knob.Paint = function(panel, w, h)
		derma.SkinHook("Paint", "Button", panel, w, h)
	end

	eyeSlider.xp = vgui.Create("DTextEntry", sliderBackground)
	eyeSlider.yp = vgui.Create("DTextEntry", sliderBackground)
	eyeSlider.xp.type = "x"
	eyeSlider.yp.type = "y"

	eyeSlider:SetEnabled(false)

	local oldPerformLayout = eyeSlider.PerformLayout

	function eyeSlider:PerformLayout(w, h)
		oldPerformLayout(self, w, h)
		local x, y = 90, 20
		local margin = 10

		self.xp:SetSize(x, y)
		self.yp:SetSize(x, y)
		self.xp:SetPos(w - x - margin, h * 0.5 - y * 0.5)
		self.yp:SetPos(w * 0.5 - x * 0.5, margin)
	end

	function eyeSlider:Paint(w, h)
		local knobX, knobY = self.Knob:GetPos()
		local knobW, knobH = self.Knob:GetSize()
		surface.SetDrawColor(0, 0, 0, 250)
		surface.DrawLine(knobX + knobW / 2, knobY + knobH / 2, w / 2, h / 2)
		surface.DrawRect(w / 2 - 2, h / 2 - 2, 5, 5)
	end

	local strabismus = form:NumSlider("#tool.eyeposer.strabismus", "", -1, 1)
	---@cast strabismus DNumSlider

	return eyeSlider, strabismus
end

---@param cPanel DForm|ControlPanel
---@param panelProps PanelProps
---@param panelState PanelState
---@return PanelChildren
function ui.ConstructPanel(cPanel, panelProps, panelState)
	local flexable = panelProps.flexable

	addHelp(cPanel, "由哔哩哔哩 UP 主茶茶茶先森改进")
	addHelp(cPanel, "面部捕捉可用于玩家、NPC 和布娃娃；支持头部和上半身捕捉。")

	-- Player mode lives in the original Face Tracker panel so the user does
	-- not need to switch to a second tool menu just to drive their own model.
	local playerForm = makeCategory(cPanel, "玩家本体模式", "DForm")
	addHelp(playerForm, "不选择 NPC 或布娃娃，直接驱动你当前的玩家模型。")
	local playerStart = playerForm:Button("启动玩家捕捉")
	local playerStop = playerForm:Button("停止并复原")
	local playerStatus = playerForm:Help("状态：等待启动")
	playerStatus:SetWrap(true)
	playerStatus:SetAutoStretchVertical(true)
	playerStatus:DockMargin(4, 4, 4, 8)
	local faceForm = makeCategory(playerForm, "面部捕捉", "DForm")
	addHelp(faceForm, "驱动玩家本体的面部 Flex。PAC3 表情目标可单独选择。")
	local manualFlexButton = faceForm:Button("打开手动表情调节")
	manualFlexButton.DoClick = function()
		if FaceTracker.Player and FaceTracker.Player.OpenManualFlexMenu then
			FaceTracker.Player.OpenManualFlexMenu()
		else
			notification.AddLegacy("手动表情模块尚未加载。", NOTIFY_ERROR, 5)
		end
	end
	faceForm:TextEntry("面部预设（auto 或文件名）", "facetracker_player_preset")
	faceForm:NumSlider("表情强度", "facetracker_player_strength", 0, 2, 2)
	faceForm:NumSlider("响应速度", "facetracker_player_smoothing", 1, 60, 0)
	faceForm:NumSlider("同步帧率", "facetracker_player_sendrate", 10, 30, 0)
	faceForm:CheckBox("断线后自动重连", "facetracker_player_reconnect")
	faceForm:CheckBox("面部表情使用 PAC3（Flex）", "facetracker_player_face_pac3")
	addHelp(faceForm, "PAC3 面部和头部目标可分别开关；不启用时使用玩家本体。")
	addPac3Binding(faceForm)
	FaceTracker.UI = FaceTracker.UI or {}
	FaceTracker.UI.RefreshPac3Binding = function()
		-- The binding controls are recreated by the tool panel; this command is
		-- kept as a discoverable entry point for the Utilities player panel.
		notification.AddLegacy("请在工具枪的玩家捕捉面板中选择 PAC3 模型和头部骨骼。", NOTIFY_HINT, 4)
	end
	local poseForm = makeCategory(playerForm, "上半身捕捉", "DForm")
	addHelp(poseForm, "头部、颈部和上半身姿态捕捉设置。")
	poseForm:CheckBox("头部骨骼使用 PAC3", "facetracker_player_pose_pac3")
	poseForm:CheckBox("启用上半身捕捉", "facetracker_player_pose_enabled")
	poseForm:CheckBox("头部与颈部", "facetracker_player_head_enabled")
	poseForm:CheckBox("实验性腰部、脊柱、双臂与双腕", "facetracker_player_upperbody_enabled")
	poseForm:NumSlider("姿态幅度", "facetracker_player_pose_strength", 0, 2, 2)
	poseForm:NumSlider("姿态响应速度", "facetracker_player_pose_smoothing", 1, 60, 0)
	poseForm:NumSlider("姿态同步帧率", "facetracker_player_pose_sendrate", 15, 30, 0)
	local poseCalibrate = poseForm:Button("校准姿态（正视镜头、手臂自然下垂）")
	addHelp(poseForm, "默认使用第三人称正面镜像：左右反向、上下保持同向。")

	local boneForm = makeCategory(poseForm, "骨骼映射预设", "DForm")
	addHelp(boneForm, "骨骼映射独立于 Flex 预设。每个语义槽位填写当前模型实际的骨骼名称。")
	local bonePresetCombo = boneForm:ComboBox("可用骨骼预设", "")
	bonePresetCombo:AddChoice("auto")
	if FaceTracker.Pose and FaceTracker.Pose.ListBonePresets then
		for _, name in ipairs(FaceTracker.Pose.ListBonePresets()) do
			bonePresetCombo:AddChoice(name)
		end
	end
	local bonePresetEntry = boneForm:TextEntry("预设名称（auto 或文件名）", "")
	local boneEntries = {}
	local boneLabels = {
		head = "头部",
		neck = "颈部",
		waist = "腰部/骨盆",
		spine = "脊柱",
		left_clavicle = "左锁骨/肩",
		left_upper_arm = "左上臂",
		left_forearm = "左前臂",
		left_wrist = "左手腕/手",
		right_upper_arm = "右上臂",
		right_forearm = "右前臂",
		right_wrist = "右手腕/手",
		right_clavicle = "右锁骨/肩",
	}
	for _, key in ipairs({ "head", "neck", "waist", "spine", "left_clavicle", "left_upper_arm", "left_forearm", "left_wrist", "right_clavicle", "right_upper_arm", "right_forearm", "right_wrist" }) do
		boneEntries[key] = boneForm:TextEntry(boneLabels[key], "")
	end
	local boneStatus = boneForm:Help("映射状态：等待玩家模型")
	local boneLoad = boneForm:Button("加载上方骨骼预设")
	local boneApply = boneForm:Button("应用当前骨骼映射")
	local boneSave = boneForm:Button("保存为骨骼预设")
	local boneAuto = boneForm:Button("自动匹配 ValveBiped / 已保存预设")

	local npcForm = makeCategory(cPanel, "NPC/布娃娃模式", "DForm")
	addHelp(npcForm, "使用工具枪右键选择 NPC 或布娃娃，再在下方编辑 Flex 表情。")
	local treeForm = makeCategory(npcForm, "选择目标模型", "DForm")
	if IsValid(flexable) then
		addHelp(treeForm, "点击模型图标可切换要驱动的实体。")
	end
	addHelp(treeForm, IsValid(flexable) and "当前目标：" .. getModelName(flexable) or "尚未选择实体")
	local treePanel = vgui.Create("DTreeScroller", treeForm)
	---@cast treePanel TreePanel
	if IsValid(flexable) then
		panelState.tree = buildTree(treePanel, flexable)
	end
	treeForm:AddItem(treePanel)
	treePanel:Dock(TOP)
	treePanel:SetSize(treeForm:GetWide(), 125)

	local presets = vgui.Create("facetracker_presetsaver", npcForm)
	presets:SetEntity(flexable)
	presets:SetDirectory(PRESETS_DIR)
	presets:RefreshDirectory()

	npcForm:AddItem(presets)

	local connect = npcForm:Button(
		FaceTracker.Socket:isConnected() and "断开面捕服务" or "连接面捕服务",
		""
	)

	addHelp(npcForm, "连接本机面捕服务后，下面的 Flex 表情映射会实时更新。")

	local remove = npcForm:Button("清空表情映射", "")
	local expressionForm = makeCategory(npcForm, "Flex 表情映射", "DForm")

	local eyeForm = makeCategory(npcForm, "眼睛追踪", "DForm")
	local eyeSlider, strabismus = eyePanel(eyeForm)

	local arkitForm = makeCategory(npcForm, "ARKit 表情系数", "DForm")
	local latency = arkitForm:Help(Format("延迟（毫秒）：%d", 0))
	latency.now = SysTime()
	for _, blendshape in ipairs(FaceTracker.Parser.blendshapes) do
		arkitForm[blendshape] = arkitForm:Help(Format("%s: %d", blendshape, 0))
	end

	local replicationSettings = makeCategory(npcForm, "同步设置", "DForm")
	addHelp(replicationSettings, "数值越小更新越频繁，但会增加性能和服务器负担。")
	local updateInterval =
		replicationSettings:NumSlider("更新间隔（毫秒）", "facetracker_updateinterval", 0, 1000)
	updateInterval:SetTooltip("面捕数据发送到服务器的间隔。")

	return {
		treePanel = treePanel,
		expressionForm = expressionForm,
		presets = presets,
		connect = connect,
		arkitForm = arkitForm,
		latency = latency,
		remove = remove,
		eyeSlider = eyeSlider,
		strabismus = strabismus,
		playerStart = playerStart,
		playerStop = playerStop,
		playerStatus = playerStatus,
		poseCalibrate = poseCalibrate,
		bonePresetCombo = bonePresetCombo,
		bonePresetEntry = bonePresetEntry,
		boneEntries = boneEntries,
		boneStatus = boneStatus,
		boneLoad = boneLoad,
		boneApply = boneApply,
		boneSave = boneSave,
		boneAuto = boneAuto,
	}
end

---@param panelChildren PanelChildren
---@param panelProps PanelProps
---@param panelState PanelState
function ui.HookPanel(panelChildren, panelProps, panelState)
	local treePanel = panelChildren.treePanel
	local presets = panelChildren.presets
	local connect = panelChildren.connect
	local arkitForm = panelChildren.arkitForm
	local expressionForm = panelChildren.expressionForm
	local latency = panelChildren.latency
	local remove = panelChildren.remove
	local strabismus = panelChildren.strabismus
	local eyeSlider = panelChildren.eyeSlider
	local playerStart = panelChildren.playerStart
	local playerStop = panelChildren.playerStop
	local playerStatus = panelChildren.playerStatus
	local poseCalibrate = panelChildren.poseCalibrate
	local bonePresetEntry = panelChildren.bonePresetEntry
	local bonePresetCombo = panelChildren.bonePresetCombo
	local boneEntries = panelChildren.boneEntries
	local boneStatus = panelChildren.boneStatus
	local boneLoad = panelChildren.boneLoad
	local boneApply = panelChildren.boneApply
	local boneSave = panelChildren.boneSave
	local boneAuto = panelChildren.boneAuto

	local flexable = panelState.flexable
	local blendshapes = FaceTracker.Parser.blendshapes

	---@param coefficients {[FlexName]: number}?
	local function refreshBlendshapes(coefficients)
		coefficients = coefficients or {}
		for i, coefficient in ipairs(coefficients) do
			local blendshape = blendshapes[i]
			arkitForm[blendshape]:SetText(Format("%s: %.2f", blendshape, coefficient or 0))
		end
	end

	local function refreshExpressions()
		expressionForm:Clear()

		for i = 0, flexable:GetFlexNum() - 1 do
			local flexName = flexable:GetFlexName(i)
			local expression = panelState.expressions[flexName] or ""

			local entry = expressionForm:TextEntry(flexName, "")
			entry:SetText(expression)

			function entry:OnValueChange(newVal)
				newVal = string.gsub(newVal, "%s+", "")
				panelState.expressions[flexName] = #newVal > 0 and newVal or nil
				FaceTracker.System.setExpressions(flexable, panelState.expressions, panelState.eyeExpressions)
			end
		end

		eyeSlider.xp:SetText(panelState.eyeExpressions.x or "")
		eyeSlider.yp:SetText(panelState.eyeExpressions.y or "")
		strabismus:SetValue(panelState.eyeExpressions.s or 0)
	end

	function FaceTracker.Socket:onConnected()
		connect:SetText("断开面捕服务")
	end

	function FaceTracker.Socket:onDisconnected()
		connect:SetText("连接面捕服务")
	end

	function FaceTracker.Socket:onMessage(coefficientString)
		local now = SysTime()
		local ping = now - latency.now
		latency.now = now

		latency:SetText(Format("延迟（毫秒）：%d", ping * 1000))
		local decoded = util.JSONToTable(coefficientString)
		local coefficients = istable(decoded) and decoded.blendshapes or decoded
		if not istable(coefficients) then
			return
		end
		refreshBlendshapes(coefficients)
		FaceTracker.Parser:updateVariables(coefficients)
	end

	function connect:DoClick()
		FaceTracker.Socket:toggleConnection()
	end

	function playerStart:DoClick()
		if FaceTracker.Player and FaceTracker.Player.Start then
			FaceTracker.Player.Start()
		else
			notification.AddLegacy("玩家面捕模块尚未加载，请检查 GMod 控制台错误。", NOTIFY_ERROR, 5)
		end
	end

	function playerStop:DoClick()
		if FaceTracker.Player and FaceTracker.Player.Stop then
			FaceTracker.Player.Stop()
		end
	end

	function poseCalibrate:DoClick()
		if FaceTracker.Pose and FaceTracker.Pose.Calibrate then
			FaceTracker.Pose.Calibrate()
		else
			notification.AddLegacy("上半身捕捉模块尚未加载。", NOTIFY_ERROR, 5)
		end
	end

	local function readBoneEditor()
		local mapping = {}
		for key, entry in pairs(boneEntries) do
			local value = string.Trim(entry:GetValue() or "")
			if value ~= "" then
				mapping[key] = value
			end
		end
		return mapping
	end

	function bonePresetCombo:OnSelect(_, value)
		bonePresetEntry:SetText(value)
	end

	local function refreshBoneEditor()
		if not FaceTracker.Pose or not FaceTracker.Pose.GetBoneMapping then
			boneStatus:SetText("映射状态：姿态模块未加载")
			return
		end
		local mapping = FaceTracker.Pose.GetBoneMapping()
		for key, entry in pairs(boneEntries) do
			entry:SetText(mapping[key] or "")
		end
		local preset = FaceTracker.Pose.GetBonePresetName and FaceTracker.Pose.GetBonePresetName() or "none"
		if bonePresetEntry:GetValue() == "" then
			bonePresetEntry:SetText(GetConVar("facetracker_player_bone_preset") and GetConVar("facetracker_player_bone_preset"):GetString() or "auto")
		end
		local matched = FaceTracker.Pose.GetTrackedBoneCount and FaceTracker.Pose.GetTrackedBoneCount() or 0
			boneStatus:SetText(Format("映射状态：%s，已匹配 %d/12 个骨骼", preset, matched))
	end

	function boneLoad:DoClick()
		if not FaceTracker.Pose or not FaceTracker.Pose.LoadBonePreset then
			return
		end
		local name = string.Trim(bonePresetEntry:GetValue() or "")
		if FaceTracker.Pose.LoadBonePreset(name) then
			timer.Simple(0, refreshBoneEditor)
		else
			notification.AddLegacy("找不到骨骼预设：" .. name, NOTIFY_ERROR, 5)
		end
	end

	function boneApply:DoClick()
		if FaceTracker.Pose and FaceTracker.Pose.SetBoneMapping then
			local matched = FaceTracker.Pose.SetBoneMapping(readBoneEditor())
			boneStatus:SetText(Format("映射已应用，已匹配 %d/12 个骨骼", matched or 0))
		end
	end

	function boneSave:DoClick()
		if not FaceTracker.Pose or not FaceTracker.Pose.SaveBonePreset then
			return
		end
		local name = string.Trim(bonePresetEntry:GetValue() or "")
		local mapping = readBoneEditor()
		local ok, result = FaceTracker.Pose.SaveBonePreset(name, mapping)
		if ok then
			FaceTracker.Pose.SetBoneMapping(mapping)
			bonePresetCombo:AddChoice(tostring(result))
			notification.AddLegacy("骨骼预设已保存：" .. tostring(result), NOTIFY_GENERIC, 4)
			boneStatus:SetText("已保存骨骼预设：" .. tostring(result))
		else
			notification.AddLegacy(tostring(result or "骨骼预设保存失败"), NOTIFY_ERROR, 5)
		end
	end

	function boneAuto:DoClick()
		if FaceTracker.Pose and FaceTracker.Pose.LoadBonePreset then
			FaceTracker.Pose.LoadBonePreset("auto")
			timer.Simple(0, refreshBoneEditor)
		end
	end

	local function refreshPlayerStatus()
		if not FaceTracker.Player or not FaceTracker.Player.GetMappedFlexCount then
			playerStatus:SetText("状态：玩家面捕模块未加载")
			return
		end
		local enabled = GetConVar("facetracker_player_enabled")
		local connected = FaceTracker.Socket:isConnected()
		local preset = FaceTracker.Player.GetPresetName()
		local mapped = FaceTracker.Player.GetMappedFlexCount()
		local poseTracking = FaceTracker.Pose and FaceTracker.Pose.IsTracking and FaceTracker.Pose.IsTracking()
		local poseBones = FaceTracker.Pose and FaceTracker.Pose.GetTrackedBoneCount and FaceTracker.Pose.GetTrackedBoneCount() or 0
		local bodyChannels = FaceTracker.Pose and FaceTracker.Pose.GetTrackedBodyChannelCount and FaceTracker.Pose.GetTrackedBodyChannelCount() or 0
		local bonePreset = FaceTracker.Pose and FaceTracker.Pose.GetBonePresetName and FaceTracker.Pose.GetBonePresetName() or "none"
		playerStatus:SetText(Format(
			"状态：%s，桥接：%s\nFlex预设：%s，Flex：%d，姿态：%s\n身体通道：%d/10，骨骼预设：%s，骨骼：%d/12",
			enabled and enabled:GetBool() and "运行中" or "已停止",
			connected and "已连接" or "未连接",
			preset ~= "" and preset or "未选择",
			mapped or 0,
			poseTracking and "已捕捉" or "未捕捉",
			bodyChannels,
			bonePreset,
			poseBones
		))
	end


	playerStatus.Think = refreshPlayerStatus
	refreshBoneEditor()

	---@param node TreePanel_Node
	function treePanel:OnNodeSelected(node)
		local selectedEntity = Entity(node.info.entity)
		if flexable == selectedEntity then
			return
		end

		flexable = selectedEntity

		presets:SetEntity(flexable)
		presets:SetText(helpers.getModelNameNice(flexable))

		panelState.expressions, panelState.eyeExpressions = FaceTracker.System.getExpressions(flexable)
		refreshExpressions()
	end

	function strabismus:OnValueChanged(value)
		panelState.eyeExpressions.s = value
		FaceTracker.System.setExpressions(flexable, panelState.expressions, panelState.eyeExpressions)
	end

	local function expressionChanged(panel, newVal)
		panelState.eyeExpressions[panel.type] = #newVal > 0 and newVal or nil
		FaceTracker.System.setExpressions(flexable, panelState.expressions, panelState.eyeExpressions)
	end

	local oldThink = eyeSlider.Think
	function eyeSlider:Think()
		oldThink(self)

		local eye = FaceTracker.System.getEye(flexable)

		if eye then
			self:SetSlideX(eye.x)
			self:SetSlideY(eye.y)
		end
	end

	eyeSlider.xp.OnValueChange = expressionChanged
	eyeSlider.yp.OnValueChange = expressionChanged

	function presets:OnSaveSuccess()
		notification.AddLegacy("表情预设已保存", NOTIFY_GENERIC, 5)
	end

	function presets:OnSaveFailure(msg)
		notification.AddLegacy("表情预设保存失败：" .. msg, NOTIFY_ERROR, 5)
	end

	function presets:OnSavePreset()
		local data = {
			expressions = panelState.expressions,
			eyeExpressions = panelState.eyeExpressions,
		}

		return util.TableToJSON(data, true)
	end

	---@param preset {expressions: FlexExpressions, eyeExpressions: EyeExpression}
	function presets:OnLoadPreset(preset)
		if istable(preset) then
			local expressions, eyeExpressions = preset.expressions or preset, preset.eyeExpressions or {}
			panelState.expressions = expressions
			panelState.eyeExpressions = eyeExpressions
			FaceTracker.System.setExpressions(flexable, expressions, eyeExpressions)
			refreshExpressions()
			notification.AddLegacy("表情预设已加载", NOTIFY_GENERIC, 5)
		end
	end

	function remove:DoClick()
		panelState.expressions = {}
		panelState.eyeExpressions = {}
		FaceTracker.System.setExpressions(flexable, panelState.expressions, panelState.eyeExpressions)
		refreshExpressions()
	end

	if IsValid(flexable) then
		panelState.expressions, panelState.eyeExpressions = FaceTracker.System.getExpressions(flexable)
		refreshExpressions()
		presets:SetEnabled(true)
	else
		presets:SetEnabled(false)
	end
end

return ui
