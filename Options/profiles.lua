local SCM = select(2, ...)
local AceGUI = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

SCM.MainTabs.Profiles = { value = "Profiles", text = "Profiles", order = 3, subgroups = {} }

local classFileNameToID = {}
local function GetSpecList(classFileName)
	local specs = {}
	if classFileName and classFileNameToID[classFileName] then
		local classID = classFileNameToID[classFileName]
		for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
			local id, name, _, icon = GetSpecializationInfoForClassID(classID, specIndex)
			if id and name and icon then
				specs[id] = ("|T%s:14:14:0:0|t %s"):format(icon, name)
			end
		end
	end
	return specs
end

local function GetClassList()
	local classes = { ["ALL"] = "All" }

	for classIndex = 1, GetNumClasses() do
		local className, classFile, classID = GetClassInfo(classIndex)

		if className and classFile and classID then
			local classColor = GetClassColorObj(classFile)
			classes[classFile] = ("|A:%s:0:0|a %s"):format(GetClassAtlas(classFile), classColor:WrapTextInColorCode(className))
			classFileNameToID[classFile] = classID
		end
	end
	return classes
end

local function CreateImportEditBox(Profiles, widget, frame, group, hasProfileName)
	widget:ReleaseChildren()

	local editGroup = AceGUI:Create("InlineGroup")
	editGroup:SetFullWidth(true)
	editGroup:SetFullHeight(true)
	editGroup:SetLayout("flow")
	widget:AddChild(editGroup)

	local profileName
	if hasProfileName then
		profileName = AceGUI:Create("EditBox")
		profileName:SetFullWidth(true)
		profileName:SetLabel("Profile Name")
		editGroup:AddChild(profileName)
	end

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
	importGroup:SetTitle("Import Profile")
	importGroup:SetFullWidth(true)
	importGroup:SetLayout("flow")
	profilesGroup:AddChild(importGroup)

	local importButton = AceGUI:Create("Button")
	importButton:SetText("Import Profile")
	importButton:SetRelativeWidth(0.33)
	importButton:SetCallback("OnClick", function()
		local editBox, profileName = CreateImportEditBox(Profiles, widget, frame, group, true)
		editBox:SetCallback("OnEnterPressed", function(self, event, text)
			SCM:ImportProfile(profileName:GetText(), text)
			Profiles(widget, frame, group)
		end)
	end)
	importGroup:AddChild(importButton)

	local importButton = AceGUI:Create("Button")
	importButton:SetText("Import Global Settings")
	importButton:SetRelativeWidth(0.33)
	importButton:SetCallback("OnClick", function()
		local editBox = CreateImportEditBox(Profiles, widget, frame, group)
		editBox:SetCallback("OnEnterPressed", function(self, event, text)
			SCM:ImportGlobalSettings(text)
			Profiles(widget, frame, group)
		end)
	end)
	importGroup:AddChild(importButton)

	local importGlobalAnchors = AceGUI:Create("Button")
	importGlobalAnchors:SetText("Import Global Anchors")
	importGlobalAnchors:SetRelativeWidth(0.33)
	importGlobalAnchors:SetCallback("OnClick", function()
		local editBox = CreateImportEditBox(Profiles, widget, frame, group)
		editBox:SetCallback("OnEnterPressed", function(self, event, text)
			SCM:ImportGlobalAnchors(text)
			Profiles(widget, frame, group)
		end)
	end)
	importGroup:AddChild(importGlobalAnchors)

	local exportGroup = AceGUI:Create("InlineGroup")
	exportGroup:SetTitle("Export Profile")
	exportGroup:SetFullWidth(true)
	exportGroup:SetLayout("flow")
	profilesGroup:AddChild(exportGroup)

	local classDropdown = AceGUI:Create("Dropdown")
	classDropdown:SetLabel("Select Class")
	classDropdown:SetList(GetClassList())
	classDropdown:SetRelativeWidth(0.33)
	classDropdown.text:SetJustifyH("LEFT")
	exportGroup:AddChild(classDropdown)

	local specDropdown = AceGUI:Create("Dropdown")
	specDropdown:SetLabel("Select Spec")
	specDropdown:SetList(GetSpecList(), SCM.Constants.SpecIDs)
	specDropdown:SetRelativeWidth(0.33)
	specDropdown:SetDisabled(true)
	specDropdown.text:SetJustifyH("LEFT")
	exportGroup:AddChild(specDropdown)

	local exportButton = AceGUI:Create("Button")
	exportButton:SetText("Export Profile")
	exportButton:SetRelativeWidth(0.33)
	exportButton:SetCallback("OnClick", function()
		local selectedClass = classDropdown:GetValue()
		local selectedSpec = specDropdown:GetValue()
		CreateExportEditBox(Profiles, widget, frame, group, SCM:ExportProfile(widget, selectedClass, selectedSpec))
	end)
	exportButton:SetDisabled(classDropdown:GetValue() ~= nil)
	exportGroup:AddChild(exportButton)

	classDropdown:SetCallback("OnValueChanged", function(self, event, value)
		local filteredSpecs = GetSpecList(value)
		specDropdown:SetList(filteredSpecs)

		specDropdown:SetValue(nil)
		specDropdown:SetDisabled(next(filteredSpecs) == nil)
		exportButton:SetDisabled(false)
	end)

	local exportGlobalSettings = AceGUI:Create("Button")
	exportGlobalSettings:SetText("Export Global Settings")
	exportGlobalSettings:SetRelativeWidth(0.33)
	exportGlobalSettings:SetCallback("OnClick", function()
		CreateExportEditBox(Profiles, widget, frame, group, SCM:ExportGlobalSettings())
	end)
	exportGroup:AddChild(exportGlobalSettings)

	local exportGlobalAnchors = AceGUI:Create("Button")
	exportGlobalAnchors:SetText("Export Global Anchors")
	exportGlobalAnchors:SetRelativeWidth(0.33)
	exportGlobalAnchors:SetCallback("OnClick", function()
		CreateExportEditBox(Profiles, widget, frame, group, SCM:ExportGlobalAnchors())
	end)
	exportGroup:AddChild(exportGlobalAnchors)

	local dbOptionsGroup = AceGUI:Create("InlineGroup")
	dbOptionsGroup:SetTitle("Profile Management")
	dbOptionsGroup:SetFullWidth(true)
	dbOptionsGroup:SetLayout("fill")
	profilesGroup:AddChild(dbOptionsGroup)

	local profileOptions = AceDBOptions:GetOptionsTable(SCM.db)
	AceConfig:RegisterOptionsTable("SCM_Profiles_OptionTable", profileOptions)
	AceConfigDialog:Open("SCM_Profiles_OptionTable", dbOptionsGroup)
end

SCM.MainTabs.Profiles.callback = Profiles
