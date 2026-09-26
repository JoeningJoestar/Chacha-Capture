-- Manual Flex editor for player/PAC3 face targets.
-- Values are stored per model under data/facetracker/manual/.

local function manualNotify(message, kind)
	notification.AddLegacy(message, kind or NOTIFY_GENERIC, 4)
end

local function makeRow(parent, flex)
	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:SetTall(46)
	row:DockMargin(0, 0, 0, 3)
	row.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(36, 42, 52, 235))
	end

	local label = vgui.Create("DLabel", row)
	label:Dock(LEFT)
	label:SetWide(235)
	label:DockMargin(8, 0, 6, 0)
	label:SetText(flex.name)
	label:SetTextColor(Color(235, 240, 250))
	label:SetContentAlignment(4)
	label:SetTooltip(flex.mapped and "已绑定实时面捕；手动值会叠加在实时值上。" or "未绑定当前面捕预设；手动值仍可单独使用。")

	local slider = vgui.Create("DNumSlider", row)
	slider:Dock(FILL)
	slider:DockMargin(0, 4, 8, 2)
	slider:SetText("")
	slider:SetMinMax(-1, 2)
	slider:SetDecimals(2)
	slider:SetValue(tonumber(flex.manual) or 0)
	slider:SetTooltip("手动偏移：0 为关闭，1 为标准上限，最高可到 2。")
	local entry = slider:GetTextArea()
	if IsValid(entry) then
		entry:SetNumeric(false)
		entry:SetTooltip("可输入 -1 到 2 的手动偏移值。")
		entry.OnEnter = function(self)
			local value = math.Clamp(tonumber(self:GetValue()) or 0, -1, 2)
			slider:SetValue(value)
		end
	end

	function slider:OnValueChanged(value)
		if FaceTracker.Player and FaceTracker.Player.SetManualFlex then
			FaceTracker.Player.SetManualFlex(flex.name, value)
		end
	end

	return row
end

local function openManualFlexMenu()
	if IsValid(FaceTracker.ManualFlexFrame) then
		FaceTracker.ManualFlexFrame:MakePopup()
		FaceTracker.ManualFlexFrame:Show()
		return FaceTracker.ManualFlexFrame
	end
	if not FaceTracker.Player or not FaceTracker.Player.GetFlexes then
		manualNotify("玩家面捕模块尚未加载。", NOTIFY_ERROR)
		return
	end

	local frame = vgui.Create("DFrame")
	FaceTracker.ManualFlexFrame = frame
	frame:SetTitle("茶茶捕捉 · 手动表情")
	frame:SetSize(760, 680)
	frame:Center()
	frame:MakePopup()
	frame:SetDeleteOnClose(false)

	local top = vgui.Create("DPanel", frame)
	top:Dock(TOP)
	top:SetTall(92)
	top:DockPadding(8, 6, 8, 6)
	top.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(28, 33, 42, 245))
	end

	local targetLabel = vgui.Create("DLabel", top)
	targetLabel:Dock(TOP)
	targetLabel:SetTall(22)
	targetLabel:SetTextColor(Color(220, 235, 255))

	local help = vgui.Create("DLabel", top)
	help:Dock(TOP)
	help:SetTall(20)
	help:SetText("手动值会与实时面捕叠加；停止面捕后仍保留。数值可超过 1，用于夸张表情。")
	help:SetTextColor(Color(170, 180, 195))

	local search = vgui.Create("DTextEntry", top)
	search:Dock(FILL)
	search:SetPlaceholderText("搜索 Flex 名称…")

	local actions = vgui.Create("DPanel", frame)
	actions:Dock(BOTTOM)
	actions:SetTall(40)
	actions:DockPadding(8, 5, 8, 5)
	actions.Paint = nil

	local refresh = vgui.Create("DButton", actions)
	refresh:Dock(LEFT)
	refresh:SetWide(120)
	refresh:SetText("刷新 Flex 列表")

	local clear = vgui.Create("DButton", actions)
	clear:Dock(LEFT)
	clear:DockMargin(6, 0, 0, 0)
	clear:SetWide(160)
	clear:SetText("清除全部手动表情")

	local close = vgui.Create("DButton", actions)
	close:Dock(RIGHT)
	close:SetWide(90)
	close:SetText("关闭")
	close.DoClick = function() frame:Hide() end

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 8, 8, 4)

	local function rebuild()
		for _, child in ipairs(scroll:GetCanvas():GetChildren()) do
			child:Remove()
		end
		local entity = FaceTracker.Player.GetFaceTargetEntity and FaceTracker.Player.GetFaceTargetEntity()
		local kind = FaceTracker.Player.GetFaceTargetKind and FaceTracker.Player.GetFaceTargetKind() or "player"
		-- Resolve again when the PAC3 switch or explicit target changed while
		-- this window stayed open.
		if FaceTracker.Player.RefreshFaceTarget then
			entity, kind = FaceTracker.Player.RefreshFaceTarget()
		end
		if not IsValid(entity) then
			targetLabel:SetText("当前目标：未找到带 Flex 的玩家或 PAC3 模型")
			return
		end
		targetLabel:SetText(Format("当前目标：%s | %s | Flex：%d", kind == "pac3" and "PAC3" or "玩家本体", entity:GetModel() or "unknown", entity:GetFlexNum()))
		local filter = string.lower(string.Trim(search:GetValue() or ""))
		for _, flex in ipairs(FaceTracker.Player.GetFlexes() or {}) do
			if filter == "" or string.find(string.lower(flex.name), filter, 1, true) then
				makeRow(scroll:GetCanvas(), flex)
			end
		end
	end

	search.OnValueChange = function() rebuild() end
	refresh.DoClick = rebuild
	clear.DoClick = function()
		if FaceTracker.Player.ClearManualFlexes then
			FaceTracker.Player.ClearManualFlexes()
			manualNotify("已清除当前模型的全部手动表情。", NOTIFY_HINT)
			rebuild()
		end
	end

	frame.OnClose = function() frame:Hide() end
	rebuild()
	return frame
end

FaceTracker.Player = FaceTracker.Player or {}
FaceTracker.Player.OpenManualFlexMenu = openManualFlexMenu
concommand.Add("facetracker_player_manual_flex", openManualFlexMenu)
