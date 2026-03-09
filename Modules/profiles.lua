local SCM = select(2, ...)

local dataVersion = 1
local pairs, tonumber, select = pairs, tonumber, select
local GetSpecializationInfoByID = GetSpecializationInfoByID

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
		exportType = 0
	elseif classFileName and not specID then
		exportType = 1
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
	local exportType = 2
	local prefix = string.format("!SCM:%d:%d!", dataVersion, exportType)
	return prefix .. SCM.Encode(self.db.global.options)
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

	if not profileName or profileName == "" then
		profileName = SCM.db:GetCurrentProfile()
	end

	local data = SCM.Decode(dataString)
	if not data then
		return
	end

	if typeID ~= 2 then
		SCM.db:SetProfile(profileName)
	end
	
	local db = self.db.profile
	local defaultAnchor = self.DB.defaultAnchorConfig

	if typeID == 0 then -- All classes
		for classFileName, classConfig in pairs(data) do
			db[classFileName] = db[classFileName] or {}
			for specID, specConfig in pairs(classConfig) do
				db[classFileName][specID] = db[classFileName][specID] or CopyTable(SCM.DefaultClassConfig)
				MergeConfig(db[classFileName][specID], specConfig, defaultAnchor)
			end
		end
	elseif typeID == 1 then -- Single class
		for specID, specConfig in pairs(data) do
			local classFileName = select(6, GetSpecializationInfoByID(specID))

			if classFileName then
				db[classFileName] = db[classFileName] or {}
				db[classFileName][specID] = db[classFileName][specID] or CopyTable(SCM.DefaultClassConfig)

				MergeConfig(db[classFileName][specID], specConfig, defaultAnchor)
			end
		end
	elseif typeID == 2 then -- global settings
		SCM:ImportGlobalSettingsFromData(data)
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
	local parameterString, dataString = importString:match("^!([^!]+)!(.+)$")
	if not parameterString or not dataString then
		return
	end

	local prefix, version, typeStr = strsplit(":", parameterString)
	local typeID = tonumber(typeStr)
	local versionID = tonumber(version)

	if typeID ~= 2 then
		self:ImportProfile(nil, importString)
		return
	elseif prefix ~= "SCM" or versionID ~= dataVersion then
		print("Invalid Import String")
		return
	end

	local data = SCM.Decode(dataString)
	if not data then
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

function SCM:ImportGlobalSettingsFromData(data)
	for key in pairs(self.db.global.options) do
		if data[key] ~= nil then
			self.db.global.options[key] = data[key]
		end
	end

	SCM:ApplyAllCDManagerConfigs()
end
