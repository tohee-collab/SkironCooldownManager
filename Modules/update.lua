local SCM = select(2, ...)

local CDM = SCM.CDM
local UPDATE_SCOPE = CDM.UPDATE_SCOPE
local OrderCDManagerSpells = CDM.OrderSpells
local OrderCDManagerSpells_Actual = CDM.OrderSpellsActual
local ToGlobalGroup = SCM.Utils.ToGlobalGroup

function SCM:ApplyEssentialCDManagerConfig()
	if C_CVar.GetCVar("cooldownViewerEnabled") == "1" and SCM.currentConfig then
		OrderCDManagerSpells(UPDATE_SCOPE.ESSENTIAL)
	end
end

function SCM:ApplyUtilityCDManagerConfig()
	if SCM.currentConfig then
		OrderCDManagerSpells(UPDATE_SCOPE.UTILITY)
	end
end

function SCM:ApplyBuffIconCDManagerConfig()
	if SCM.currentConfig then
		OrderCDManagerSpells(UPDATE_SCOPE.BUFF)
	end
end

function SCM:ApplyAllCDManagerConfigs()
	if C_CVar.GetCVar("cooldownViewerEnabled") == "1" and SCM.currentConfig then
		OrderCDManagerSpells(UPDATE_SCOPE.ALL)
	end
end

function SCM:ApplyAnchorGroupCDManagerConfig(group, isGlobal)
	if C_CVar.GetCVar("cooldownViewerEnabled") ~= "1" or not SCM.currentConfig then
		return
	end

	local scopedGroup = tonumber(group)
	if not scopedGroup then
		return
	end

	if isGlobal then
		scopedGroup = ToGlobalGroup(scopedGroup)
	end

	local scopedGroups = self:AcquireScopedGroupCache()
	scopedGroups[scopedGroup] = true
	OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, scopedGroups)
	self:ReleaseScopedGroupCache(scopedGroups)
end

local function GetScopeGroupsForConfig(customConfig, scopedGroups, isGlobal, predicate)
	if not customConfig then
		return scopedGroups
	end

	for _, config in pairs(customConfig) do
		if not predicate or predicate(config) then
			local group = isGlobal and ToGlobalGroup(config.anchorGroup) or config.anchorGroup
			scopedGroups[group] = true
		end
	end

	return scopedGroups
end

local function ApplyScopedGroups(scopedGroups)
	if next(scopedGroups) then
		OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, scopedGroups)
	end
end

function SCM:ApplyAnchorGroupCustomConfig(customConfig)
	if not customConfig then
		return
	end

	local scopedGroups = self:AcquireScopedGroupCache()
	GetScopeGroupsForConfig(customConfig, scopedGroups)
	ApplyScopedGroups(scopedGroups)
	self:ReleaseScopedGroupCache(scopedGroups)
end

function SCM:ApplyAnchorGroupByIconType(iconType, skipGlobal)
	local scopedGroups = self:AcquireScopedGroupCache()
	GetScopeGroupsForConfig(self:GetConfigTable(iconType), scopedGroups)

	if not skipGlobal then
		GetScopeGroupsForConfig(self:GetConfigTable(iconType, true), scopedGroups, true)
	end

	ApplyScopedGroups(scopedGroups)
	self:ReleaseScopedGroupCache(scopedGroups)
end

function SCM:ApplyAnchorGroupByIconTypes(skipGlobal, predicate, ...)
	local scopedGroups = self:AcquireScopedGroupCache()
	local numIconTypes = select("#", ...)
	for i = 1, numIconTypes do
		local iconType = select(i, ...)
		GetScopeGroupsForConfig(self:GetConfigTable(iconType), scopedGroups, false, predicate)
		if not skipGlobal then
			GetScopeGroupsForConfig(self:GetConfigTable(iconType, true), scopedGroups, true, predicate)
		end
	end

	ApplyScopedGroups(scopedGroups)
	self:ReleaseScopedGroupCache(scopedGroups)
end

function SCM:ApplyAnchorGroupBySpellID(spellID, iconType)
	local scopedGroups = self:AcquireScopedGroupCache()
	local configTable = self:GetConfigTable(iconType)
	if configTable then
		for _, config in pairs(configTable) do
			if config.spellID == spellID then
				scopedGroups[config.anchorGroup] = true
			end
		end
	end

	local globalConfigTable = self:GetConfigTable(iconType, true)
	if globalConfigTable then
		for _, config in pairs(globalConfigTable) do
			if config.spellID == spellID then
				scopedGroups[ToGlobalGroup(config.anchorGroup)] = true
			end
		end
	end

	ApplyScopedGroups(scopedGroups)
	self:ReleaseScopedGroupCache(scopedGroups)
end

local function ApplySuccessfulCastToConfigTable(configTable, spellID, scopedGroups, isGlobal, now)
	if not configTable then
		return scopedGroups
	end

	for id, config in pairs(configTable) do
		local duration = config.duration
		if config.spellID == spellID and duration and duration > 0 then
			local group = isGlobal and ToGlobalGroup(config.anchorGroup) or config.anchorGroup
			scopedGroups[group] = true

			local customFrames = SCM.CustomIcons.GetCustomIconFrames(config)
			if customFrames and customFrames[id] then
				customFrames[id].lastCastStartTime = now
			end
		end
	end

	return scopedGroups
end

function SCM:ApplySuccessfulCastBySpellID(spellID)
	local now = GetTime()
	local scopedGroups = self:AcquireScopedGroupCache()

	scopedGroups = ApplySuccessfulCastToConfigTable(self:GetConfigTable("timer"), spellID, scopedGroups, false, now)
	scopedGroups = ApplySuccessfulCastToConfigTable(self:GetConfigTable("timer", true), spellID, scopedGroups, true, now)
	scopedGroups = ApplySuccessfulCastToConfigTable(self:GetConfigTable("spell"), spellID, scopedGroups, false, now)
	scopedGroups = ApplySuccessfulCastToConfigTable(self:GetConfigTable("spell", true), spellID, scopedGroups, true, now)

	ApplyScopedGroups(scopedGroups)
	self:ReleaseScopedGroupCache(scopedGroups)
end
