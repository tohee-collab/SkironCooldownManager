local SCM = select(2, ...)

local dataVersion = 1
local EXPORT_TYPE_ALL = 0
local EXPORT_TYPE_CLASS = 1
local EXPORT_TYPE_GLOBAL_SETTINGS = 2
local EXPORT_TYPE_GLOBAL_ANCHORS = 3
local EXPORT_TYPE_EVERYTHING = 4
local GLOBAL_CUSTOM_CONFIG_KEYS = {
	"spellConfig",
	"itemConfig",
	"slotConfig",
	"timerConfig",
}
local PROFILE_OPTION_SECTION_KEYS = {
	resourceBars = true,
	resourceBar = true,
	castBar = true,
}

local function CopyValue(value)
	if type(value) == "table" then
		return CopyTable(value)
	end

	return value
end

local function BuildGeneralSettingsExport(options)
	local exportData = {}
	for key, value in pairs(options) do
		if not PROFILE_OPTION_SECTION_KEYS[key] then
			exportData[key] = CopyValue(value)
		end
	end

	return exportData
end

local function BuildResourceBarSettingsExport(options)
	local exportData = {}
	if options.resourceBars ~= nil then
		exportData.resourceBars = CopyValue(options.resourceBars)
	end

	if options.resourceBar ~= nil then
		exportData.resourceBar = CopyValue(options.resourceBar)
	end

	return exportData
end

local function BuildCastBarSettingsExport(options)
	return options.castBar and CopyValue(options.castBar) or {}
end

local function ApplyOptionsData(options, data)
	if type(data) ~= "table" then
		return
	end

	for key, value in pairs(data) do
		options[key] = CopyValue(value)
	end
end

local function ApplyResourceBarSettings(options, data)
	if type(data) ~= "table" then
		return
	end

	if data.resourceBar ~= nil then
		options.resourceBar = CopyValue(data.resourceBar)
	end
end

local function ApplyCastBarSettings(options, data)
	if type(data) ~= "table" then
		return
	end

	options.castBar = CopyValue(data)
end

local function MergeConfig(destDB, sourceData, defaultAnchor)
	if not destDB or not sourceData then
		return
	end

	destDB.spellConfig = sourceData.spellConfig
	destDB.itemConfig = sourceData.itemConfig
	destDB.customConfig = sourceData.customConfig or {}

	local anchors = sourceData.anchorConfig
	if not anchors or #anchors == 0 then
		destDB.anchorConfig = defaultAnchor
	else
		destDB.anchorConfig = anchors
	end
end

local function GetProfileExportData(db, exportType, classFileName, specID)
	if not classFileName and not specID then
		return {}
	end

	if exportType == EXPORT_TYPE_ALL then
		local profileData = {}
		for key, value in pairs(db) do
			if key ~= "options" then
				profileData[key] = CopyValue(value)
			end
		end

		return profileData
	end

	local classData = db[classFileName]
	if type(classData) ~= "table" then
		return {}
	end

	if specID then
		return type(classData[specID]) == "table" and CopyValue(classData[specID]) or {}
	end

	return CopyValue(classData)
end

local function BuildProfileExportPayload(self, exportType, classFileName, specID, exportOptions)
	exportOptions = exportOptions or {}

	local payload = {
		profileData = GetProfileExportData(self.db.profile, exportType, classFileName, specID),
	}
	local options = self.db.profile.options

	if exportOptions.includeResourceBar then
		payload.resourceBarSettings = BuildResourceBarSettingsExport(options)
	end

	if exportOptions.includeCastBar then
		payload.castBarSettings = BuildCastBarSettingsExport(options)
	end

	if exportOptions.includeGlobalSettings then
		payload.globalSettings = BuildGeneralSettingsExport(options)
	end

	return payload
end

local function GetExportString(self, classFileName, specID, exportOptions)
	local exportType = specID or EXPORT_TYPE_ALL
	if classFileName == "ALL" then
		exportType = EXPORT_TYPE_ALL
	elseif classFileName and not specID then
		exportType = EXPORT_TYPE_CLASS
	end

	local prefix = string.format("!SCM:%d:%d!", dataVersion, exportType)
	return prefix .. SCM.Encode(BuildProfileExportPayload(self, exportType, classFileName, specID, exportOptions))
end

function SCM:ExportProfile(widget, classFileName, specID, exportOptions)
	return GetExportString(self, classFileName, specID, exportOptions)
end

function SCM:ExportGlobalSettings()
	local exportType = EXPORT_TYPE_GLOBAL_SETTINGS
	local prefix = string.format("!SCM:%d:%d!", dataVersion, exportType)
	return prefix .. SCM.Encode(BuildGeneralSettingsExport(self.db.profile.options))
end

function SCM:ExportGlobalAnchors()
	local prefix = string.format("!SCM:%d:%d!", dataVersion, EXPORT_TYPE_GLOBAL_ANCHORS)
	return prefix .. SCM.Encode({
		globalAnchorConfig = self.db.global.globalAnchorConfig,
		globalCustomConfig = self.db.global.globalCustomConfig,
	})
end

function SCM:ExportEverything()
	local prefix = string.format("!SCM:%d:%d!", dataVersion, EXPORT_TYPE_EVERYTHING)
	local options = self.db.profile.options
	return prefix .. SCM.Encode({
		profileData = GetProfileExportData(self.db.profile, EXPORT_TYPE_ALL),
		resourceBarSettings = BuildResourceBarSettingsExport(options),
		castBarSettings = BuildCastBarSettingsExport(options),
		globalSettings = BuildGeneralSettingsExport(options),
	})
end

local function DecodeImportString(importString)
	local parameterString, dataString = importString:match("^!([^!]+)!(.+)$")
	if not parameterString or not dataString then
		return
	end

	local prefix, version, typeStr = strsplit(":", parameterString)
	local typeID = tonumber(typeStr)
	local versionID = tonumber(version)

	if prefix ~= "SCM" or versionID ~= dataVersion then
		print("Invalid Import String")
		return
	end

	local data = SCM.Decode(dataString)
	if not data then
		return
	end

	return typeID, data
end

local function GetImportedProfilePayload(typeID, data)
	if type(data) ~= "table" then
		return data, nil
	end

	if data.profileData or data.resourceBarSettings or data.castBarSettings or data.globalSettings then
		local profileData = type(data.profileData) == "table" and data.profileData or {}
		return profileData, data
	end

	if typeID == EXPORT_TYPE_EVERYTHING then
		local profileData = type(data.profileData) == "table" and data.profileData or {}
		return profileData, data
	end

	return data, nil
end

local function NormalizeAnchorEntry(anchorConfig)
	if type(anchorConfig) ~= "table" then
		anchorConfig = {}
	end

	if type(anchorConfig.anchor) ~= "table" then
		anchorConfig.anchor = { "CENTER", "UIParent", "CENTER", 0, 0 }
	end

	if type(anchorConfig.rowConfig) ~= "table" or #anchorConfig.rowConfig == 0 then
		anchorConfig.rowConfig = {
			{
				size = 40,
				limit = 8,
			},
		}
	end

	return anchorConfig
end

local function NormalizeImportedGlobalAnchorData(data)
	local anchors = type(data) == "table" and data.globalAnchorConfig or nil
	if type(anchors) ~= "table" or #anchors == 0 then
		anchors = CopyTable(SCM.DefaultDB.global.globalAnchorConfig)
	else
		anchors = CopyTable(anchors)
	end

	for index, anchorConfig in ipairs(anchors) do
		anchors[index] = NormalizeAnchorEntry(anchorConfig)
	end

	local customConfig = type(data) == "table" and data.globalCustomConfig or nil
	if type(customConfig) ~= "table" then
		customConfig = CopyTable(SCM.DefaultDB.global.globalCustomConfig)
	else
		customConfig = CopyTable(customConfig)
	end

	local allowedKeys = SCM.DefaultDB.global.globalCustomConfig
	for key in pairs(customConfig) do
		if not allowedKeys[key] then
			customConfig[key] = nil
		end
	end

	for _, key in ipairs(GLOBAL_CUSTOM_CONFIG_KEYS) do
		customConfig[key] = type(customConfig[key]) == "table" and customConfig[key] or {}
		local iconType = key:gsub("Config$", "")

		for id, config in pairs(customConfig[key]) do
			if type(config) ~= "table" or type(config.anchorGroup) ~= "number" or config.anchorGroup < 1 or config.anchorGroup > #anchors then
				customConfig[key][id] = nil
			else
				config.id = config.id or id
				config.iconType = config.iconType or iconType
			end
		end
	end

	return anchors, customConfig
end

local function RefreshImportedGlobalAnchors(self, previousAnchorCount)
	local currentAnchorCount = #self.db.global.globalAnchorConfig
	for index = currentAnchorCount + 1, previousAnchorCount do
		local globalGroup = self.Utils.ToGlobalGroup(index)
		local anchorFrame = SCM:GetAnchor(globalGroup)
		if anchorFrame then
			anchorFrame:Hide()
			self.anchorFrames[globalGroup] = nil
		end
	end

	SCM.RefreshCooldownViewerData(true)
end

function SCM:GetFreeProfileName(profileName)
	if not profileName or strtrim(profileName) == "" then
		profileName = "New Profile"
	end

	local existingProfiles = {}
	for _, name in ipairs(self.db:GetProfiles()) do
		existingProfiles[name] = true
	end

	if not existingProfiles[profileName] then
		return profileName
	end

	local index = 1
	local baseName = profileName
	while existingProfiles[baseName .. " " .. index] do
		index = index + 1
	end

	return "New Profile " .. index
end

function SCM:ImportProfile(profileName, importString)
	local typeID, data = DecodeImportString(importString)
	if not typeID then
		return
	end

	if typeID == EXPORT_TYPE_GLOBAL_SETTINGS then
		self:ImportGlobalSettingsFromData(data)
		return
	end

	if typeID == EXPORT_TYPE_GLOBAL_ANCHORS then
		self:ImportGlobalAnchorsFromData(data)
		return
	end

	local importedSections
	data, importedSections = GetImportedProfilePayload(typeID, data)

	if typeID == EXPORT_TYPE_EVERYTHING then
		typeID = EXPORT_TYPE_ALL
	end

	if not profileName or profileName == "" then
		profileName = SCM.db:GetCurrentProfile()
	end

	SCM.db:SetProfile(profileName)

	local db = self.db.profile
	local defaultAnchor = self.DB.defaultAnchorConfig

	if typeID == EXPORT_TYPE_ALL then -- All classes
		for classFileName, classConfig in pairs(data) do
			db[classFileName] = db[classFileName] or {}
			for specID, specConfig in pairs(classConfig) do
				db[classFileName][specID] = db[classFileName][specID] or CopyTable(SCM.DefaultClassConfig)
				MergeConfig(db[classFileName][specID], specConfig, defaultAnchor)
			end
		end
	elseif typeID == EXPORT_TYPE_CLASS then -- Single class
		for specID, specConfig in pairs(data) do
			local classFileName = select(6, GetSpecializationInfoByID(specID))

			if classFileName then
				db[classFileName] = db[classFileName] or {}
				db[classFileName][specID] = db[classFileName][specID] or CopyTable(SCM.DefaultClassConfig)

				MergeConfig(db[classFileName][specID], specConfig, defaultAnchor)
			end
		end
	elseif typeID then -- Single Spec
		local classFileName = select(6, GetSpecializationInfoByID(typeID))

		if classFileName then
			db[classFileName] = db[classFileName] or {}
			db[classFileName][typeID] = db[classFileName][typeID] or CopyTable(SCM.DefaultClassConfig)
			MergeConfig(db[classFileName][typeID], data, defaultAnchor)
		end
	end

	local options = self.db.profile.options
	if importedSections then
		ApplyResourceBarSettings(options, importedSections.resourceBarSettings)
		ApplyCastBarSettings(options, importedSections.castBarSettings)
		ApplyOptionsData(options, importedSections.globalSettings)
	end

	self.db.profile.options = options

	SCM.RefreshCooldownViewerData(true)
end

function SCM:ImportGlobalSettings(importString)
	self:ImportProfile(nil, importString)
end

function SCM:ImportGlobalAnchors(importString)
	self:ImportProfile(nil, importString)
end

function SCM:ImportGlobalAnchorsFromData(data)
	local previousAnchorCount = #(self.db.global.globalAnchorConfig or {})
	local anchors, customConfig = NormalizeImportedGlobalAnchorData(data)

	self.db.global.globalAnchorConfig = anchors
	self.db.global.globalCustomConfig = customConfig

	RefreshImportedGlobalAnchors(self, previousAnchorCount)
end

function SCM:ImportGlobalSettingsFromData(data)
	local options = self.db.profile.options
	ApplyOptionsData(options, data)
	self.db.profile.options = options

	SCM.RefreshCooldownViewerData(true)
end
