local SCM = select(2, ...)

local Icons = SCM.Icons
local Cache = SCM.Cache
local AddChildToGroup = SCM.Utils.AddChildToGroup
local Cooldowns = SCM.Cooldowns
local delayedHideSpellIDs = {
	--[450615] = true,
}
local delayedHideSeconds = 0.03

local function OnManagedChildSetAlpha(self)
	UIParent.SetAlpha(self, self.SCMHidden and 0 or 1)
end

local function ApplyHideChildNow(child)
	child.SCMHidden = true
	UIParent.SetAlpha(child, 0)
	child:EnableMouse(false)
	child:SetScript("OnEnter", nil)
	SCM:Debug("HIDE", GetTime(), child.SCMSpellID or "unknown", child.SCMCooldownID or "unknown")

	if not child.SCMAlphaHook then
		child.SCMAlphaHook = true
		hooksecurefunc(child, "SetAlpha", OnManagedChildSetAlpha)
	end
end

local function DelayedHideChildCallback(child)
	child.SCMHideTimer = nil
	if child.viewerFrame and not child.SCMHidden then
		ApplyHideChildNow(child)
	end
end

function Icons.HideChild(child)
	if not child.viewerFrame or child.SCMHidden then
		return
	end

	if delayedHideSpellIDs[child.SCMSpellID] then
		if child.SCMHideTimer then
			return
		end
		SCM:Debug("Start Timer", child.SCMSpellID)

		child.SCMHideTimer = C_Timer.NewTimer(delayedHideSeconds, function()
			DelayedHideChildCallback(child)
		end)
		return
	end

	ApplyHideChildNow(child)
end

local function CancelChildHideTimer(child)
	if child.SCMHideTimer then
		SCM:Debug("Cancel Timer", child.SCMSpellID)
		child.SCMHideTimer:Cancel()
		child.SCMHideTimer = nil
	end
end

function Icons.ShowChild(child)
	CancelChildHideTimer(child)

	if child.viewerFrame and child.SCMHidden then
		child.SCMHidden = false
		UIParent.SetAlpha(child, 1)
		child:EnableMouse(true)
		SCM:Debug("SHOW", GetTime(), child.SCMSpellID or "unknown", child.SCMCooldownID or "unknown")
	end
end

function Icons.SetChildVisibilityState(child, shouldShow, applyNow)
	child.SCMShouldBeVisible = shouldShow and true or false
	if not applyNow then
		return
	end

	if child.viewerFrame then
		if shouldShow then
			Icons.ShowChild(child)
		else
			Icons.HideChild(child)
		end
		return
	end

	if child.SCMCustom and not child:GetAttribute("statehidden") then
		child:SetShown(shouldShow)
	end
end

function Icons.UpdateChildDesaturation(child, shouldDesaturate)
	if child.Icon and child.SCMConfig and child.SCMSpellID then
		if child.SCMConfig.desaturate then
			child.Icon:SetDesaturated(shouldDesaturate)
		else
			child.Icon:SetDesaturated(false)
		end
	end
end

function Icons.UpdateChildGlow(child, isInactive)
	if child.SCMConfig then
		if child.SCMConfig.glowWhileActive then
			if not isInactive then
				SCM:StartCustomGlow(child)
				return
			end

			if child.SCMGlow then
				SCM:StopCustomGlow(child)
			end
		end
	end
end

local function OnManagedChildShow(child)
	UIParent.SetAlpha(child, child.SCMHidden and 0 or 1)
	if child and child.SCMGroup and child.SCMChanged then
		SCM:ApplyAnchorGroupCDManagerConfig(child.SCMGroup)
	end
end

local function OnManagedChildHide(child)
	if child and child.SCMGroup and child.SCMChanged then
		SCM:ApplyAnchorGroupCDManagerConfig(child.SCMGroup)
	end
end

function Icons.SetupIconHooks(child)
	if child.SCMShowHook or child == UIParent then
		return
	end
	child.SCMShowHook = true

	child:HookScript("OnShow", OnManagedChildShow)
	child:HookScript("OnHide", OnManagedChildHide)
end

function Icons.SetupRegularIconHooks(child)
	if child.SCMRegularCooldownHook then
		return
	end

	Icons.SetupIconHooks(child)
	Cooldowns.SetupCooldownHooks(child)
end

local function GetOrCacheChildren(viewer, isBuffIcon)
	if isBuffIcon then
		Cache.cachedViewerChildren[viewer] = nil
	end

	if not Cache.cachedViewerChildren[viewer] then
		Cache.cachedViewerChildren[viewer] = { viewer:GetChildren() }
	end

	return Cache.cachedViewerChildren[viewer]
end

function Icons.CollectScopedAnchorGroups(updateScope, config, viewerUpdateMapping)
	if updateScope == "all" then
		return
	end

	local viewerData = viewerUpdateMapping[updateScope]
	local targetGroups = viewerData and Cache.cachedScopedAnchorGroups[updateScope]
	if not targetGroups then
		return
	end

	wipe(targetGroups)

	local viewer = _G[viewerData.frameName]
	local spellConfig = config and config.spellConfig
	local defaultConfig = SCM.defaultCooldownViewerConfig
	if not (viewer and spellConfig and defaultConfig) then
		return targetGroups
	end

	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	if not categoryIndex then
		return targetGroups
	end

	local pairCategory = SCM.Constants.SourcePairs[categoryIndex]

	for _, child in ipairs(GetOrCacheChildren(viewer, viewerData.isBuffIcon)) do
		if child.GetCooldownID then
			local cooldownID = child:GetCooldownID()
			local _, childData = SCM:GetSpellConfigByCooldownID(cooldownID)
			local group = childData and (childData.source[categoryIndex] or childData.source[pairCategory])
			if group then
				targetGroups[group] = true
			end
		end
	end

	return targetGroups
end

local function ProcessBuffIcon(child, childData, options)
	Cooldowns.SetupBuffIconHooks(child, options)
	child.SCMBuffOptions = options

	local isInactive = not child.Cooldown:IsShown() and not child.auraInstanceID
	local forceShow = SCM.simulateBuffs or (not SCM.isHideWhenInactiveEnabled and childData.alwaysShow)
	local shouldHide = isInactive and not forceShow

	if shouldHide then
		Icons.SetChildVisibilityState(child, false, true)
		return
	end

	Icons.SetChildVisibilityState(child, true, true)
	Icons.UpdateChildDesaturation(child, isInactive)
end

local function ProcessRegularIcon(child, childData)
	Icons.SetupRegularIconHooks(child)
	Icons.SetChildVisibilityState(child, not (childData.hideWhenNotOnCooldown and not Cooldowns.IsChildOnCooldown(child)), false)

	Cooldowns.OverrideRegularAuraCooldown(child.Cooldown, child)
end

local function ProcessSingleChild(child, validChildren, categoryIndex, isBuffIcon, options)
	if not child.Icon then
		return
	end

	local cooldownID = child:GetCooldownID()
	local categoryConfig = categoryIndex and SCM.defaultCooldownViewerConfig[categoryIndex]
	local info = categoryConfig and (categoryConfig[cooldownID] or SCM.defaultCooldownViewerConfig.cooldownIDs[cooldownID])
	local spellID = info and (info.overrideSpellID or info.spellID)
	if info and info.linkedSpellIDs and #info.linkedSpellIDs == 1 then
		child.SCMLinkedSpellID = info.linkedSpellIDs[1]
	end

	child.SCMSpellID = spellID

	local configID, childData = SCM:GetSpellConfigByCooldownID(cooldownID)
	if not (cooldownID and spellID and childData) then
		child.SCMConfig = nil
		child.SCMOrder = nil
		child.SCMCooldownID = nil
		child.SCMConfigID = nil

		Icons.SetChildVisibilityState(child, false, true)
		return
	end

	local group = childData.source[categoryIndex] or childData.source[SCM.Constants.SourcePairs[categoryIndex]]
	local groupConfig = childData.anchorGroup and childData.anchorGroup[group]
	if not (group and groupConfig) then
		child.SCMConfigID = nil
		Icons.SetChildVisibilityState(child, false, true)
		return
	end

	AddChildToGroup(validChildren, group, child)

	child.SCMChanged = not child.SCMConfig or child.SCMConfig ~= groupConfig
	child.SCMConfig = groupConfig
	child.SCMOrder = groupConfig.order
	child.SCMCooldownID = cooldownID
	child.SCMConfigID = configID
	child.SCMGroup = group

	SCM:SkinChild(child, groupConfig)

	if isBuffIcon then
		ProcessBuffIcon(child, groupConfig, options)
	else
		ProcessRegularIcon(child, groupConfig)
	end

	if not InCombatLockdown() then
		if childData.hideWhileMounted then
			RegisterAttributeDriver(child, "state-visibility", "[combat]show;[mounted][stance:3]hide;show")
		else
			UnregisterAttributeDriver(child, "state-visibility")
		end
	end
end

function Icons.ProcessChildren(viewer, validChildren, isBuffIcon)
	if not viewer then
		return
	end

	local children = GetOrCacheChildren(viewer, isBuffIcon)
	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	local options = SCM.db.global.options

	for _, child in ipairs(children) do
		ProcessSingleChild(child, validChildren, categoryIndex, isBuffIcon, options)
	end
end
