local SCM = select(2, ...)
local AceGUI = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

SCM.MainTabs.Profiles = { value = "Profiles", text = "Profiles", order = 9, subgroups = {} }

local function CreateImportEditBox(Profiles, widget, frame, group)
	widget:ReleaseChildren()

	local editGroup = AceGUI:Create("InlineGroup")
	editGroup:SetFullWidth(true)
	editGroup:SetFullHeight(true)
	editGroup:SetLayout("flow")
	widget:AddChild(editGroup)

	local profileName = AceGUI:Create("EditBox")
	profileName:SetFullWidth(true)
	profileName:SetLabel("Profile Name (Optional)")
	editGroup:AddChild(profileName)

	local editBox = AceGUI:Create("MultiLineEditBox")
	editBox:SetFullWidth(true)
	editBox:SetFullHeight(true)
	editBox:SetLabel("Import")
	editBox:SetFocus()
	editBox.editBox:HighlightText()
	editBox.editBox:SetScript("OnEscapePressed", function()
		Profiles(widget, frame, group)
	end)

	editBox.frame:SetClipsChildren(true)
	editGroup:AddChild(editBox)
	return editBox, profileName
end

local function CreateExportEditBox(Profiles, widget, frame, group, exportString)
	if not exportString then
		return
	end

	widget:ReleaseChildren()

	local editGroup = AceGUI:Create("InlineGroup")
	editGroup:SetFullWidth(true)
	editGroup:SetFullHeight(true)
	editGroup:SetLayout("fill")
	widget:AddChild(editGroup)

	local editBox = AceGUI:Create("MultiLineEditBox")
	editBox:SetLabel("Export")
	editBox:SetText(exportString)
	editBox:SetFocus()
	editBox.editBox:HighlightText()
	editBox.editBox:SetScript("OnEscapePressed", function()
		Profiles(widget, frame, group)
	end)
	editBox.button:Hide()
	editBox.frame:SetClipsChildren(true)
	editGroup:AddChild(editBox)
end

local function Profiles(widget, frame, group)
	widget:ReleaseChildren()

	local profilesGroup = AceGUI:Create("InlineGroup")
	profilesGroup:SetFullWidth(true)
	profilesGroup:SetFullHeight(true)
	profilesGroup:SetLayout("flow")
	widget:AddChild(profilesGroup)

	local importGroup = AceGUI:Create("InlineGroup")
	importGroup:SetTitle("Import")
	importGroup:SetFullWidth(true)
	importGroup:SetLayout("flow")
	profilesGroup:AddChild(importGroup)

	local importButton = AceGUI:Create("Button")
	importButton:SetText("Import")
	importButton:SetRelativeWidth(1)
	importButton:SetCallback("OnClick", function()
		local editBox, profileName = CreateImportEditBox(Profiles, widget, frame, group)
		editBox:SetCallback("OnEnterPressed", function(self, event, text)
			SCM:ImportProfile(profileName:GetText(), text)
			Profiles(widget, frame, group)
		end)
	end)
	importGroup:AddChild(importButton)

	local exportGroup = AceGUI:Create("InlineGroup")
	exportGroup:SetTitle("Export Profile")
	exportGroup:SetFullWidth(true)
	exportGroup:SetLayout("flow")
	profilesGroup:AddChild(exportGroup)

	local exportState = {
		useSpecificClass = false,
		useSpecificSpec = false,
		includeResourceBar = false,
		includeCastBar = false,
		includeGlobalSettings = false,
		includeGlobalAnchors = false,
	}

	local specificClassCheckbox = AceGUI:Create("CheckBox")
	specificClassCheckbox:SetLabel("Class")
	specificClassCheckbox:SetRelativeWidth(0.5)
	specificClassCheckbox:SetValue(exportState.useSpecificClass)
	exportGroup:AddChild(specificClassCheckbox)

	local classDropdown = AceGUI:Create("Dropdown")
	classDropdown:SetLabel("Select Class")
	classDropdown:SetList(SCM.Utils.GetClassList(true))
	classDropdown:SetRelativeWidth(0.5)
	classDropdown:SetDisabled(true)
	classDropdown.text:SetJustifyH("LEFT")
	exportGroup:AddChild(classDropdown)

	local specificSpecCheckbox = AceGUI:Create("CheckBox")
	specificSpecCheckbox:SetLabel("Specific Spec")
	specificSpecCheckbox:SetRelativeWidth(0.5)
	specificSpecCheckbox:SetValue(exportState.useSpecificSpec)
	specificSpecCheckbox:SetDisabled(true)
	exportGroup:AddChild(specificSpecCheckbox)

	local specDropdown = AceGUI:Create("Dropdown")
	specDropdown:SetLabel("Select Spec")
	specDropdown:SetList({})
	specDropdown:SetRelativeWidth(0.5)
	specDropdown:SetDisabled(true)
	specDropdown.text:SetJustifyH("LEFT")
	exportGroup:AddChild(specDropdown)

	local resourceBarCheckbox = AceGUI:Create("CheckBox")
	resourceBarCheckbox:SetLabel("Resource Bar Settings")
	resourceBarCheckbox:SetRelativeWidth(0.25)
	resourceBarCheckbox:SetValue(exportState.includeResourceBar)
	exportGroup:AddChild(resourceBarCheckbox)

	local castBarCheckbox = AceGUI:Create("CheckBox")
	castBarCheckbox:SetLabel("Cast Bar Settings")
	castBarCheckbox:SetRelativeWidth(0.25)
	castBarCheckbox:SetValue(exportState.includeCastBar)
	exportGroup:AddChild(castBarCheckbox)

	local globalSettingsCheckbox = AceGUI:Create("CheckBox")
	globalSettingsCheckbox:SetLabel("Global Settings")
	globalSettingsCheckbox:SetRelativeWidth(0.25)
	globalSettingsCheckbox:SetValue(exportState.includeGlobalSettings)
	exportGroup:AddChild(globalSettingsCheckbox)

	local globalAnchorsCheckbox = AceGUI:Create("CheckBox")
	globalAnchorsCheckbox:SetLabel("Global Icon Anchors")
	globalAnchorsCheckbox:SetRelativeWidth(0.25)
	globalAnchorsCheckbox:SetValue(exportState.includeGlobalAnchors)
	exportGroup:AddChild(globalAnchorsCheckbox)

	local exportButton = AceGUI:Create("Button")
	exportButton:SetText("Export")
	exportButton:SetRelativeWidth(1)
	exportButton:SetCallback("OnClick", function()
		local selectedClass = exportState.useSpecificClass and classDropdown:GetValue() or nil
		local selectedSpec = exportState.useSpecificSpec and specDropdown:GetValue() or nil
		CreateExportEditBox(
			Profiles,
			widget,
			frame,
			group,
			SCM:ExportProfile(selectedClass, selectedSpec, {
				includeResourceBar = resourceBarCheckbox:GetValue(),
				includeCastBar = castBarCheckbox:GetValue(),
				includeGlobalSettings = globalSettingsCheckbox:GetValue(),
				includeGlobalAnchors = globalAnchorsCheckbox:GetValue(),
			})
		)
	end)
	exportGroup:AddChild(exportButton)

	local function RefreshExportControls()
		local selectedClass = classDropdown:GetValue()
		local hasSpecificClass = exportState.useSpecificClass and selectedClass ~= nil
		local filteredSpecs = hasSpecificClass and SCM.Utils.GetSpecList(selectedClass) or {}
		local hasSpecs = next(filteredSpecs) ~= nil

		classDropdown:SetDisabled(not exportState.useSpecificClass)
		specificSpecCheckbox:SetDisabled(not hasSpecificClass or not hasSpecs)

		if (not hasSpecificClass or not hasSpecs) and exportState.useSpecificSpec then
			exportState.useSpecificSpec = false
			specificSpecCheckbox:SetValue(false)
		end

		specDropdown:SetList(filteredSpecs)
		if not filteredSpecs[specDropdown:GetValue()] then
			specDropdown:SetValue(nil)
		end
		specDropdown:SetDisabled(not exportState.useSpecificSpec or not hasSpecs)

		local hasOptions = exportState.includeResourceBar or exportState.includeCastBar or exportState.includeGlobalSettings or exportState.includeGlobalAnchors
		exportButton:SetDisabled((exportState.useSpecificClass and not selectedClass) or (exportState.useSpecificSpec and not specDropdown:GetValue()) or (not hasSpecificClass and not hasOptions))
	end

	specificClassCheckbox:SetCallback("OnValueChanged", function(_, _, value)
		exportState.useSpecificClass = value
		if not value then
			exportState.useSpecificSpec = false
			specificSpecCheckbox:SetValue(false)
			specDropdown:SetValue(nil)
		end
		RefreshExportControls()
	end)

	classDropdown:SetCallback("OnValueChanged", function(_, _, value)
		if not exportState.useSpecificClass then
			return
		end

		specDropdown:SetValue(nil)
		RefreshExportControls()
	end)

	specificSpecCheckbox:SetCallback("OnValueChanged", function(_, _, value)
		exportState.useSpecificSpec = value
		if not value then
			specDropdown:SetValue(nil)
		end
		RefreshExportControls()
	end)

	specDropdown:SetCallback("OnValueChanged", function()
		RefreshExportControls()
	end)

	resourceBarCheckbox:SetCallback("OnValueChanged", function(_, _, value)
		exportState.includeResourceBar = value
		RefreshExportControls()
	end)

	castBarCheckbox:SetCallback("OnValueChanged", function(_, _, value)
		exportState.includeCastBar = value
		RefreshExportControls()
	end)

	globalSettingsCheckbox:SetCallback("OnValueChanged", function(_, _, value)
		exportState.includeGlobalSettings = value
		RefreshExportControls()
	end)

	globalAnchorsCheckbox:SetCallback("OnValueChanged", function(_, _, value)
		exportState.includeGlobalAnchors = value
		RefreshExportControls()
	end)

	RefreshExportControls()

	local dbOptionsGroup = AceGUI:Create("InlineGroup")
	dbOptionsGroup:SetTitle("Profile Management")
	dbOptionsGroup:SetFullWidth(true)
	dbOptionsGroup:SetLayout("fill")
	profilesGroup:AddChild(dbOptionsGroup)

	local profileOptions = AceDBOptions:GetOptionsTable(SCM.db)
	SCM.LibDualSpec:EnhanceOptions(profileOptions, SCM.db)
	AceConfig:RegisterOptionsTable("SCM_Profiles_OptionTable", profileOptions)
	AceConfigDialog:Open("SCM_Profiles_OptionTable", dbOptionsGroup)
end

SCM.MainTabs.Profiles.callback = Profiles
