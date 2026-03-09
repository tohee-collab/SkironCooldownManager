local addonName, SCM = ...
SCM.anchorFrames = {}
SCM.itemFrames = {}
SCM.customIconFrames = SCM.customIconFrames or {}
SCM.MainTabs = {}
SCM.OptionsCallbacks = {}
SCM.Skins = {}
SCM.CustomAnchors = {}

local LibCustomGlow = LibStub("LibCustomGlow-1.0")
local Cache = SCM.Cache
local UPDATE_SCOPE = {
	ALL = "all",
	ESSENTIAL = "essential",
	UTILITY = "utility",
	BUFF = "buff",
}
local VIEWER_UPDATE_MAPPING = {
	[UPDATE_SCOPE.ESSENTIAL] = {
		frameName = "EssentialCooldownViewer",
		isBuffIcon = false,
	},
	[UPDATE_SCOPE.UTILITY] = {
		frameName = "UtilityCooldownViewer",
		isBuffIcon = false,
	},
	[UPDATE_SCOPE.BUFF] = {
		frameName = "BuffIconCooldownViewer",
		isBuffIcon = true,
	},
}
local VIEWER_PROCESS_ORDER = {
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.ESSENTIAL],
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.UTILITY],
	VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.BUFF],
}
local delayedHideSpellIDs = {
	[450615] = true,
}
local delayedHideSeconds = 0.03
local DEFAULT_ROW_CONFIG = { { limit = 8, iconWidth = 47, iconHeight = 47 } }
local DEFAULT_ANCHOR = { "CENTER", UIParent, "CENTER", 0, 0 }
local Utils = SCM.Utils
local ToGlobalGroup = Utils.ToGlobalGroup
local SortBySCMOrder = Utils.SortBySCMOrder
local AddChildToGroup = Utils.AddChildToGroup
local CustomIcons = SCM.CustomIcons
local PIVOT_MAP = {
	LEFT = {
		TOP = "TOPRIGHT",
		TOPLEFT = "TOPRIGHT",
		BOTTOM = "BOTTOMRIGHT",
		BOTTOMLEFT = "BOTTOMRIGHT",
		LEFT = "RIGHT",
	},
	RIGHT = {
		TOP = "TOPLEFT",
		TOPRIGHT = "TOPLEFT",
		BOTTOM = "BOTTOMLEFT",
		BOTTOMRIGHT = "BOTTOMLEFT",
		RIGHT = "LEFT",
	},
}

local function GetAnchorConfigForGroup(config, group)
	return Utils.GetAnchorConfigForGroup(config, group, SCM.globalAnchorConfig)
end

function SCM:Debug(...)
	if self.db.global.options.debug then
		print(addonName, ...)
	end
end

local function RequestApplyAllCDManagerConfigs()
	SCM:ApplyAllCDManagerConfigs()
end

local function RequestApplyEssentialCDManagerConfig()
	SCM:ApplyEssentialCDManagerConfig()
end

local function RequestApplyUtilityCDManagerConfig()
	SCM:ApplyUtilityCDManagerConfig()
end

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

local function HideChild(child)
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

local function ShowChild(child)
	CancelChildHideTimer(child)

	if child.viewerFrame and child.SCMHidden then
		child.SCMHidden = false
		UIParent.SetAlpha(child, 1)
		child:EnableMouse(true)
		SCM:Debug("SHOW", GetTime(), child.SCMSpellID or "unknown", child.SCMCooldownID or "unknown")
	end
end

local function SetChildVisibilityState(child, shouldShow, applyNow)
	child.SCMShouldBeVisible = shouldShow and true or false
	if not applyNow then
		return
	end

	if child.viewerFrame then
		if shouldShow then
			ShowChild(child)
		else
			HideChild(child)
		end
		return
	end

	child:SetShown(shouldShow)
end

SCM.SetChildVisibilityState = SetChildVisibilityState

local function UpdateChildDesaturation(child, shouldDesaturate)
	if child.Icon and child.SCMConfig and child.SCMSpellID and not SCM.db.global.options.testSetting[child.SCMSpellID] then
		if child.SCMConfig.desaturate then
			child.Icon:SetDesaturated(shouldDesaturate)
		else
			child.Icon:SetDesaturated(false)
		end
	end
end

local function UpdateChildGlow(child, isInactive)
	if child.SCMConfig and child.SCMConfig.glowWhileActive then
		if not isInactive then
			SCM:StartCustomGlow(child)
		else
			SCM:StopCustomGlow(child)
		end
	end
end

local function OnManagedChildShow(child)
	UIParent.SetAlpha(child, child.SCMHidden and 0 or 1)
	if child and child.SCMGroup then
		SCM:ApplyAnchorGroupCDManagerConfig(child.SCMGroup)
	end
end

local function OnManagedChildHide(child)
	--SCM:ApplyAllCDManagerConfigs()
	if child and child.SCMGroup then
		SCM:ApplyAnchorGroupCDManagerConfig(child.SCMGroup)
	end
end

local function SetupChildHooks(child)
	if child.SCMShowHook or child == UIParent then
		return
	end
	child.SCMShowHook = true

	child:HookScript("OnShow", OnManagedChildShow)
	child:HookScript("OnHide", OnManagedChildHide)
end

local function OnBuffCooldownSet(self)
	local parent = self:GetParent()
	if not parent or not parent.SCMConfig then
		return
	end

	ShowChild(parent)
	UpdateChildDesaturation(parent, false)
	SCM:ApplyAllCDManagerConfigs()
end

local function OnBuffCooldownEnd(self)
	local parent = self:GetParent()
	if not parent or not parent.SCMConfig then
		return
	end

	local options = parent.SCMBuffOptions
	if not options or not options.hideBuffsWhenInactive then
		return
	end

	if parent.SCMConfig.alwaysShow then
		UpdateChildDesaturation(parent, true)
		return
	end

	SCM:ApplyAllCDManagerConfigs()
end

local function OnBuffTriggerPandemicAlert(self)
	local options = self.SCMBuffOptions
	if options and options.pandemicGlowOption ~= "keepPandemicGlow" then
		self.SCMPandemic = true
	end
end

local pendingPandemicGlowChildren = {}

local function StartPendingPandemicGlows()
	for child in pairs(pendingPandemicGlowChildren) do
		pendingPandemicGlowChildren[child] = nil
		if child then
			SCM:StartCustomGlow(child)
		end
	end
end

local function OnBuffShowPandemicStateFrame(self)
	if not self.PandemicIcon or self.PandemicIcon:GetAlpha() == 0 then
		return
	end

	self.PandemicIcon:SetAlpha(0)

	local options = self.SCMBuffOptions
	if not options or options.pandemicGlowOption ~= "replacePandemicGlow" then
		return
	end

	pendingPandemicGlowChildren[self] = true
	RunNextFrame(StartPendingPandemicGlows)
end

local function OnBuffHidePandemicStateFrame(self)
	local options = self.SCMBuffOptions
	if not options then
		return
	end

	if self.SCMPandemic and options.pandemicGlowOption == "replacePandemicGlow" then
		SCM:StopCustomGlow(self)
		self.SCMPandemic = nil
	end
end

local function SetupBuffIconHooks(child, options)
	if child.SCMShowHook then
		return
	end

	SetupChildHooks(child)
	child.SCMBuffOptions = options
	hooksecurefunc(child.Cooldown, "SetCooldown", OnBuffCooldownSet)
	hooksecurefunc(child.Cooldown, "Clear", OnBuffCooldownEnd)
	child.Cooldown:HookScript("OnCooldownDone", OnBuffCooldownEnd)
	hooksecurefunc(child, "TriggerPandemicAlert", OnBuffTriggerPandemicAlert)
	hooksecurefunc(child, "ShowPandemicStateFrame", OnBuffShowPandemicStateFrame)
	hooksecurefunc(child, "HidePandemicStateFrame", OnBuffHidePandemicStateFrame)
end

local function ProcessBuffIcon(child, childData, options)
	SetupBuffIconHooks(child, options)
	child.SCMBuffOptions = options

	local isInactive = not child.Cooldown:IsShown()
	local forceShow = SCM.simulateBuffs or (not SCM.isHideWhenInactiveEnabled and childData.alwaysShow)

	--local shouldHide = options.hideBuffsWhenInactive and isInactive and not forceShow
	local shouldHide = isInactive and not forceShow

	if shouldHide then
		SetChildVisibilityState(child, false, true)
		return
	end

	SetChildVisibilityState(child, true, true)
	UpdateChildDesaturation(child, isInactive)
	UpdateChildGlow(child, isInactive)
end

local function IsChildOnCooldown(child)
	if not child or not child.Cooldown then
		return
	end

	local spellCooldownInfo = C_Spell.GetSpellCooldown(child.SCMSpellID)
	if spellCooldownInfo and spellCooldownInfo.isOnGCD then
		return
	end

	local hasCooldown = child.Cooldown:IsShown()
	if hasCooldown then
		return true
	end
end

local function OnRegularCooldownChanged(self)
	local parent = self:GetParent()
	if parent and parent.SCMConfig and parent.SCMConfig.hideWhenNotOnCooldown then
		local viewer = parent.viewerFrame
		if viewer then
			local viewerName = viewer:GetName()
			if viewerName == VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.ESSENTIAL].frameName then
				RunNextFrame(RequestApplyEssentialCDManagerConfig)
			elseif viewerName == VIEWER_UPDATE_MAPPING[UPDATE_SCOPE.UTILITY].frameName then
				RunNextFrame(RequestApplyUtilityCDManagerConfig)
			end
		else
			RunNextFrame(RequestApplyAllCDManagerConfigs)
		end
	end
end

local function SetupCooldownHooks(child)
	if child.SCMRegularCooldownHook or not child.Cooldown then
		return
	end

	hooksecurefunc(child.Cooldown, "SetCooldown", OnRegularCooldownChanged)
	hooksecurefunc(child.Cooldown, "Clear", OnRegularCooldownChanged)
	child.Cooldown:HookScript("OnCooldownDone", OnRegularCooldownChanged)
	child.SCMRegularCooldownHook = true
end

local function SetupRegularIconHooks(child)
	if child.SCMRegularCooldownHook then
		return
	end

	SetupChildHooks(child)
	SetupCooldownHooks(child)
end

local function ProcessRegularIcon(child, childData)
	SetupRegularIconHooks(child)
	SetChildVisibilityState(child, not (childData.hideWhenNotOnCooldown and not IsChildOnCooldown(child)), false)
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

local function CollectScopedAnchorGroups(updateScope, config)
	if updateScope == UPDATE_SCOPE.ALL then
		return
	end

	local viewerData = VIEWER_UPDATE_MAPPING[updateScope]
	local targetGroups = viewerData and Cache.cachedScopedAnchorGroups[updateScope]
	if not targetGroups then
		return
	end

	wipe(targetGroups)

	local viewer = viewerData and _G[viewerData.frameName]
	local spellConfig = config and config.spellConfig
	local defaultConfig = SCM.defaultCooldownViewerConfig
	if not (viewer and spellConfig and defaultConfig) then
		return targetGroups
	end

	local categoryIndex = SCM.CooldownViewerNameToIndex[viewer:GetName()]
	if not categoryIndex then
		return targetGroups
	end

	local categoryConfig = defaultConfig[categoryIndex]
	local pairCategory = SCM.Constants.SourcePairs[categoryIndex]
	local allCooldownIDs = defaultConfig.cooldownIDs

	for _, child in ipairs(GetOrCacheChildren(viewer, viewerData.isBuffIcon)) do
		if child.GetCooldownID then
			local cooldownID = child:GetCooldownID()
			local info = (categoryConfig and categoryConfig[cooldownID]) or (allCooldownIDs and allCooldownIDs[cooldownID])
			local spellID = info and info.spellID
			local childData = spellID and spellConfig[spellID]
			local group = childData and (childData.source[categoryIndex] or childData.source[pairCategory])
			if group then
				targetGroups[group] = true
			end
		end
	end

	return targetGroups
end

local function IsScopedGroup(scopedAnchorGroups, group)
	return not scopedAnchorGroups or scopedAnchorGroups[group]
end

local function IsScopedAnchorGroupAllowed(group, isGlobal)
	local effectiveGroup = isGlobal and ToGlobalGroup(group) or group
	return IsScopedGroup(Cache.activeScopedAnchorGroups, effectiveGroup)
end
SCM.IsScopedAnchorGroupAllowed = IsScopedAnchorGroupAllowed

local function AddChildToScopedGroup(validChildren, group, child, isGlobal)
	if IsScopedAnchorGroupAllowed(group, isGlobal) then
		AddChildToGroup(validChildren, group, child, isGlobal)
	end
end
SCM.AddChildToScopedGroup = AddChildToScopedGroup

local function ProcessSingleChild(child, validChildren, spellConfig, categoryIndex, isBuffIcon, options)
	if not child.Icon then
		return
	end

	local cooldownID = child:GetCooldownID()
	local categoryConfig = categoryIndex and SCM.defaultCooldownViewerConfig[categoryIndex]
	local info = categoryConfig and (categoryConfig[cooldownID] or SCM.defaultCooldownViewerConfig.cooldownIDs[cooldownID])
	local spellID = info and info.spellID
	child.SCMSpellID = spellID
	child.SCMConfig = nil
	child.SCMOrder = nil
	child.SCMCooldownID = nil

	if not (cooldownID and spellID and spellConfig[spellID]) then
		SetChildVisibilityState(child, false, true)
		return
	end

	local childData = spellConfig[spellID]
	local group = childData.source[categoryIndex] or childData.source[SCM.Constants.SourcePairs[categoryIndex]]

	if not group then
		SetChildVisibilityState(child, false, true)
		return
	end

	AddChildToGroup(validChildren, group, child)

	child.SCMConfig = childData
	child.SCMOrder = childData.anchorGroup[group].order
	child.SCMCooldownID = cooldownID
	child.SCMGroup = group

	SCM:SkinChild(child, childData)

	if isBuffIcon then
		ProcessBuffIcon(child, childData, options)
	else
		ProcessRegularIcon(child, childData)
	end
end

local function ProcessChildren(viewer, validChildren, config, isBuffIcon)
	if not viewer then
		return
	end

	local spellConfig = config and config.spellConfig
	local options = SCM.db.global.options
	local children = GetOrCacheChildren(viewer, isBuffIcon)
	local cooldownViewerName = viewer:GetName()
	local categoryIndex = SCM.CooldownViewerNameToIndex[cooldownViewerName]

	for _, child in ipairs(children) do
		ProcessSingleChild(child, validChildren, spellConfig, categoryIndex, isBuffIcon, options)
	end
end

local function OnIconCooldownDone(self)
	local parent = self:GetParent()
	if parent and parent.Icon then
		parent.Icon:SetDesaturated(false)
	end

	if parent.UpdateCooldown then
		parent.UpdateCooldown(parent, parent.SCMIconType, parent.SCMConfig)
	end

	if parent.UpdateCharges then
		parent.UpdateCharges(parent, parent.spellID)
	end
end

local function SetupCustomIconFrame(frame)
	frame.Cooldown:SetScript("OnCooldownDone", OnIconCooldownDone)
	SetupChildHooks(frame)
end
SCM.SetupCustomIconFrame = SetupCustomIconFrame

local function ApplyManagedAnchorPoint(child)
	local anchorFrame = child.SCMAnchorFrame
	local anchorData = child.SCMAnchorData
	if not anchorFrame or not anchorData then
		return
	end

	anchorFrame.ClearAllPoints(child)
	anchorFrame.SetPoint(child, anchorData[1], anchorData[2], anchorData[3], anchorData[4], anchorData[5])
end

local function OnManagedAnchorChildSetSize(child)
	local anchorFrame = child.SCMAnchorFrame
	if anchorFrame then
		anchorFrame.SetSize(child, child.width, child.height)
	end
end

local function OnManagedAnchorChildSetWidth(child)
	local anchorFrame = child.SCMAnchorFrame
	if anchorFrame then
		anchorFrame.SetWidth(child, child.width)
	end
end

local function OnManagedAnchorChildSetHeight(child)
	local anchorFrame = child.SCMAnchorFrame
	if anchorFrame then
		anchorFrame.SetHeight(child, child.height)
	end
end

local function UpdateEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups)
	if not IsScopedGroup(scopedAnchorGroups, group) or Cache.cachedCooldownFrameTbl[group] then
		return
	end

	local rowConfig = (anchorConfig and anchorConfig.rowConfig and #anchorConfig.rowConfig > 0) and anchorConfig.rowConfig or DEFAULT_ROW_CONFIG
	local p, a, r, x, y = unpack(anchorConfig and anchorConfig.anchor or DEFAULT_ANCHOR)
	local initialIconWidth = rowConfig[1].iconWidth or rowConfig[1].size or 47
	SCM:GetAnchor(group, p, a, r, x, y, anchorConfig.growDir, initialIconWidth, true)

	if group == 1 then
		if SCRB and SCRB.registerCustomFrame then
			if not SCM.registeredCustomFrame then
				SCM.registeredCustomFrame = true
				SCRB.registerCustomFrame(anchorConfig)
			end
		else
			SCM:UpdateResourceBarWidth(initialIconWidth)
		end

		if not InCombatLockdown() then
			SCM:UpdateUUFValues(SCM.db.global.options, initialIconWidth, rowConfig)
		end
	end
end

local function OrderCDManagerSpells_Actual(updateScope, scopedAnchorGroupsOverride)
	Cache.cachedViewerScale = 1

	wipe(Cache.cachedChildrenTbl)
	wipe(Cache.cachedCooldownFrameTbl)

	local config = SCM.currentConfig
	local scopedAnchorGroups = scopedAnchorGroupsOverride or CollectScopedAnchorGroups(updateScope, config)
	Cache.activeScopedAnchorGroups = scopedAnchorGroups
	local options = SCM.db.global.options
	for i = 1, #VIEWER_PROCESS_ORDER do
		local viewerData = VIEWER_PROCESS_ORDER[i]
		ProcessChildren(_G[viewerData.frameName], Cache.cachedChildrenTbl, config, viewerData.isBuffIcon)
	end

	for group, children in pairs(Cache.cachedChildrenTbl) do
		if IsScopedGroup(scopedAnchorGroups, group) then
			local visibleChildren = GetOrCreateTableEntry(Cache.cachedVisibleChildren, group)
			wipe(visibleChildren)
			for _, child in ipairs(children) do
				if child.SCMShouldBeVisible then
					visibleChildren[#visibleChildren + 1] = child
				end
			end

			Cache.cachedCooldownFrameTbl[group] = visibleChildren
		end
	end

	if options.enableCustomIcons then
		for _, customConfig in pairs(SCM.customConfig) do
			CustomIcons.ProcessIcons(customConfig, Cache.cachedCooldownFrameTbl)
		end

		for _, customConfig in pairs(SCM.globalCustomConfig) do
			CustomIcons.ProcessIcons(customConfig, Cache.cachedCooldownFrameTbl, true)
		end
	else
		CustomIcons.HideIcons()
	end

	for group, visibleChildren in pairs(Cache.cachedCooldownFrameTbl) do
		local anchorConfig = GetAnchorConfigForGroup(config, group)
		local rowConfig = (anchorConfig and anchorConfig.rowConfig and #anchorConfig.rowConfig > 0) and anchorConfig.rowConfig or DEFAULT_ROW_CONFIG
		local lastRowConfig = rowConfig[#rowConfig]
		local growDir = anchorConfig and anchorConfig.grow or "CENTER"
		local baseSpacing = anchorConfig and anchorConfig.spacing or 0

		table.sort(visibleChildren, SortBySCMOrder)

		local p, a, r, x, y = unpack(anchorConfig and anchorConfig.anchor or DEFAULT_ANCHOR)
		local initialWidth = rowConfig[1].iconWidth or rowConfig[1].size or 47
		local initialHeight = rowConfig[1].iconHeight or rowConfig[1].size or 47
		local groupAnchor = SCM:GetAnchor(group, p, a, r, x, y, growDir, initialWidth)

		local childIndex = 1
		local rowIndex = 1
		local accumulatedY = 0
		local maxGroupWidth = 0
		local startPoint = (growDir == "CENTER" and "TOP") or (growDir == "LEFT" and "TOPRIGHT") or "TOPLEFT"

		while childIndex <= #visibleChildren do
			local currentRowConfig = rowConfig[rowIndex] or lastRowConfig
			local rowLimit = currentRowConfig.limit or 8
			local rowIconWidth = currentRowConfig.iconWidth or currentRowConfig.size or 47
			local rowIconHeight = currentRowConfig.iconHeight or currentRowConfig.size or 47

			local scaleData = anchorConfig and anchorConfig.advancedScale
			if scaleData then
				local targetViewer = Cache.cachedCooldownFrameTbl[scaleData.viewer]
				local targetGroup = targetViewer and targetViewer[scaleData.anchorGroup]
				if targetGroup and #targetGroup <= scaleData.numChildren then
					rowIconWidth = scaleData.iconWidth or scaleData.size or rowIconWidth
					rowIconHeight = scaleData.iconHeight or scaleData.size or rowIconHeight
				end
			end

			local endIndex = math.min(childIndex + rowLimit - 1, #visibleChildren)
			local numInRow = endIndex - childIndex + 1

			local rowWidth = (numInRow * rowIconWidth) + ((numInRow - 1) * baseSpacing)
			maxGroupWidth = math.max(maxGroupWidth, rowWidth)

			for i = 0, numInRow - 1 do
				local child = visibleChildren[childIndex + i]
				child.width = rowIconWidth
				child.height = rowIconHeight
				child.SCMAnchorFrame = groupAnchor
				child:SetScale(Cache.cachedViewerScale)
				child:SetSize(rowIconWidth, rowIconHeight)

				local offsetX = 0
				if growDir == "CENTER" then
					offsetX = (i * (rowIconWidth + baseSpacing)) - (rowWidth / 2) + (rowIconWidth / 2)
				elseif growDir == "LEFT" then
					offsetX = -(i * (rowIconWidth + baseSpacing))
				else -- RIGHT
					offsetX = i * (rowIconWidth + baseSpacing)
				end

				local offsetY = -accumulatedY

				if not child.SCMSizeHook then
					child.SCMSizeHook = true
					hooksecurefunc(child, "SetSize", OnManagedAnchorChildSetSize)
					hooksecurefunc(child, "SetWidth", OnManagedAnchorChildSetWidth)
					hooksecurefunc(child, "SetHeight", OnManagedAnchorChildSetHeight)
				end

				if not child.SCMPointHook then
					child.SCMPointHook = true
					hooksecurefunc(child, "SetPoint", ApplyManagedAnchorPoint)
					hooksecurefunc(child, "ClearAllPoints", ApplyManagedAnchorPoint)
				end

				local anchorData = child.SCMAnchorData or {}
				child.SCMAnchorData = anchorData
				if anchorData[1] ~= startPoint or anchorData[2] ~= groupAnchor or anchorData[3] ~= startPoint or anchorData[4] ~= offsetX or anchorData[5] ~= offsetY then
					anchorData[1] = startPoint
					anchorData[2] = groupAnchor
					anchorData[3] = startPoint
					anchorData[4] = offsetX
					anchorData[5] = offsetY
					ApplyManagedAnchorPoint(child)
				end
			end

			accumulatedY = accumulatedY + rowIconHeight + baseSpacing
			childIndex = endIndex + 1
			rowIndex = rowIndex + 1
		end
		if group == 1 then
			if not InCombatLockdown() then
				groupAnchor:SetSize(max(initialWidth, maxGroupWidth, 1), max(initialHeight, accumulatedY - baseSpacing, 1))

				if SCM.db.global.options.adjustResourceWidth then
					if SCRB and SCRB.registerCustomFrame then
						if not SCM.registeredCustomFrame then
							SCM.registeredCustomFrame = true
							SCRB.registerCustomFrame(SCM:GetAnchor(1))
						end
					else
						SCM:UpdateResourceBarWidth(maxGroupWidth)
					end
				end

				SCM:UpdateUUFValues(SCM.db.global.options, maxGroupWidth, rowConfig)
			end

			SCM:ApplyCustomAnchors(maxGroupWidth, rowConfig)
		elseif not InCombatLockdown() then
			groupAnchor:SetSize(max(initialWidth, maxGroupWidth, 1), max(initialHeight, accumulatedY - baseSpacing, 1))
		end
	end

	for _, children in pairs(Cache.cachedChildrenTbl) do
		for _, child in ipairs(children) do
			SetChildVisibilityState(child, child.SCMShouldBeVisible, true)
		end
	end

	wipe(Cache.cachedVisitedAnchorGroups)
	for group, anchorConfig in pairs(config.anchorConfig) do
		Cache.cachedVisitedAnchorGroups[group] = true
		UpdateEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups)
	end

	for index, anchorConfig in pairs(SCM.globalAnchorConfig or {}) do
		local group = ToGlobalGroup(index)
		if not Cache.cachedVisitedAnchorGroups[group] then
			Cache.cachedVisitedAnchorGroups[group] = true
			UpdateEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups)
		end
	end

	Cache.activeScopedAnchorGroups = nil
end

local isThrottled = false
local hasPendingUpdate = false
local pendingUpdateScope

local function MergeUpdateScope(currentScope, newScope)
	if not currentScope then
		return newScope
	end

	if currentScope == UPDATE_SCOPE.ALL or newScope == UPDATE_SCOPE.ALL then
		return UPDATE_SCOPE.ALL
	end

	if currentScope ~= newScope then
		return UPDATE_SCOPE.ALL
	end

	return currentScope
end

local function OnOrderThrottleTick()
	isThrottled = false
	if hasPendingUpdate then
		hasPendingUpdate = false
		OrderCDManagerSpells_Actual(pendingUpdateScope or UPDATE_SCOPE.ALL)
		pendingUpdateScope = nil
	end
end

local function OrderCDManagerSpells(updateScope)
	-- print(updateScope)
	-- if updateScope == UPDATE_SCOPE.ALL then
	-- 	if DevTool then
	-- 		DevTool:AddData({strsplit("\n", debugstack())}, updateScope)
	-- 	end
	-- end

	updateScope = updateScope or UPDATE_SCOPE.ALL
	if updateScope == UPDATE_SCOPE.BUFF then
		OrderCDManagerSpells_Actual(updateScope)
		return
	elseif isThrottled then
		hasPendingUpdate = true
		pendingUpdateScope = MergeUpdateScope(pendingUpdateScope, updateScope)
		return
	end

	OrderCDManagerSpells_Actual(updateScope)
	isThrottled = true
	C_Timer.After(0.1, OnOrderThrottleTick)
end

local function OnAnchorDebugTextureShow(self)
	local anchorFrame = self:GetParent()
	if not anchorFrame then
		return
	end

	anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
	LibCustomGlow.PixelGlow_Start(anchorFrame, nil, nil, nil, nil, nil, nil, nil, nil, "SCM")
end

local function OnAnchorDebugTextureHide(self)
	local anchorFrame = self:GetParent()
	self.isGlowActive = false
	if anchorFrame then
		LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
	end
end

function SCM:GetAnchor(group, point, anchor, relativePoint, xOffset, yOffset, growDir, iconSize, resetSize)
	if group > 100 and not self.db.global.options.enableCustomIcons then return end

	local anchorFrame = self.anchorFrames[group]
	if not anchorFrame then
		anchorFrame = CreateFrame("Frame", "SCM_GroupAnchor_" .. group, UIParent)
		anchorFrame:SetFrameStrata("HIGH")
		anchorFrame.debugTexture = anchorFrame:CreateTexture(nil, "BACKGROUND")
		anchorFrame:SetScale(Cache.cachedViewerScale)

		anchorFrame.debugTexture:SetAllPoints()
		anchorFrame.debugTexture:SetColorTexture(8 / 255, 8 / 255, 8 / 255, 0.4)
		anchorFrame.debugTexture:SetShown(self.OptionsFrame ~= nil)

		anchorFrame.debugText = anchorFrame:CreateFontString(nil, "OVERLAY", "Permok_Expressway_Large")
		anchorFrame.debugText:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
		if group > 100 then
			anchorFrame.debugText:SetText("G" .. group - 100)
		else
			anchorFrame.debugText:SetText(group)
		end
		anchorFrame.debugText:SetFontHeight(35)
		anchorFrame.debugText:SetShown(self.OptionsFrame ~= nil)
		anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)

		anchorFrame.debugTexture:HookScript("OnShow", OnAnchorDebugTextureShow)
		anchorFrame.debugTexture:HookScript("OnHide", OnAnchorDebugTextureHide)

		-- if group == 1 then
		-- 	hooksecurefunc(anchorFrame, "SetSize", function(self, width, height)
		-- 		if DevTool then
		-- 			DevTool:AddData({ strsplit("\n", debugstack()) }, width)
		-- 		end
		-- 	end)
		-- end

		self.anchorFrames[group] = anchorFrame
	end

	if not (point and anchor) or InCombatLockdown() then
		return anchorFrame
	end

	anchorFrame:Show()

	local target = anchor
	if type(target) == "string" then
		local id = target:match("ANCHOR:(%d+)")
		target = id and self:GetAnchor(tonumber(id)) or _G[target] or SCM[target]

		if id and target then
			anchorFrame:SetScale(target:GetScale())
		end
	end

	target = target or UIParent

	local pivot = (PIVOT_MAP[growDir] and PIVOT_MAP[growDir][point]) or point

	local xMod = 0
	if growDir == "LEFT" then
		xMod = (point == "TOPLEFT" and 1) or ((point == "TOP" or point == "BOTTOM" or point == "CENTER") and 0.5) or 0
	elseif growDir == "RIGHT" then
		xMod = (point == "TOPRIGHT" and -1) or ((point == "TOP" or point == "BOTTOM" or point == "CENTER") and -0.5) or 0
	end

	if resetSize then
		anchorFrame:SetSize(iconSize, iconSize)
	else
		anchorFrame:SetSize(max(anchorFrame:GetWidth(), iconSize), max(anchorFrame:GetHeight(), iconSize))
	end
	anchorFrame:ClearAllPoints()
	anchorFrame:SetPoint(pivot, target, relativePoint, xOffset + ((iconSize or 0) * xMod), yOffset)
	anchorFrame:Show()

	if self.OptionsFrame ~= nil and self.OptionsFrame:IsShown() and not anchorFrame.isGlowActive then
		anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
		LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
		LibCustomGlow.PixelGlow_Start(anchorFrame, nil, nil, nil, nil, nil, nil, nil, nil, "SCM")
	end

	return anchorFrame
end

function SCM:ApplyEssentialCDManagerConfig()
	if C_CVar.GetCVar("cooldownViewerEnabled") == "1" then
		if SCM.currentConfig then
			OrderCDManagerSpells(UPDATE_SCOPE.ESSENTIAL)
		end
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

	OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, { [scopedGroup] = true })
end

local function GetScopeGroupsForConfig(customConfig, scopedGroups)
	if not customConfig then return scopedGroups end

	local scopedGroups = scopedGroups or {}

	for _, config in pairs(customConfig) do
		scopedGroups[config.anchorGroup] = true
	end

	return scopedGroups
end

function SCM:ApplyAnchorGroupCustomConfig(customConfig)
	if not customConfig then return end

	local scopedGroups = GetScopeGroupsForConfig(customConfig)
	if next(scopedGroups) then
		OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, scopedGroups)
	end
end

function SCM:ApplyAnchorGroupByIconType(iconType, skipGlobal)
	local scopedGroups = GetScopeGroupsForConfig(self:GetConfigTable(iconType))

	if not skipGlobal then
		local globalConfigTable = self:GetConfigTable(iconType, true)

		if globalConfigTable then
			scopedGroups = GetScopeGroupsForConfig(globalConfigTable, scopedGroups)
		end
	end

	if next(scopedGroups) then
		OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, scopedGroups)
	end
end

function SCM:ApplyAnchorGroupByIconTypes(skipGlobal, ...)
	local scopedGroups = {}

	for _, iconType in ipairs({...}) do
		scopedGroups = GetScopeGroupsForConfig(self:GetConfigTable(iconType), scopedGroups)
		scopedGroups = GetScopeGroupsForConfig(self:GetConfigTable(iconType, true), scopedGroups)
	end

	if next(scopedGroups) then
		OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, scopedGroups)
	end
end

function SCM:ApplyAnchorGroupBySpellID(spellID, iconType)
	local scopedGroups = {}

	for id, config in pairs(self:GetConfigTable(iconType)) do
		if config.spellID == spellID then
			scopedGroups[config.anchorGroup] = true

			if iconType == "cast" then
				local customFrames = SCM.CustomIcons.GetCustomIconFrames(config)
				if customFrames and customFrames[id] then
					customFrames[id].lastCastStartTime = GetTime()
				end
			end
		end
	end

	for id, config in pairs(self:GetConfigTable(iconType, true)) do
		if config.spellID == spellID then
			scopedGroups[config.anchorGroup] = true

			if iconType == "cast" then
				local customFrames = SCM.CustomIcons.GetCustomIconFrames(config)
				if customFrames and customFrames[id] then
					customFrames[id].lastCastStartTime = GetTime()
				end
			end
		end
	end

	if next(scopedGroups) then
		OrderCDManagerSpells_Actual(UPDATE_SCOPE.ALL, scopedGroups)
	end
end

function SCM:UpdateCooldownInfo(isFirstLoad, dataProvider)
	self.defaultCooldownViewerConfig = {
		cooldownIDs = {},
		spellIDs = {},
	}
	self.currentCooldownViewerConfig = {}

	local displayData = dataProvider and dataProvider.displayData.cooldownInfoByID
	for _, cooldownCategory in pairs(CooldownViewerSettingsDataProvider_GetCategories()) do
		self.defaultCooldownViewerConfig[cooldownCategory] = {
			spellIDs = {},
			cooldownIDs = {},
		}

		local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cooldownCategory, true)
		local order = 0
		for _, cooldownID in ipairs(cooldownIDs) do
			-- category, charges, cooldownID, flags, hasAura, isKnown, linksSpellIDs, overrideSpellID, selfAura, spellID
			local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
			if info then
				local data = displayData[cooldownID]
				if data then
					self.defaultCooldownViewerConfig[cooldownCategory][data.cooldownID] = data
					self.defaultCooldownViewerConfig[cooldownCategory].spellIDs[data.spellID] = data
					self.defaultCooldownViewerConfig[cooldownCategory].cooldownIDs[data.cooldownID] = data
					self.defaultCooldownViewerConfig.cooldownIDs[data.cooldownID] = data
					self.defaultCooldownViewerConfig.spellIDs[data.spellID] = data

					if data and data.category >= 0 and data.category <= 2 then
						order = order + 1
						self.currentCooldownViewerConfig[data.spellID] = self.currentCooldownViewerConfig[data.spellID] or { source = {}, anchorGroup = {} }
						self.currentCooldownViewerConfig[data.spellID].source[data.category] = data.category + 1
						self.currentCooldownViewerConfig[data.spellID].anchorGroup[data.category + 1] = {
							order = order,
						}
					end
				end
			end
		end
	end
end

local function GetOrCreateCustomConfig()
	SCM.currentConfig.customConfig = GetOrCreateTableEntry(SCM.currentConfig, "customConfig", {spellConfig = {},itemConfig = {},slotConfig = {}})
	SCM.currentConfig.customConfig.spellConfig = GetOrCreateTableEntry(SCM.currentConfig.customConfig, "spellConfig")
	SCM.currentConfig.customConfig.itemConfig = GetOrCreateTableEntry(SCM.currentConfig.customConfig, "itemConfig")
	SCM.currentConfig.customConfig.slotConfig = GetOrCreateTableEntry(SCM.currentConfig.customConfig, "slotConfig")

	return SCM.currentConfig.customConfig
end

function SCM:UpdateDB()
	local class = UnitClassBase("player")
	local specID = GetSpecializationInfo(GetSpecialization())

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
	self.itemConfig = self.currentConfig.itemConfig
	self.customConfig = GetOrCreateCustomConfig()

	self.globalAnchorConfig = self.db.global.globalAnchorConfig or {}
	self.globalCustomConfig = self.db.global.globalCustomConfig

	self.isHideWhenInactiveEnabled = self:GetHideWhenInactive() == 1
	-- self.globalSpellConfig = self.db.global.globalCustomConfig.spellConfig
	-- self.globalItemConfig = self.db.global.globalCustomConfig.itemConfig
	-- self.globalSlotConfig = self.db.global.globalCustomConfig.slotConfig
end
