local SCM = select(2, ...)

local Utils = SCM.Utils

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

local function CreateAnchorConfigTables(customConfig)
	customConfig = customConfig or {}

	if not customConfig[1] then
		customConfig[1] = {
			anchor = { "CENTER", "UIParent", "CENTER", 0, 0 },
			rowConfig = {
				[1] = {
					iconWidth = 150,
					iconHeight = 40,
					limit = 8,
				},
			},
		}
	end

	return customConfig
end

local function NormalizeTrackedBarSpellConfig(spellConfig)
	if type(spellConfig) ~= "table" then
		return
	end

	for _, config in pairs(spellConfig) do
		if type(config) == "table" and type(config.source) == "table" and type(config.anchorGroup) == "table" then
			local trackedBarGroup = config.source[Enum.CooldownViewerCategory.TrackedBar]
			local normalizedTrackedBarGroup = Utils.NormalizeBuffBarGroup(trackedBarGroup)
			local legacyGroup = normalizedTrackedBarGroup and (normalizedTrackedBarGroup - 200)
			local groupConfig = (trackedBarGroup and config.anchorGroup[trackedBarGroup])
				or (legacyGroup and config.anchorGroup[legacyGroup])

			if trackedBarGroup ~= normalizedTrackedBarGroup then
				config.source[Enum.CooldownViewerCategory.TrackedBar] = normalizedTrackedBarGroup
			end

			if normalizedTrackedBarGroup and groupConfig then
				config.anchorGroup[normalizedTrackedBarGroup] = groupConfig
			end

			if trackedBarGroup and trackedBarGroup ~= normalizedTrackedBarGroup then
				config.anchorGroup[trackedBarGroup] = nil
			end

			if legacyGroup and legacyGroup ~= normalizedTrackedBarGroup then
				config.anchorGroup[legacyGroup] = nil
			end
		end
	end
end

function SCM:UpdateDB()
	local firstGlobalGroup = SCM.Utils.ToGlobalGroup(1)
	local firstBuffBarGroup = SCM.Utils.ToBuffBarGroup(1)
	local class = UnitClassBase("player")
	local specID, _, _, _, role = GetSpecializationInfo(GetSpecialization())

	local currentConfig = self.DB:LoadData()
	local specAnchorConfig = currentConfig and currentConfig.anchorConfig[specID]
	local specBuffBarsAnchorConfig = currentConfig and currentConfig.buffBarsAnchorConfig and currentConfig.buffBarsAnchorConfig[specID]
	local specSpellConfig = currentConfig and currentConfig.spellConfig[specID]
	local specCustomConfig = currentConfig and currentConfig.customConfig and currentConfig.customConfig[specID]

	self.db.profile[class] = self.db.profile[class] or {}
	self.db.profile[class][specID] = self.db.profile[class][specID]
		or {
			anchorConfig = CopyTable(specAnchorConfig or self.DB.defaultAnchorConfig),
			buffBarsAnchorConfig = CopyTable(specBuffBarsAnchorConfig or {}),
			spellConfig = specSpellConfig or {},
			customConfig = specCustomConfig or {},
		}

	self.currentConfig = self.db.profile[class][specID]
	self.anchorConfig = self.currentConfig.anchorConfig
	self.spellConfig = self.currentConfig.spellConfig
	self:MigrateLegacySpellConfigKeys(self.spellConfig, self.defaultCooldownViewerConfig)
	NormalizeTrackedBarSpellConfig(self.spellConfig)
	self.itemConfig = self.currentConfig.itemConfig

	self.currentConfig.customConfig = self.currentConfig.customConfig or {}
	self.customConfig = CreateCustomConfigTables(self.currentConfig.customConfig)

	self.currentConfig.buffBarsAnchorConfig = self.currentConfig.buffBarsAnchorConfig or {}
	self.buffBarsAnchorConfig = CreateAnchorConfigTables(self.currentConfig.buffBarsAnchorConfig)

	self.globalAnchorConfig = self.db.global.globalAnchorConfig
	self.globalCustomConfig = CreateCustomConfigTables(self.db.global.globalCustomConfig)
	self:RemoveOldAnchorConfigs(self.currentConfig, self.globalAnchorConfig, self.globalCustomConfig)

	self.isHideWhenInactiveEnabled = self:GetHideWhenInactive() == 1
	self.currentClass = class
	self.currentSpecID = specID
	self.currentRole = role

	for group, anchorFrame in pairs(self.anchorFrames) do
		if group < firstGlobalGroup and not self.anchorConfig[group] then
			anchorFrame:Hide()
		elseif Utils.IsGlobalGroup(group) and not self.globalAnchorConfig[group - 100] then
			anchorFrame:Hide()
		elseif group >= firstBuffBarGroup and not self.buffBarsAnchorConfig[group - 200] then
			anchorFrame:Hide()
		end
	end
end

function SCM:GetSpellConfigForGroup(configID, group)
	return GetSpellAnchorGroupConfig(self.spellConfig and self.spellConfig[configID], group)
end
