local addonName, SCM = ...

local function GetSpecConfigValue(configTable, specID)
	if type(configTable) ~= "table" then
		return
	end

	-- Support both layouts:
	-- 1) itemConfig[specID] = { [slotID] = config }
	-- 2) itemConfig = { [slotID] = config } (shared for all specs)
	return configTable[specID] or configTable
end

function SCM.DB:LoadData()
	SCM.DB.currentConfig = self:GetClassConfig(SCM.Utils.GetClass())
	SCM.DB.configLoaded = SCM.DB.currentConfig ~= nil

	return SCM.DB.currentConfig
end

function SCM.DB:ResetData()
	self.classes = {}
end
function SCM.DB:GetClassConfig(classFileName)
	return self.classes[classFileName]
end

function SCM.DB:RegisterClassConfig(classFileName, config)
	self.classes[classFileName] = self.classes[classFileName] or {
		anchorConfig = {},
		spellConfig = {},
		itemConfig = {},
		customConfig = {},
	}

	for specID, anchorConfig in pairs(config.anchorConfig) do
		if #anchorConfig == 0 then
			self.classes[classFileName].anchorConfig[specID] = CopyTable(self.defaultAnchorConfig)
		else
			self.classes[classFileName].anchorConfig[specID] = anchorConfig
		end
	end

	for specID, spellConfig in pairs(config.spellConfig) do
		self.classes[classFileName].spellConfig[specID] = spellConfig

		if config.itemConfig then
			self.classes[classFileName].itemConfig[specID] = GetSpecConfigValue(config.itemConfig, specID)
		end
		if config.customConfig then
			self.classes[classFileName].customConfig[specID] = config.customConfig[specID] or config.customConfig
		end
	end
end

function SCM.DB:RegisterClassSpecConfig(classFileName, config, specID)
	self.classes[classFileName] = self.classes[classFileName] or {
		anchorConfig = {},
		spellConfig = {},
		itemConfig = {},
		customConfig = {},
	}

	if config.anchorConfig[specID] then
		if #config.anchorConfig[specID] == 0 then
			self.classes[classFileName].anchorConfig[specID] = CopyTable(self.defaultAnchorConfig)
		else
			self.classes[classFileName].anchorConfig[specID] = config.anchorConfig[specID]
		end
	end
	self.classes[classFileName].spellConfig[specID] = config.spellConfig[specID]

	if config.itemConfig then
		self.classes[classFileName].itemConfig[specID] = GetSpecConfigValue(config.itemConfig, specID)
	end
	if config.customConfig then
		self.classes[classFileName].customConfig[specID] = config.customConfig[specID] or config.customConfig
	end
end

function SCM.DB:RegisterAndLoadConfig(profileName, classFileName, config, specID)
	SCM.db:SetProfile(profileName)

	if specID then
		SCM.DB:RegisterClassSpecConfig(classFileName, config, specID)
	else
		SCM.DB:RegisterClassConfig(classFileName, config)
	end

	if classFileName == SCM.Utils.GetClass() then
		SCM.db.profile[classFileName] = SCM.db.profile[classFileName] or {}

		for specID, spellConfig in pairs(config.spellConfig) do
			if next(spellConfig) then
				SCM.db.profile[classFileName][specID] = nil
			end
		end

		SCM:LoadNewProfile(true)
	end
end
