local SCM = select(2, ...)

local dataVersion = 1
local pairs, tonumber, select = pairs, tonumber, select
local GetSpecializationInfoByID = GetSpecializationInfoByID
local EXPORT_TYPE_ALL = 0
local EXPORT_TYPE_CLASS = 1
local EXPORT_TYPE_GLOBAL_SETTINGS = 2
local EXPORT_TYPE_GLOBAL_ANCHORS = 3
local GLOBAL_CUSTOM_CONFIG_KEYS = {
	"spellConfig",
	"itemConfig",
	"slotConfig",
	"timerConfig",
}

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

local function GetExportString(classFileName, specID)
	local exportType = specID
	if classFileName == "ALL" or (not classFileName and not specID) then
		exportType = EXPORT_TYPE_ALL
	elseif classFileName and not specID then
		exportType = EXPORT_TYPE_CLASS
	end

	local prefix = string.format("!SCM:%d:%d!", dataVersion, exportType)
	local db = SCM.db.profile

	if exportType == 0 then
		return prefix .. SCM.Encode(db)
	end

	local classData = db[classFileName]
	if not classData then
		return
	end

	if specID then
		if classData[specID] then
			return prefix .. SCM.Encode(classData[specID])
		end
	else
		return prefix .. SCM.Encode(classData)
	end
end

function SCM:ExportProfile(widget, classFileName, specID)
	return GetExportString(classFileName, specID)
end

function SCM:ExportGlobalSettings()
	local exportType = EXPORT_TYPE_GLOBAL_SETTINGS
	local prefix = string.format("!SCM:%d:%d!", dataVersion, exportType)
	return prefix .. SCM.Encode(self.db.global.options)
end

function SCM:ExportGlobalAnchors()
	local prefix = string.format("!SCM:%d:%d!", dataVersion, EXPORT_TYPE_GLOBAL_ANCHORS)
	return prefix .. SCM.Encode({
		globalAnchorConfig = self.db.global.globalAnchorConfig,
		globalCustomConfig = self.db.global.globalCustomConfig,
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
		local anchorFrame = self.anchorFrames[globalGroup]
		if anchorFrame then
			anchorFrame:Hide()
			self.anchorFrames[globalGroup] = nil
		end
	end

	self.CustomIcons.ReleaseAllIcons()
	self:UpdateDB()
	self:CreateAllCustomIcons()
	self:ApplyAllCDManagerConfigs()
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

	if not profileName or profileName == "" then
		profileName = SCM.db:GetCurrentProfile()
	end

	if typeID == EXPORT_TYPE_GLOBAL_SETTINGS then
		SCM:ImportGlobalSettingsFromData(data)
		return
	end

	if typeID == EXPORT_TYPE_GLOBAL_ANCHORS then
		SCM:ImportGlobalAnchorsFromData(data)
		return
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

	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:ImportGlobalSettings(importString)
	local typeID, data = DecodeImportString(importString)
	if not typeID then
		return
	end

	if typeID ~= EXPORT_TYPE_GLOBAL_SETTINGS then
		self:ImportProfile(nil, importString)
		return
	end

	local options = self.db.global.options
	for key in pairs(self.db.global.options) do
		if data[key] ~= nil then
			if type(options[key]) == "table" then
				self.db.global.options[key] = data[key]
			end
		end
	end

	SCM:ApplyAllCDManagerConfigs()
end

function SCM:ImportGlobalAnchors(importString)
	local typeID, data = DecodeImportString(importString)
	if not typeID then
		return
	end

	if typeID ~= EXPORT_TYPE_GLOBAL_ANCHORS then
		self:ImportProfile(nil, importString)
		return
	end

	self:ImportGlobalAnchorsFromData(data)
end

function SCM:ImportGlobalAnchorsFromData(data)
	local previousAnchorCount = #(self.db.global.globalAnchorConfig or {})
	local anchors, customConfig = NormalizeImportedGlobalAnchorData(data)

	self.db.global.globalAnchorConfig = anchors
	self.db.global.globalCustomConfig = customConfig

	RefreshImportedGlobalAnchors(self, previousAnchorCount)
end

function SCM:ImportGlobalSettingsFromData(data)
	for key in pairs(self.db.global.options) do
		if data[key] ~= nil then
			self.db.global.options[key] = data[key]
		end
	end

	SCM:ApplyAllCDManagerConfigs()
end
