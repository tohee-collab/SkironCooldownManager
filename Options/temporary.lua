local addonName, SCM = ...
local AceGUI = LibStub("AceGUI-3.0")

SCM.MainTabs.Temporary = { value = "Temporary", text = "Temporary", order = 4, subgroups = {} }

local function Temporary(self, frame, group)
	local options = SCM.db.global.options

	local generalFrame = AceGUI:Create("InlineGroup")
	generalFrame:SetLayout("flow")
	generalFrame:SetFullWidth(true)
	generalFrame:SetFullHeight(true)
	self:AddChild(generalFrame)

	local label = AceGUI:Create("Label")
	label:SetRelativeWidth(1.0)
	label:SetHeight(24)
	label:SetJustifyH("CENTER")
	label:SetJustifyV("MIDDLE")
	label:SetText("|TInterface\\common\\help-i:40:40:0:0|tSome options will be removed once a better alternative has been found/made.")
	label:SetFontObject("Game12Font")
	generalFrame:AddChild(label)

	local uufSettings = AceGUI:Create("InlineGroup")
	uufSettings:SetFullWidth(true)
	uufSettings:SetLayout("flow")
	uufSettings:SetTitle("Unit Frames")
	generalFrame:AddChild(uufSettings)

	local anchorUUF = AceGUI:Create("CheckBox")
	anchorUUF:SetRelativeWidth(0.5)
	anchorUUF:SetLabel("Reanchor UUF")
	anchorUUF:SetValue(options.anchorUUF)
	anchorUUF:SetCallback("OnValueChanged", function(_, _, value)
		options.anchorUUF = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	uufSettings:AddChild(anchorUUF)

	local anchorElvUI = AceGUI:Create("CheckBox")
	anchorElvUI:SetRelativeWidth(0.5)
	anchorElvUI:SetLabel("Reanchor ElvUI")
	anchorElvUI:SetValue(options.anchorElvUI)
	anchorElvUI:SetCallback("OnValueChanged", function(_, _, value)
		options.anchorElvUI = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	uufSettings:AddChild(anchorElvUI)

	local resourceBarSettings = AceGUI:Create("InlineGroup")
	resourceBarSettings:SetLayout("flow")
	resourceBarSettings:SetFullWidth(true)
	resourceBarSettings:SetTitle("Resource Bar")
	generalFrame:AddChild(resourceBarSettings)

	local adjustResourceWidth = AceGUI:Create("CheckBox")
	adjustResourceWidth:SetRelativeWidth(0.5)
	adjustResourceWidth:SetLabel("Adjust Resource Bar Width")
	adjustResourceWidth:SetValue(options.adjustResourceWidth)
	adjustResourceWidth:SetCallback("OnValueChanged", function(_, _, value)
		options.adjustResourceWidth = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	resourceBarSettings:AddChild(adjustResourceWidth)

	local listContainer = AceGUI:Create("SimpleGroup")
	listContainer:SetLayout("flow")
	listContainer:SetFullWidth(true)

	local function RefreshList()
		listContainer:ReleaseChildren()

		for i, name in ipairs(options.resourceBars) do
			local row = AceGUI:Create("SimpleGroup")
			row:SetLayout("flow")
			row:SetFullWidth(true)
			listContainer:AddChild(row)

			local label = AceGUI:Create("Label")
			label:SetText(name)
			label:SetRelativeWidth(0.8)
			row:AddChild(label)

			local removeBtn = AceGUI:Create("Button")
			removeBtn:SetText("Delete")
			removeBtn:SetRelativeWidth(0.15)
			removeBtn:SetCallback("OnClick", function()
				table.remove(options.resourceBars, i)
				RefreshList()
			end)
			row:AddChild(removeBtn)
		end

		listContainer:DoLayout()
		resourceBarSettings:DoLayout()
		generalFrame:DoLayout()
	end

	local addResourceBarButton = AceGUI:Create("EditBox")
	addResourceBarButton:SetRelativeWidth(0.8)
	addResourceBarButton:SetLabel("Add Frame Name")
	addResourceBarButton:SetCallback("OnEnterPressed", function(self, _, value)
		if value and value ~= "" then
			table.insert(options.resourceBars, value)
			self:SetText("")
			RefreshList()
			SCM:ApplyAllCDManagerConfigs()
		end
	end)
	resourceBarSettings:AddChild(addResourceBarButton)
	resourceBarSettings:AddChild(listContainer)

	RefreshList()
end

SCM.MainTabs.Temporary.callback = Temporary
