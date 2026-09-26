-- In-game static Flex preset creator. This is intentionally independent from
-- the live face tracker so users can author expressions without a camera.
local CREATOR_DIRECTORY = "facetracker/presets"
local CHANNELS = FaceTracker.Parser and FaceTracker.Parser.blendshapes or {}
local NUM_SLIDER_TEXT_COLOR = Color(35, 35, 35)
local CHANNEL_SET = {}
for _, channel in ipairs(CHANNELS) do CHANNEL_SET[channel] = true end

local function styleNumSlider(slider)
	if not IsValid(slider) then return end
	if IsValid(slider.Label) then
		slider.Label:SetTextColor(NUM_SLIDER_TEXT_COLOR)
	end
	local entry = slider:GetTextArea()
	if IsValid(entry) then
		entry:SetTextColor(NUM_SLIDER_TEXT_COLOR)
	end
end

local function notify(message, kind)
	notification.AddLegacy(message, kind or NOTIFY_GENERIC, 4)
end

local function trim(value)
	return string.Trim(tostring(value or ""))
end

local function stripOuterParentheses(value)
	value = trim(value)
	while string.StartWith(value, "(") and string.EndsWith(value, ")") do
		local depth = 0
		local closesAtEnd = true
		for index = 1, #value do
			local character = string.sub(value, index, index)
			if character == "(" then
				depth = depth + 1
			elseif character == ")" then
				depth = depth - 1
				if depth == 0 and index < #value then
					closesAtEnd = false
					break
				end
			end
		end
		if not closesAtEnd or depth ~= 0 then break end
		value = trim(string.sub(value, 2, -2))
	end
	return value
end

local function findTopLevelOperator(value, operator)
	local depth = 0
	for index = 1, #value do
		local character = string.sub(value, index, index)
		if character == "(" then
			depth = depth + 1
		elseif character == ")" then
			depth = depth - 1
		elseif depth == 0 and character == operator then
			return index
		end
	end
end

-- Convert the linear subset used by shipped .txt presets into the creator's
-- editable mapping rows. Unsupported functions are left untouched and reported
-- to the user instead of being silently discarded.
local function parseLinearExpression(expression)
	local text = string.gsub(trim(expression), "%s+", "")
	if text == "" then return end

	local function addScaled(destination, source, scale)
		destination.constant = destination.constant + (source.constant or 0) * scale
		for channel, weight in pairs(source.terms or {}) do
			destination.terms[channel] = (destination.terms[channel] or 0) + weight * scale
		end
	end

	local parseExpression
	local function parseTerm(term)
		term = stripOuterParentheses(term)
		local star = findTopLevelOperator(term, "*")
		if star then
			local left = parseExpression(string.sub(term, 1, star - 1))
			local right = parseExpression(string.sub(term, star + 1))
			if not left or not right then return end
			local leftHasTerms = next(left.terms) ~= nil
			local rightHasTerms = next(right.terms) ~= nil
			if leftHasTerms and rightHasTerms then return end
			local result = {constant = 0, terms = {}}
			if leftHasTerms then
				addScaled(result, left, right.constant)
			else
				addScaled(result, right, left.constant)
			end
			return result
		end

		local number = tonumber(term)
		if number then return {constant = number, terms = {}} end
		local meanBody = string.match(term, "^mean%((.*)%)$")
		if meanBody then
			local names = {}
			for name in string.gmatch(meanBody, "([%a_][%w_]*)") do
				if not CHANNEL_SET[name] then return end
				table.insert(names, name)
			end
			if #names == 0 then return end
			local result = {constant = 0, terms = {}}
			for _, name in ipairs(names) do result.terms[name] = 1 / #names end
			return result
		end
		if CHANNEL_SET[term] then return {constant = 0, terms = {[term] = 1}} end
	end

	parseExpression = function(value)
		value = stripOuterParentheses(value)
		local result = {constant = 0, terms = {}}
		local start = 1
		local sign = 1
		local depth = 0
		local function consumeTerm(finish)
			local term = trim(string.sub(value, start, finish))
			if term == "" then return false end
			local parsed = parseTerm(term)
			if not parsed then return false end
			addScaled(result, parsed, sign)
			return true
		end
		for index = 1, #value do
			local character = string.sub(value, index, index)
			if character == "(" then
				depth = depth + 1
			elseif character == ")" then
				depth = depth - 1
			elseif depth == 0 and (character == "+" or character == "-") then
				if index == start then
					sign = character == "-" and -1 or 1
					start = index + 1
				else
					if not consumeTerm(index - 1) then return end
					sign = character == "-" and -1 or 1
					start = index + 1
				end
			end
		end
		if not consumeTerm(#value) then return end
		return result
	end

	return parseExpression(text)
end

local function copyMappings(source)
	local result = {}
	for flexName, inputs in pairs(istable(source) and source or {}) do
		if isstring(flexName) and istable(inputs) then
			for _, input in ipairs(inputs) do
				if istable(input) and CHANNEL_SET[input.channel] then
					result[flexName] = result[flexName] or {}
					table.insert(result[flexName], {
						channel = input.channel,
						weight = tonumber(input.weight) or 0,
						multiplier = tonumber(input.multiplier) or 1,
						threshold = tonumber(input.threshold) or 0,
						reverse = input.reverse and true or false,
					})
				end
			end
		end
	end
	return result
end

local function getTarget()
	if FaceTracker.Player and FaceTracker.Player.RefreshFaceTarget then
		local entity = FaceTracker.Player.RefreshFaceTarget()
		return entity
	end
	return LocalPlayer(), "player"
end

local function candidates()
	local result = {}
	local player = LocalPlayer()
	if IsValid(player) and player.GetFlexNum and player:GetFlexNum() > 0 then
		table.insert(result, {entity = player, label = "玩家本体 | " .. (player:GetModel() or "unknown")})
	end
	if FaceTracker.Player and FaceTracker.Player.GetPac3Candidates then
		for _, entity in ipairs(FaceTracker.Player.GetPac3Candidates() or {}) do
			if IsValid(entity) and entity.GetFlexNum and entity:GetFlexNum() > 0 then
				table.insert(result, {entity = entity, label = Format("PAC3 [%d] | %s", entity:EntIndex(), entity:GetModel() or "unknown")})
			end
		end
	end
	for _, entity in ipairs(ents.GetAll()) do
		if IsValid(entity) and entity ~= player and entity.GetFlexNum and entity:GetFlexNum() > 0 then
			local class = entity:GetClass() or ""
			if class == "npc_*" or string.StartWith(class, "npc_") or class == "prop_ragdoll" then
				table.insert(result, {entity = entity, label = Format("%s [%d] | %s", class, entity:EntIndex(), entity:GetModel() or "unknown")})
			end
		end
	end
	return result
end

local function openCreator()
	if IsValid(FaceTracker.FlexCreatorFrame) then
		FaceTracker.FlexCreatorFrame:MakePopup()
		return FaceTracker.FlexCreatorFrame
	end
	local frame = vgui.Create("DFrame")
	FaceTracker.FlexCreatorFrame = frame
	frame:SetTitle("茶茶捕捉 · Flex 表情制作")
	frame:SetSize(900, 720)
	frame:Center()
	frame:MakePopup()
	frame:SetDeleteOnClose(false)
	frame.OnClose = function(self)
		-- DFrame remains valid when hidden; remove the reference so the next
		-- command creates a fresh editor instead of returning a deleted panel.
		FaceTracker.FlexCreatorFrame = nil
		self:Remove()
	end

	local target = NULL
	local values = {}
	local rows = {}
	local mapping = {}
	local rawExpressions = {}
	local mappingRows = {}
	local editingMapping
	local selectedFlexValue
	local selectedChannelValue
	local top = vgui.Create("DPanel", frame)
	top:Dock(TOP)
	top:SetTall(86)
	top:DockPadding(8, 6, 8, 6)
	local targets = vgui.Create("DComboBox", top)
	targets:Dock(TOP)
	targets:SetTall(24)
	targets:SetTextColor(Color(0, 0, 0))
	local nameEntry = vgui.Create("DTextEntry", top)
	nameEntry:Dock(TOP)
	nameEntry:DockMargin(0, 5, 0, 0)
	nameEntry:SetPlaceholderText("模型专属预设名称，例如：anon_expressive")
	nameEntry:SetTextColor(Color(0, 0, 0))
	local search = vgui.Create("DTextEntry", frame)
	search:Dock(TOP)
	search:DockMargin(8, 6, 8, 0)
	search:SetTall(24)
	search:SetPlaceholderText("搜索 Flex 名称")
	search:SetTextColor(Color(0, 0, 0))
	local mappingLabel = vgui.Create("DLabel", frame)
	mappingLabel:Dock(TOP)
	mappingLabel:DockMargin(8, 4, 8, 0)
	mappingLabel:SetText("选择 Flex 后可添加 ARKit 通道；面捕运行时会实时预览映射效果。")
	mappingLabel:SetTextColor(Color(0, 0, 0))
	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 6, 8, 4)
	local actions = vgui.Create("DPanel", frame)
	actions:Dock(BOTTOM)
	actions:SetTall(42)
	local refresh = vgui.Create("DButton", actions)
	refresh:Dock(LEFT)
	refresh:SetWide(130)
	refresh:SetText("刷新目标/Flex")
	local clear = vgui.Create("DButton", actions)
	clear:Dock(LEFT)
	clear:SetWide(130)
	clear:DockMargin(6, 0, 0, 0)
	clear:SetText("清空当前表情")
	local load = vgui.Create("DButton", actions)
	load:Dock(LEFT)
	load:SetWide(130)
	load:DockMargin(6, 0, 0, 0)
	load:SetText("导入 .txt 预设")
	local save = vgui.Create("DButton", actions)
	save:Dock(RIGHT)
	save:SetWide(130)
	save:SetText("导出表情预设")
	local mappingPanel = vgui.Create("DPanel", frame)
	mappingPanel:Dock(BOTTOM)
	mappingPanel:SetTall(116)
	mappingPanel:DockPadding(8, 4, 8, 4)
	local selectedFlex = vgui.Create("DComboBox", mappingPanel)
	selectedFlex:Dock(LEFT)
	selectedFlex:SetWide(170)
	selectedFlex:SetTextColor(Color(0, 0, 0))
	local selectedChannel = vgui.Create("DComboBox", mappingPanel)
	selectedChannel:Dock(LEFT)
	selectedChannel:DockMargin(6, 0, 0, 0)
	selectedChannel:SetWide(170)
	selectedChannel:SetTextColor(Color(0, 0, 0))
	local weight = vgui.Create("DNumSlider", mappingPanel)
	weight:Dock(LEFT)
	weight:SetWide(135)
	weight:DockMargin(6, 0, 0, 0)
	weight:SetText("权重")
	weight:SetMinMax(-2, 2)
	weight:SetDecimals(2)
	styleNumSlider(weight)
	local addMapping = vgui.Create("DButton", mappingPanel)
	addMapping:Dock(RIGHT)
	addMapping:SetWide(110)
	addMapping:SetText("添加映射")
	local mappingList = vgui.Create("DScrollPanel", frame)
	mappingList:Dock(RIGHT)
	mappingList:SetWide(330)
	mappingList:DockMargin(6, 6, 8, 4)
	local mappingTitle = vgui.Create("DLabel", mappingList)
	mappingTitle:Dock(TOP)
	mappingTitle:SetTall(22)
	mappingTitle:SetText("已添加映射（单击编辑，双击删除）")
	mappingTitle:SetTextColor(Color(0, 0, 0))

	local multiplier = vgui.Create("DNumSlider", mappingPanel)
	multiplier:Dock(LEFT)
	multiplier:SetWide(125)
	multiplier:SetText("倍率")
	multiplier:SetMinMax(0, 4)
	multiplier:SetDecimals(2)
	multiplier:SetValue(1)
	styleNumSlider(multiplier)
	local threshold = vgui.Create("DNumSlider", mappingPanel)
	threshold:Dock(LEFT)
	threshold:SetWide(120)
	threshold:SetText("阈值")
	threshold:SetMinMax(0, 1)
	threshold:SetDecimals(2)
	styleNumSlider(threshold)
	local reverse = vgui.Create("DCheckBoxLabel", mappingPanel)
	reverse:Dock(LEFT)
	reverse:SetWide(62)
	reverse:SetText("反向")
	reverse:SetTextColor(Color(0, 0, 0))
	local mappingSpacer = vgui.Create("DPanel", mappingPanel)
	mappingSpacer:Dock(FILL)

	local function rebuildRows()
		for _, row in ipairs(rows) do row:Remove() end
		rows = {}
		if not IsValid(target) then return end
		local filter = string.lower(string.Trim(search:GetValue() or ""))
		for id = 0, target:GetFlexNum() - 1 do
			local flexName = target:GetFlexName(id)
			if filter == "" or string.find(string.lower(flexName), filter, 1, true) then
				local row = vgui.Create("DPanel", scroll:GetCanvas())
				row:Dock(TOP)
				row:SetTall(42)
				row:DockMargin(0, 0, 0, 3)
				local label = vgui.Create("DLabel", row)
				label:Dock(LEFT)
				label:SetWide(250)
				label:SetText(flexName)
				label:SetTextColor(Color(0, 0, 0))
				label:SetContentAlignment(4)
				local slider = vgui.Create("DNumSlider", row)
				slider:Dock(FILL)
				slider:SetText("")
				slider:SetMinMax(0, 2)
				slider:SetDecimals(2)
				slider:SetValue(values[flexName] or 0)
				styleNumSlider(slider)
				function slider:OnValueChanged(value)
					values[flexName] = math.abs(value) > 0.0001 and value or nil
					if IsValid(target) then target:SetFlexWeight(id, value) end
				end
				table.insert(rows, row)
			end
		end
		selectedFlex:Clear()
		for id = 0, target:GetFlexNum() - 1 do
			local flexName = target:GetFlexName(id)
			selectedFlex:AddChoice(flexName, flexName)
			if not selectedFlexValue then selectedFlexValue = flexName end
		end
	end

	local function rebuildMappingRows()
		for _, row in ipairs(mappingRows) do if IsValid(row) then row:Remove() end end
		mappingRows = {}
		for flexName, inputs in pairs(mapping) do
			for index, input in ipairs(inputs) do
				local row = vgui.Create("DButton", mappingList:GetCanvas())
				row:Dock(TOP)
				row:SetTall(28)
				row:DockMargin(0, 0, 0, 3)
				row:SetText(Format("%s <- %s x %.2f [%.2f]", flexName, input.channel, input.weight, input.threshold or 0))
				row:SetTextColor(Color(0, 0, 0))
				row.DoClick = function()
					editingMapping = {flex = flexName, index = index}
					selectedFlexValue = flexName
					selectedChannelValue = input.channel
					selectedFlex:SetValue(flexName)
					selectedChannel:SetValue(input.channel)
					weight:SetValue(input.weight)
					multiplier:SetValue(input.multiplier or 1)
					threshold:SetValue(input.threshold or 0)
					reverse:SetValue(input.reverse and 1 or 0)
					addMapping:SetText("修改映射")
				end
				row.DoDoubleClick = function()
					table.remove(mapping[flexName], index)
					if #mapping[flexName] == 0 then mapping[flexName] = nil end
					rawExpressions[flexName] = nil
					rebuildMappingRows()
				end
				table.insert(mappingRows, row)
			end
		end
	end

	local function rebuildChannels()
		selectedChannel:Clear()
		for _, channel in ipairs(CHANNELS) do
			selectedChannel:AddChoice(channel, channel)
			if not selectedChannelValue then selectedChannelValue = channel end
		end
	end

	local function choose(entity)
		target = entity
		values = {}
		mapping = {}
		rawExpressions = {}
		editingMapping = nil
		selectedFlexValue = nil
		selectedChannelValue = nil
		if IsValid(target) then
			for id = 0, target:GetFlexNum() - 1 do values[target:GetFlexName(id)] = target:GetFlexWeight(id) end
		end
		rebuildRows()
		rebuildMappingRows()
	end

	local function applyPreset(data, filename)
		if not istable(data) then return false end
		values = {}
		mapping = copyMappings(data.mappings)
		rawExpressions = {}
		selectedFlexValue = nil
		selectedChannelValue = nil
		for flexName, value in pairs(istable(data.values) and data.values or {}) do
			if isstring(flexName) and tonumber(value) then values[flexName] = tonumber(value) end
		end
		local expressions = data.expressions or data
		local unsupported = 0
		for flexName, expression in pairs(expressions) do
			if not isstring(flexName) or not isstring(expression) and not isnumber(expression) then continue end
			local static = tonumber(expression)
			if static then
				if values[flexName] == nil then values[flexName] = static end
			elseif not mapping[flexName] then
				local parsed = parseLinearExpression(expression)
				if parsed then
					if math.abs(parsed.constant) > 0.0001 then values[flexName] = parsed.constant end
					for channel, weightValue in pairs(parsed.terms) do
						if math.abs(weightValue) > 0.0001 then
							mapping[flexName] = mapping[flexName] or {}
							table.insert(mapping[flexName], {channel = channel, weight = weightValue, multiplier = 1, threshold = 0, reverse = false})
						end
					end
			else
				unsupported = unsupported + 1
				rawExpressions[flexName] = expression
				end
			end
		end
		rebuildRows()
		rebuildMappingRows()
		nameEntry:SetValue(data.name or string.StripExtension(filename or ""))
		local suffix = unsupported > 0 and Format("，有 %d 项复杂表达式保留为高级表达式", unsupported) or ""
		notify("已导入预设：" .. tostring(filename or data.name or "unknown") .. suffix, unsupported > 0 and NOTIFY_ERROR or NOTIFY_HINT)
		return true
	end

	local function loadPresetFile(filename, pathId)
		local path = CREATOR_DIRECTORY .. "/" .. filename
		local raw = file.Read(path, pathId or "DATA")
		local data = raw and util.JSONToTable(raw)
		if not istable(data) then return false end
		return applyPreset(data, filename)
	end

	local function loadModelPreset()
		if not IsValid(target) then notify("请先选择目标模型。", NOTIFY_ERROR); return end
		local menu = DermaMenu()
		local found = 0
		local seen = {}
		for _, filename in ipairs(file.Find(CREATOR_DIRECTORY .. "/*.txt", "DATA") or {}) do
			local raw = file.Read(CREATOR_DIRECTORY .. "/" .. filename, "DATA") or ""
			local data = util.JSONToTable(raw)
			if istable(data) then
				local label = filename
				if data.model and data.model ~= "" then label = label .. " | " .. data.model end
				menu:AddOption(label, function() applyPreset(data, filename) end)
				seen[string.lower(filename)] = true
				found = found + 1
			end
		end
		for _, filename in ipairs(file.Find("data_static/facetracker/presets/*.txt", "GAME") or {}) do
			local raw = file.Read("data_static/facetracker/presets/" .. filename, "GAME") or ""
			local data = util.JSONToTable(raw)
			if istable(data) and not seen[string.lower(filename)] then
				menu:AddOption("内置：" .. filename, function() applyPreset(data, filename) end)
				found = found + 1
			end
		end
		if found == 0 then menu:AddOption("没有找到可导入的 .txt 预设"):SetEnabled(false) end
		menu:Open()
	end

	local function rebuildTargets()
		targets:Clear()
		for _, item in ipairs(candidates()) do targets:AddChoice(item.label, item.entity) end
		local entity = getTarget()
		if IsValid(entity) then choose(entity) end
	end
	targets.OnSelect = function(_, _, _, entity) choose(entity) end
	selectedFlex.OnSelect = function(_, _, value, data) selectedFlexValue = data or value end
	selectedChannel.OnSelect = function(_, _, value, data) selectedChannelValue = data or value end
	search.OnValueChange = rebuildRows
	refresh.DoClick = rebuildTargets
	load.DoClick = loadModelPreset
	clear.DoClick = function() values = {}; mapping = {}; rawExpressions = {}; editingMapping = nil; addMapping:SetText("添加映射"); rebuildRows(); rebuildMappingRows() end
	addMapping.DoClick = function()
		local flex = selectedFlexValue
		local channel = selectedChannelValue
		if not flex or not channel then notify("请先选择目标 Flex 和 ARKit 通道。", NOTIFY_ERROR); return end
		local item = {channel = channel, weight = tonumber(weight:GetValue()) or 0, multiplier = tonumber(multiplier:GetValue()) or 1, threshold = tonumber(threshold:GetValue()) or 0, reverse = reverse:GetChecked()}
		if editingMapping and mapping[editingMapping.flex] and mapping[editingMapping.flex][editingMapping.index] then
			mapping[editingMapping.flex][editingMapping.index] = item
			rawExpressions[editingMapping.flex] = nil
		else
			mapping[flex] = mapping[flex] or {}
			table.insert(mapping[flex], item)
			rawExpressions[flex] = nil
		end
		editingMapping = nil
		addMapping:SetText("添加映射")
		rebuildMappingRows()
		values[flex] = 0
		notify(Format("已添加映射：%s ← %s × %.2f", flex, channel, item.weight), NOTIFY_HINT)
	end
	save.DoClick = function()
		if not IsValid(target) then notify("请先选择带 Flex 的目标。", NOTIFY_ERROR); return end
		local name = string.Trim(nameEntry:GetValue() or "")
		if name == "" then notify("请先输入表情名称。", NOTIFY_ERROR); return end
		file.CreateDir("facetracker")
		file.CreateDir(CREATOR_DIRECTORY)
		local safe = string.gsub(string.lower(name), "[^%w_%-]", "_")
		local expressions = {}
		local staticValues = {}
		for flexName, expression in pairs(rawExpressions) do expressions[flexName] = expression end
		for flexName, value in pairs(values) do
			if isnumber(value) and math.abs(value) > 0.0001 then
				staticValues[flexName] = math.Round(value, 4)
				expressions[flexName] = tostring(math.Round(value, 4))
			end
		end
		for flexName, inputs in pairs(mapping) do
			local parts = {}
			if isnumber(values[flexName]) and math.abs(values[flexName]) > 0.0001 then
				table.insert(parts, tostring(math.Round(values[flexName], 4)))
			end
			for _, input in ipairs(inputs) do
				local scale = math.Round(input.weight * (input.multiplier or 1), 4)
				local term = input.channel .. "*" .. tostring(scale)
				if (input.threshold or 0) > 0 then term = "max(0,(" .. input.channel .. "-" .. input.threshold .. "))*" .. tostring(scale) end
				if input.reverse then term = "(1-" .. term .. ")" end
				table.insert(parts, term)
			end
			if #parts > 0 then expressions[flexName] = table.concat(parts, "+") end
		end
		local data = {name = safe, expressions = expressions, values = staticValues, mappings = mapping, eyeExpressions = {x = "0.5", y = "0.5", s = 0}, model = target:GetModel() or ""}
		file.CreateDir("facetracker")
		file.CreateDir(CREATOR_DIRECTORY)
		file.Write(CREATOR_DIRECTORY .. "/" .. safe .. ".txt", util.TableToJSON(data, true))
		notify("模型专属 Flex 预设已导出到 data/facetracker/presets/" .. safe .. ".txt")
	end
	rebuildTargets()
	rebuildChannels()
	rebuildMappingRows()
	hook.Add("Think", frame, function()
		if not IsValid(frame) or not IsValid(target) or not FaceTracker.Parser then return end
		for flexName, expression in pairs(rawExpressions) do
			local ok, value = pcall(FaceTracker.Parser.solve, FaceTracker.Parser, expression)
			local id = target:GetFlexIDByName(flexName)
			if ok and isnumber(value) and id and id >= 0 then target:SetFlexWeight(id, math.Clamp(value + (values[flexName] or 0), 0, 2)) end
		end
		for flexName, inputs in pairs(mapping) do
			local total = values[flexName] or 0
			for _, input in ipairs(inputs) do
				local channelValue = FaceTracker.Parser:solve(input.channel) or 0
				if input.reverse then channelValue = 1 - channelValue end
				if channelValue < (input.threshold or 0) then channelValue = 0 end
				total = total + channelValue * input.weight * (input.multiplier or 1)
			end
			local id = target:GetFlexIDByName(flexName)
			if id and id >= 0 then target:SetFlexWeight(id, math.Clamp(total, 0, 2)) end
		end
	end)
	frame.OnRemove = function() hook.Remove("Think", frame) end
	return frame
end

FaceTracker.FlexCreator = {Open = openCreator}
concommand.Add("facetracker_flex_creator", openCreator)
