TOOL.Category = "茶茶捕捉"
TOOL.Name = "Flex 制作"
TOOL.Command = nil
TOOL.ConfigName = ""

if SERVER then
	return
end

function TOOL.BuildCPanel(panel)
	panel:Help("为当前模型制作专属 Flex 面捕预设。右键选择 NPC、布娃娃或其他模型后，在面板中编辑映射。")
	local open = panel:Button("打开 Flex 映射制作器")
	open.DoClick = function()
		if FaceTracker.FlexCreator and FaceTracker.FlexCreator.Open then
			FaceTracker.FlexCreator.Open()
		end
	end
	local help = panel:Help("预设会按模型名称保存，可为每个模型建立独立的 ARKit → Flex 映射。")
	help:SetWrap(true)
end

function TOOL:RightClick(trace)
	return true
end

TOOL.Information = {
	{name = "info"},
	{name = "right"},
}
