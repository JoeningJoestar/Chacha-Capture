TOOL.Category = "茶茶捕捉"
TOOL.Name = "茶茶捕捉"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["updateinterval"] = "10"

local lastFlexable = NULL
local lastValidFlexable = false
function TOOL:Think()
	local currentFlexable = self:GetFlexable()
	local validFlexable = IsValid(currentFlexable)

	if currentFlexable == lastFlexable and validFlexable == lastValidFlexable then
		return
	end

	if CLIENT then
		self:RebuildControlPanel(currentFlexable)
	end
	lastFlexable = currentFlexable
	lastValidFlexable = validFlexable
end

---@param newFlexable Entity
function TOOL:SetFlexable(newFlexable)
	self:GetWeapon():SetNW2Entity("facetracker_entity", IsValid(newFlexable) and newFlexable or NULL)
end

---@return Entity flexable
function TOOL:GetFlexable()
	return self:GetWeapon():GetNW2Entity("facetracker_entity")
end

---Select an entity to add flex drivers
---@param tr table|TraceResult
---@return boolean
function TOOL:RightClick(tr)
	if CLIENT then
		return true
	end

	if IsValid(tr.Entity) and tr.Entity:GetClass() == "prop_effect" then
		---@diagnostic disable-next-line: undefined-field
		tr.Entity = tr.Entity.AttachedEntity
	end

	self:SetFlexable(tr.Entity)

	return true
end

if SERVER then
	return
end

TOOL:BuildConVarList()

---@module "facetracker.client.ui"
local ui = include("facetracker/client/ui.lua")

---@type PanelState
local panelState = {
	flexable = NULL,
	expressions = {},
	eyeExpressions = {},
}

---@param cPanel ControlPanel|DForm
---@param flexable Entity
function TOOL.BuildCPanel(cPanel, flexable)
	local intro = vgui.Create("DForm", cPanel)
	intro:SetLabel("茶茶捕捉")
	cPanel:AddItem(intro)
	intro:Help("面部、头部和 Flex 映射工具。玩家捕捉需要本机面捕桥接程序。")

	local panelProps = {flexable = flexable}
	panelState.flexable = flexable
	local panelChildren = ui.ConstructPanel(cPanel, panelProps, panelState)
	ui.HookPanel(panelChildren, panelProps, panelState)

	local playerForm = vgui.Create("DForm", cPanel)
	playerForm:SetLabel("玩家捕捉")
	cPanel:AddItem(playerForm)
	playerForm:Help("直接驱动当前玩家本体；也可以在 Q 菜单的“玩家捕捉”中使用。PAC3 手动绑定位于下方设置。")
	local start = playerForm:Button("启动玩家捕捉")
	start.DoClick = function() RunConsoleCommand("facetracker_player_start") end
	local stop = playerForm:Button("停止并复原")
	stop.DoClick = function() RunConsoleCommand("facetracker_player_stop") end
	local manual = playerForm:Button("打开手动表情调节")
	manual.DoClick = function()
		if FaceTracker.Player and FaceTracker.Player.OpenManualFlexMenu then FaceTracker.Player.OpenManualFlexMenu() end
	end
	local flexCreator = playerForm:Button("打开 Flex 制作")
	flexCreator.DoClick = function()
		if FaceTracker.FlexCreator and FaceTracker.FlexCreator.Open then FaceTracker.FlexCreator.Open() end
	end
	local pac3 = playerForm:Help("PAC3 手动选择：请在下面玩家捕捉设置中选择 PAC3 模型和头部骨骼。")
	pac3:SetWrap(true)

end

TOOL.Information = {
	{ name = "info" },
	{ name = "right" },
}
