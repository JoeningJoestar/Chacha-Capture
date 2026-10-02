---@module "facetracker.shared.helpers"
local helpers = include("facetracker/shared/helpers.lua")

---Saves bone presets for a specific model and tries to load them if they are suspected to match the model's skeleton
---@source https://github.com/Winded/RagdollMover/blob/2c9c5a9417effc618e4530ce98f9b69f3ad817fe/lua/weapons/gmod_tool/stools/ragmover_ikchains.lua#L402
---@class facetracker_presetsaver: DPanel
local PANEL = {}

function PANEL:Init()
	self.selector = vgui.Create("DComboBox", self)
	self.entity = NULL

	self.save = vgui.Create("DButton", self)
	self.save:SetText("保存")
	self.save.DoClick = function()
		self:SavePreset()
	end

	self.load = vgui.Create("DButton", self)
	self.load:SetText("加载")
	self.load.DoClick = function()
		self:LoadPreset()
	end

	self:SetTall(45)
end

function PANEL:SetData(newData)
	self.data = newData
end

function PANEL:OnSavePreset()
	return ""
end

function PANEL:OnSaveSuccess() end

---@param msg string
function PANEL:OnSaveFailure(msg) end

function PANEL:SetEnabled(enabled)
	self.save:SetEnabled(enabled)
	self.load:SetEnabled(enabled)
	self.selector:SetEnabled(enabled)
end

function PANEL:SavePreset()
	if not IsValid(self.entity) then
		self:OnSaveFailure("尚未选择实体")
		return
	end
	local json = self:OnSavePreset()
	if not isstring(json) or #json == 0 then
		self:OnSaveFailure("没有可保存的数据")
		return
	end

	if not file.Exists(self.directory, "DATA") then
		file.CreateDir(self.directory)
	end

	local name = helpers.getModelNameNice(self.entity)
	if file.Exists(self.directory .. "/" .. name .. ".txt", "DATA") then
		local exists = true
		local count = 1

		while exists do
			local newname = name .. count

			if not file.Exists(self.directory .. "/" .. newname .. ".txt", "DATA") then
				name = newname
				exists = false
			end

			count = count + 1
		end
	end

	local path = self.directory .. "/" .. name .. ".txt"
	file.Write(path, json)
	if not file.Exists(path, "DATA") then
		self:OnSaveFailure("保存预设时发生错误")
		return
	end
	self:AddChoice(name)
	self:OnSaveSuccess()

	self:RefreshDirectory()
end

function PANEL:OnLoadPreset(preset) end

function PANEL:LoadPreset()
	local name = self.selector:GetSelected()
	if not name then
		return
	end
	if not file.Exists(self.directory, "DATA") or not file.Exists(self.directory .. "/" .. name .. ".txt", "DATA") then
		return
	end

	local json = file.Read(self.directory .. "/" .. name .. ".txt", "DATA")
	local preset = util.JSONToTable(json)
	if preset then
		self:OnLoadPreset(preset)
	end
end

function PANEL:PerformLayout()
	self.selector:SetPos(0, 0)
	self.selector:SetSize(self:GetWide(), 20)

	self.save:SetPos(0, 25)
	self.save:SetSize(self:GetWide() / 2 - 20, 20)

	self.load:SetPos(self:GetWide() / 2 + 20, 25)
	self.load:SetSize(self:GetWide() / 2 - 20, 20)
end

function PANEL:AddChoice(option)
	self.selector:AddChoice(option)
end

---@param newEntity Entity
function PANEL:SetEntity(newEntity)
	self.entity = newEntity
end

function PANEL:SetDirectory(newDirectory)
	self.directory = newDirectory
end

function PANEL:RefreshDirectory()
	if not file.Exists(self.directory, "DATA") then
		file.CreateDir(self.directory)
	end
	self.selector:Clear()

	local files = file.Find(self.directory .. "/*.txt", "DATA")
	for k, file in ipairs(files) do
		self.selector:AddChoice(string.sub(file, 1, -5))
	end
end

vgui.Register("facetracker_presetsaver", PANEL, "DPanel")
