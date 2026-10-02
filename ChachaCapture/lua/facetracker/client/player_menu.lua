local function addHelp(panel, text)
	local label = panel:Help(text)
	if IsValid(label) then
		label:SetWrap(true)
		label:SetAutoStretchVertical(true)
		label:DockMargin(4, 2, 4, 2)
	end
	return label
end

local function buildPlayerPanel(panel)
	panel:ClearControls()
	addHelp(panel, "茶茶捕捉 · 玩家捕捉")
	addHelp(panel, "请先运行 server/start_player_tracker.bat。此页面只负责玩家本体面部与姿态捕捉。")
	local startButton = panel:Button("启动玩家捕捉")
	startButton.DoClick = function() RunConsoleCommand("facetracker_player_start") end
	local stopButton = panel:Button("停止并复原表情与骨骼")
	stopButton.DoClick = function() RunConsoleCommand("facetracker_player_stop") end
	local manual = panel:Button("打开手动表情调节")
	manual.DoClick = function()
		if FaceTracker.Player and FaceTracker.Player.OpenManualFlexMenu then
			FaceTracker.Player.OpenManualFlexMenu()
		end
	end
	panel:CheckBox("断线后自动重连", "facetracker_player_reconnect")
	panel:CheckBox("面部表情使用 PAC3（Flex）", "facetracker_player_face_pac3")
	panel:CheckBox("头部骨骼使用 PAC3", "facetracker_player_pose_pac3")
	local pac3Help = panel:Help("PAC3 手动绑定：刷新并选择模型、头部骨骼后，勾选对应的 PAC3 面部或头部选项，捕捉才会驱动该模型。")
	pac3Help:SetWrap(true)
	local pac3Target = panel:ComboBox("PAC3 模型", "")
	local pac3Bone = panel:ComboBox("PAC3 头部骨骼", "")
	local function loadPac3Bones(entity)
		pac3Bone:Clear()
		pac3Bone:AddChoice("自动匹配", "")
		if IsValid(entity) and FaceTracker.Player and FaceTracker.Player.GetPac3Bones then
			for _, bone in ipairs(FaceTracker.Player.GetPac3Bones(entity) or {}) do pac3Bone:AddChoice(bone.name, bone.name) end
		end
	end
	local pac3Refresh = panel:Button("刷新 PAC3 候选模型")
	pac3Refresh.DoClick = function()
		pac3Target:Clear()
		pac3Target:SetValue("选择 PAC3 模型")
		if FaceTracker.Player and FaceTracker.Player.GetPac3Candidates then
			for index, entity in ipairs(FaceTracker.Player.GetPac3Candidates() or {}) do
				pac3Target:AddChoice(Format("[候选%d] %s", index, entity:GetModel() or "unknown"), entity)
			end
		end
	end
	pac3Target.OnSelect = function(_, _, _, entity)
		if IsValid(entity) then
			if FaceTracker.Player and FaceTracker.Player.SetPac3Target then
				FaceTracker.Player.SetPac3Target(entity)
			else
				RunConsoleCommand("facetracker_player_pac3_target_ent", tostring(entity:EntIndex()))
			end
			loadPac3Bones(entity)
		end
	end
	pac3Bone.OnSelect = function(_, _, _, value) RunConsoleCommand("facetracker_player_pac3_head_bone", tostring(value or "")) end
	local pac3Auto = panel:Button("恢复 PAC3 自动选择")
	pac3Auto.DoClick = function()
		if FaceTracker.Player and FaceTracker.Player.ClearPac3Target then
			FaceTracker.Player.ClearPac3Target()
		else
			RunConsoleCommand("facetracker_player_pac3_target_ent", "0")
			RunConsoleCommand("facetracker_player_pac3_head_bone", "")
		end
		pac3Refresh:DoClick()
	end
	pac3Refresh:DoClick()
	panel:TextEntry("面部预设（auto 或文件名）", "facetracker_player_preset")
	panel:NumSlider("表情强度", "facetracker_player_strength", 0, 2, 2)
	panel:NumSlider("响应速度", "facetracker_player_smoothing", 1, 60, 0)
	panel:NumSlider("同步帧率", "facetracker_player_sendrate", 10, 30, 0)
	addHelp(panel, "PAC3 面部 Flex 和头部骨骼可分别开关；选择模型本身不会自动启用捕捉通道。")
	panel:CheckBox("启用姿态捕捉", "facetracker_player_pose_enabled")
	panel:CheckBox("头部与颈部", "facetracker_player_head_enabled")
	panel:CheckBox("实验性腰部、脊柱、双臂与双腕", "facetracker_player_upperbody_enabled")
	local calibrate = panel:Button("校准姿态")
	calibrate.DoClick = function() RunConsoleCommand("facetracker_player_pose_calibrate") end
end

local function buildFlexPanel(panel)
	panel:ClearControls()
	addHelp(panel, "在游戏中调整模型 Flex，满意后导出静态表情预设。")
	local open = panel:Button("打开 Flex 表情制作器")
	open.DoClick = function()
		if FaceTracker.FlexCreator and FaceTracker.FlexCreator.Open then FaceTracker.FlexCreator.Open() end
	end
end

hook.Add("PopulateToolMenu", "facetracker_player_menu", function()
	-- Keep the addon introduction first, followed by player settings and Flex tools.
	spawnmenu.AddToolMenuOption("Utilities", "ChachaCapture", "facetracker_about", "茶茶捕捉", "", "", function(panel)
		panel:ClearControls()
		addHelp(panel, "茶茶捕捉")
		addHelp(panel, "面部、头部和 Flex 映射工具。玩家捕捉需要本机面捕桥接程序。")
	end)
	spawnmenu.AddToolMenuOption("Utilities", "ChachaCapture", "facetracker_player", "玩家捕捉", "", "", buildPlayerPanel)
	spawnmenu.AddToolMenuOption("Utilities", "ChachaCapture", "facetracker_flex_creator", "Flex 制作", "", "", buildFlexPanel)
	-- NPC/ragdoll capture remains under the dedicated tool category, not here.
end)

language.Add("spawnmenu.category.ChachaCapture", "茶茶捕捉")
