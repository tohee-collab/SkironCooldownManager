local addonName, SCM = ...

local Cache = SCM.Cache
local Utils = SCM.Utils
local ToGlobalGroup = Utils.ToGlobalGroup
local SortBySCMOrder = Utils.SortBySCMOrder
local AddChildToGroup = Utils.AddChildToGroup
local CustomIcons = SCM.CustomIcons
local Icons = SCM.Icons

local CDM = SCM.CDM

local UPDATE_SCOPE = {
	ALL = "all",
	ESSENTIAL = "essential",
	UTILITY = "utility",
	BUFF = "buff",
}
CDM.UPDATE_SCOPE = UPDATE_SCOPE

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

local DEFAULT_ROW_CONFIG = { { limit = 8, iconWidth = 47, iconHeight = 47 } }
local DEFAULT_ANCHOR = { "CENTER", UIParent, "CENTER", 0, 0 }

function SCM:Debug(...)
	if self.db.profile.options.debug then
		print(addonName, ...)
	end
end

local function IsScopedGroup(scopedAnchorGroups, group)
	return not scopedAnchorGroups or scopedAnchorGroups[group]
end

local function IsScopedAnchorGroupAllowed(group, isGlobal)
	local effectiveGroup = isGlobal and ToGlobalGroup(group) or group
	return IsScopedGroup(Cache.activeScopedAnchorGroups, effectiveGroup)
end
CDM.IsScopedAnchorGroupAllowed = IsScopedAnchorGroupAllowed

local function AddChildToScopedGroup(validChildren, group, child, isGlobal)
	if IsScopedAnchorGroupAllowed(group, isGlobal) then
		AddChildToGroup(validChildren, group, child, isGlobal)
	end
end
CDM.AddChildToScopedGroup = AddChildToScopedGroup

local function UpdateEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups)
	if not IsScopedGroup(scopedAnchorGroups, group) or Cache.cachedCooldownFrameTbl[group] then
		return
	end

	local rowConfig = (anchorConfig and anchorConfig.rowConfig and #anchorConfig.rowConfig > 0) and anchorConfig.rowConfig or DEFAULT_ROW_CONFIG
	local p, a, r, x, y = unpack(anchorConfig and anchorConfig.anchor or DEFAULT_ANCHOR)
	local initialIconWidth = rowConfig[1].iconWidth or rowConfig[1].size or 47
	local growDir = anchorConfig and anchorConfig.grow or "CENTERED"
	local groupAnchor = SCM:GetAnchor(group, p, a, r, x, y, growDir, initialIconWidth, true)

	if group == 1 then
		if C_AddOns.IsAddOnLoaded("SenseiClassResourceBar") then
			if SCRB and SCRB.registerCustomFrame then
				SCRB.registerCustomFrame(groupAnchor)
			else
				SCM:UpdateResourceBarWidth(initialIconWidth)
			end
		end

		if not InCombatLockdown() then
			SCM:UpdateUUFValues(SCM.db.profile.options, initialIconWidth, rowConfig)
		end
	end
end

local function LayoutAnchorGroup(group, visibleChildren, anchorConfig, options)
	local rowConfig = (anchorConfig and anchorConfig.rowConfig and #anchorConfig.rowConfig > 0) and anchorConfig.rowConfig or DEFAULT_ROW_CONFIG
	local lastRowConfig = rowConfig[#rowConfig]
	local growDir = anchorConfig and anchorConfig.grow or "CENTERED"
	local isCentered = growDir == "CENTER" or growDir == "CENTERED"
	local isFixed = growDir == "FIXED"
	local baseSpacing = anchorConfig and anchorConfig.spacing or 0

	table.sort(visibleChildren, SortBySCMOrder)

	local p, a, r, x, y = unpack(anchorConfig and anchorConfig.anchor or DEFAULT_ANCHOR)
	local initialWidth = rowConfig[1].iconWidth or rowConfig[1].size or 47
	local initialHeight = rowConfig[1].iconHeight or rowConfig[1].size or 47
	local groupAnchor = SCM:GetAnchor(group, p, a, r, x, y, growDir, initialWidth)

	local layoutChildren = visibleChildren
	if isFixed then
		layoutChildren = Cache.cachedChildrenTbl[group] or visibleChildren
		table.sort(layoutChildren, SortBySCMOrder)
	end

	local childIndex = 1
	local rowIndex = 1
	local accumulatedY = 0
	local maxGroupWidth = 0
	local startPoint = (isCentered or isFixed) and "TOP" or (growDir == "LEFT" and "TOPRIGHT") or "TOPLEFT"

	local totalChildren = #layoutChildren
	while childIndex <= totalChildren do
		local currentRowConfig = rowConfig[rowIndex] or lastRowConfig
		totalChildren = (currentRowConfig.hardLimit and min(#visibleChildren, (childIndex + currentRowConfig.limit - 1))) or totalChildren

		local rowLimit = min(totalChildren, currentRowConfig.limit or 8)
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

		local endIndex = math.min(childIndex + rowLimit - 1, #layoutChildren)
		local numInRow = endIndex - childIndex + 1

		local rowWidth = (numInRow * rowIconWidth) + ((numInRow - 1) * baseSpacing)
		maxGroupWidth = math.max(maxGroupWidth, (currentRowConfig.useFixedWidth and currentRowConfig.fixedWidth) or rowWidth)

		for i = 0, numInRow - 1 do
			local child = layoutChildren[childIndex + i]
			child.SCMRowConfig = currentRowConfig
			local offsetX = 0
			if isCentered or isFixed then
				offsetX = (i * (rowIconWidth + baseSpacing)) - (rowWidth / 2) + (rowIconWidth / 2)
			elseif growDir == "LEFT" then
				offsetX = -(i * (rowIconWidth + baseSpacing))
			else -- RIGHT
				offsetX = i * (rowIconWidth + baseSpacing)
			end

			if child.SCMShouldBeVisible then
				SCM:UpdateManagedAnchorChild(child, groupAnchor, startPoint, offsetX, -accumulatedY, rowIconWidth, rowIconHeight)
			end

			SCM:SkinChild(child, child.SCMConfig)
		end

		accumulatedY = accumulatedY + rowIconHeight + baseSpacing
		childIndex = endIndex + 1
		rowIndex = rowIndex + 1
	end

	if totalChildren < #visibleChildren then
		for childIndex = totalChildren + 1, #visibleChildren do
			Icons.SetChildVisibilityState(visibleChildren[childIndex], false, true)
		end
	end

	if group == 1 then
		if not InCombatLockdown() then
			groupAnchor:SetSize(SCM:PixelPerfect(max(initialWidth, maxGroupWidth, 1)), SCM:PixelPerfect(max(initialHeight, accumulatedY - baseSpacing, 1)))

			if options.adjustResourceWidth and C_AddOns.IsAddOnLoaded("SenseiClassResourceBar") then
				if SCRB and SCRB.registerCustomFrame then
					SCRB.registerCustomFrame(SCM:GetAnchor(1))
				else
					SCM:UpdateResourceBarWidth(maxGroupWidth)
				end
			end

			SCM:UpdateUUFValues(options, maxGroupWidth, rowConfig)
		end

		SCM:ApplyCustomAnchors(maxGroupWidth, rowConfig)
	elseif not InCombatLockdown() and groupAnchor then
		groupAnchor:SetSize(SCM:PixelPerfect(max(initialWidth, maxGroupWidth, 1)), SCM:PixelPerfect(max(initialHeight, accumulatedY - baseSpacing, 1)))
	end
end

local function OrderCDManagerSpells_Actual(updateScope, scopedAnchorGroupsOverride)
	Cache.cachedViewerScale = 1

	wipe(Cache.cachedChildrenTbl)
	wipe(Cache.cachedCooldownFrameTbl)

	local config = SCM.currentConfig
	local scopedAnchorGroups = scopedAnchorGroupsOverride or Icons.CollectScopedAnchorGroups(updateScope, config, VIEWER_UPDATE_MAPPING)
	local options = SCM.db.profile.options
	Cache.activeScopedAnchorGroups = scopedAnchorGroups

	for i = 1, #VIEWER_PROCESS_ORDER do
		local viewerData = VIEWER_PROCESS_ORDER[i]
		Icons.ProcessChildren(_G[viewerData.frameName], Cache.cachedChildrenTbl, viewerData.isBuffIcon)
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

	for _, customConfig in pairs(SCM.customConfig) do
		CustomIcons.ProcessIcons(customConfig, Cache.cachedCooldownFrameTbl)
	end

	for _, customConfig in pairs(SCM.globalCustomConfig) do
		CustomIcons.ProcessIcons(customConfig, Cache.cachedCooldownFrameTbl, true)
	end

	for group, visibleChildren in pairs(Cache.cachedCooldownFrameTbl) do
		LayoutAnchorGroup(group, visibleChildren, Utils.GetAnchorConfigForGroup(config, group, SCM.globalAnchorConfig), options)
	end

	for _, children in pairs(Cache.cachedChildrenTbl) do
		for _, child in ipairs(children) do
			Icons.SetChildVisibilityState(child, child.SCMShouldBeVisible, true)
		end
	end

	wipe(Cache.cachedVisitedAnchorGroups)
	for group, anchorConfig in pairs(config.anchorConfig) do
		Cache.cachedVisitedAnchorGroups[group] = true
		UpdateEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups)
	end

	for index, anchorConfig in pairs(SCM.globalAnchorConfig) do
		local group = ToGlobalGroup(index)
		if not Cache.cachedVisitedAnchorGroups[group] then
			Cache.cachedVisitedAnchorGroups[group] = true
			UpdateEmptyAnchorGroup(group, anchorConfig, scopedAnchorGroups)
		end
	end

	Cache.activeScopedAnchorGroups = nil
end
CDM.OrderSpellsActual = OrderCDManagerSpells_Actual

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

local function OrderCDManagerSpells(updateScope, isInit)
	updateScope = updateScope or UPDATE_SCOPE.ALL
	if updateScope == UPDATE_SCOPE.BUFF or isInit then
		OrderCDManagerSpells_Actual(updateScope)
		return
	end
	if isThrottled then
		pendingUpdateScope = MergeUpdateScope(pendingUpdateScope, updateScope)
		return
	end

	hasPendingUpdate = true
	isThrottled = true
	C_Timer.After(0.1, OnOrderThrottleTick)
end
CDM.OrderSpells = OrderCDManagerSpells
