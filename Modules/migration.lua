local SCM = select(2, ...)

local Utils = SCM.Utils
local GetCooldownConfigKey = Utils.GetCooldownConfigKey
local ToBuffBarGroup = Utils.ToBuffBarGroup
local IsBuffBarGroup = Utils.IsBuffBarGroup

local function HasAnchorConfig(anchorGroup, anchorConfig, buffBarsAnchorConfig)
	anchorGroup = tonumber(anchorGroup)
	if not anchorGroup then
		return
	end

	if IsBuffBarGroup(anchorGroup) then
		return buffBarsAnchorConfig and buffBarsAnchorConfig[anchorGroup - ToBuffBarGroup(0)]
	end

	return anchorConfig and anchorConfig[anchorGroup]
end

local function RemoveOldSpellConfigAnchors(config, anchorConfig, buffBarsAnchorConfig)
	local source = type(config) == "table" and config.source
	local anchorGroups = type(config) == "table" and config.anchorGroup
	if type(anchorGroups) ~= "table" then
		return
	end

	if type(source) == "table" then
		for sourceIndex, anchorGroup in pairs(source) do
			if not HasAnchorConfig(anchorGroup, anchorConfig, buffBarsAnchorConfig) then
				source[sourceIndex] = nil
			end
		end
	end

	for anchorGroup in pairs(anchorGroups) do
		if not HasAnchorConfig(anchorGroup, anchorConfig, buffBarsAnchorConfig) then
			anchorGroups[anchorGroup] = nil
		end
	end

	return next(anchorGroups)
end

local function HasCustomAnchorConfig(config, anchorConfig)
	local anchorGroup = type(config) == "table" and config.anchorGroup
	return type(anchorGroup) == "number" and HasAnchorConfig(anchorGroup, anchorConfig)
end

local function RemoveOldSpellConfigAnchorsFromTable(spellConfig, anchorConfig, buffBarsAnchorConfig)
	if type(spellConfig) ~= "table" then
		return
	end

	for configID, config in pairs(spellConfig) do
		if not RemoveOldSpellConfigAnchors(config, anchorConfig, buffBarsAnchorConfig) then
			spellConfig[configID] = nil
		end
	end
end

local function RemoveOldCustomConfigAnchors(customConfig, anchorConfig)
	if type(customConfig) ~= "table" then
		return
	end

	for _, configKey in ipairs({ "spellConfig", "itemConfig", "slotConfig", "timerConfig" }) do
		local configTable = customConfig[configKey]
		if type(configTable) == "table" then
			for id, config in pairs(configTable) do
				if not HasCustomAnchorConfig(config, anchorConfig) then
					configTable[id] = nil
				end
			end
		end
	end
end

function SCM:RemoveOldAnchorConfigs(currentConfig, globalAnchorConfig, globalCustomConfig)
	if type(currentConfig) == "table" then
		RemoveOldSpellConfigAnchorsFromTable(currentConfig.spellConfig, currentConfig.anchorConfig, currentConfig.buffBarsAnchorConfig)
		RemoveOldCustomConfigAnchors(currentConfig.customConfig, currentConfig.anchorConfig)
	end

	RemoveOldCustomConfigAnchors(globalCustomConfig, globalAnchorConfig)
end

local function GetCooldownDataForLegacySpellConfig(defaultCooldownViewerConfig, configID, config)
	local spellID = config.spellID or (type(configID) == "number" and configID)
	if not spellID or not defaultCooldownViewerConfig then
		return
	end

	for sourceIndex in pairs(config.source) do
		local categoryConfig = defaultCooldownViewerConfig[sourceIndex]
		local pairIndex = SCM.Constants.SourcePairs[sourceIndex]
		local pairConfig = pairIndex and defaultCooldownViewerConfig[pairIndex]
		local data = categoryConfig and categoryConfig.spellIDs[spellID]
		if not data and pairConfig then
			data = pairConfig.spellIDs[spellID]
		end
		if data and data.cooldownID then
			return data
		end
	end

	return defaultCooldownViewerConfig.spellIDs and defaultCooldownViewerConfig.spellIDs[spellID]
end

function SCM:MigrateLegacySpellConfigKeys(spellConfig, defaultCooldownViewerConfig)
	local legacyKeys = {}
	for configID in pairs(spellConfig) do
		if type(configID) == "number" then
			legacyKeys[#legacyKeys + 1] = configID
		end
	end

	for _, legacyID in ipairs(legacyKeys) do
		local config = spellConfig[legacyID]
		local spellID = config.spellID or legacyID
		local cooldownData = GetCooldownDataForLegacySpellConfig(defaultCooldownViewerConfig, legacyID, config)
		local cooldownID = config.cooldownID or (cooldownData and cooldownData.cooldownID)
		if cooldownID then
			local migratedID = GetCooldownConfigKey(cooldownID)
			config.spellID = spellID
			config.cooldownID = cooldownID
			if migratedID then
				spellConfig[migratedID] = config
				spellConfig[legacyID] = nil
			end
		else
			spellConfig[legacyID] = nil
		end
	end
end

function SCM:MigrateLegacyProfileOptions()
	local legacyOptions = self.db.global.options
	if type(legacyOptions) ~= "table" then
		return
	end

	for _, profile in pairs(self.db.profiles) do
		if type(profile) == "table" and type(profile.options) ~= "table" then
			profile.options = CopyTable(legacyOptions)
		end
	end
end