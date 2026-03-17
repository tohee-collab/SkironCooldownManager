local SCM = select(2, ...)

local function GetSpellAnchorGroupConfig(spellConfig, group)
	return spellConfig and spellConfig.anchorGroup and spellConfig.anchorGroup[group]
end

local function CreateCustomConfigTables(customConfig)
	customConfig = customConfig or {}
	customConfig.spellConfig = GetOrCreateTableEntry(customConfig, "spellConfig")
	customConfig.itemConfig = GetOrCreateTableEntry(customConfig, "itemConfig")
	customConfig.slotConfig = GetOrCreateTableEntry(customConfig, "slotConfig")
	customConfig.timerConfig = GetOrCreateTableEntry(customConfig, "timerConfig")

	local allowedKeys = SCM.DefaultDB.global.globalCustomConfig
	for key in pairs(customConfig) do
		if not allowedKeys[key] then
			customConfig[key] = nil
		end
	end

	return customConfig
end

function SCM:UpdateDB()
	local class = UnitClassBase("player")
	local specID, _, _, _, role = GetSpecializationInfo(GetSpecialization())

	local currentConfig = self.DB:LoadData()
	local specAnchorConfig = currentConfig and currentConfig.anchorConfig[specID]
	local specSpellConfig = currentConfig and currentConfig.spellConfig[specID]
	local specCustomConfig = currentConfig and currentConfig.customConfig and currentConfig.customConfig[specID]

	self.db.profile[class] = self.db.profile[class] or {}
	self.db.profile[class][specID] = self.db.profile[class][specID]
		or {
			anchorConfig = CopyTable(specAnchorConfig or self.DB.defaultAnchorConfig),
			spellConfig = specSpellConfig or {},
			customConfig = specCustomConfig or {},
		}

	self.currentConfig = self.db.profile[class][specID]
	self.anchorConfig = self.currentConfig.anchorConfig
	self.spellConfig = self.currentConfig.spellConfig
	self:MigrateLegacySpellConfigKeys(self.spellConfig, self.defaultCooldownViewerConfig)
	self.itemConfig = self.currentConfig.itemConfig

	self.currentConfig.customConfig = self.currentConfig.customConfig or {}
	self.customConfig = CreateCustomConfigTables(self.currentConfig.customConfig)

	self.globalAnchorConfig = self.db.global.globalAnchorConfig
	self.globalCustomConfig = CreateCustomConfigTables(self.db.global.globalCustomConfig)

	self.isHideWhenInactiveEnabled = self:GetHideWhenInactive() == 1
	self.currentClass = class
	self.currentSpecID = specID
	self.currentRole = role
end

function SCM:GetSpellConfigForGroup(configID, group)
	return GetSpellAnchorGroupConfig(self.spellConfig and self.spellConfig[configID], group)
end
