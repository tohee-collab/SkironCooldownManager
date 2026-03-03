local addonName, SCM = ...
SCM.anchorFrames = {}
SCM.itemFrames = {}
SCM.customIconFrames = SCM.customIconFrames or {}
SCM.MainTabs = {}
SCM.OptionsCallbacks = {}
SCM.Skins = {}
SCM.CustomAnchors = {}

local LibCustomGlow = LibStub("LibCustomGlow-1.0")

local cachedViewerScale
local cachedChildrenTbl = {}
local cachedVisibleChildren = {}
local cachedCooldownFrameTbl = {}
local cachedViewerChildren = {}
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
local GetOrCreateBucket = Utils.GetOrCreateBucket
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

local function OnManagedChildSetAlpha(self)
	UIParent.SetAlpha(self, self.SCMHidden and 0 or 1)
end

local function ApplyHideChildNow(child)
	child.SCMHidden = true
	UIParent.SetAlpha(child, 0)
	child:EnableMouse(false)
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

local function UpdateChildDesaturation(child, shouldDesaturate)
	if child.Icon and child.SCMConfig and child.SCMSpellID and not SCM.db.global.options.testSetting[child.SCMSpellID] then
		if child.SCMConfig.desaturate then
			child.Icon:SetDesaturated(shouldDesaturate)
		else
			child.Icon:SetDesaturated(false)
		end
	end
end

local function OnManagedChildShow(self)
	UIParent.SetAlpha(self, self.SCMHidden and 0 or 1)
	SCM:ApplyAllCDManagerConfigs()
end

local function OnManagedChildHide()
	SCM:ApplyAllCDManagerConfigs()
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
	--if not issecretvalue(child.Icon:GetTexture()) then
	--	--isInactive = false
	--end
	local forceShow = SCM.simulateBuffs or childData.alwaysShow

	local shouldHide = options.hideBuffsWhenInactive and isInactive and not forceShow

	if shouldHide then
		SetChildVisibilityState(child, false, true)
		return
	end

	SetChildVisibilityState(child, true, true)
	UpdateChildDesaturation(child, isInactive)
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
		RunNextFrame(RequestApplyAllCDManagerConfigs)
	end
end

local function SetupRegularIconHooks(child)
	if child.SCMRegularCooldownHook or not child.Cooldown then
		return
	end

	child.SCMRegularCooldownHook = true
	SetupChildHooks(child)
	hooksecurefunc(child.Cooldown, "SetCooldown", OnRegularCooldownChanged)
	hooksecurefunc(child.Cooldown, "Clear", OnRegularCooldownChanged)
	child.Cooldown:HookScript("OnCooldownDone", OnRegularCooldownChanged)
end

local function ProcessRegularIcon(child, childData)
	SetupRegularIconHooks(child)
	SetChildVisibilityState(child, not (childData.hideWhenNotOnCooldown and not IsChildOnCooldown(child)), false)
end

local function GetOrCacheChildren(viewer, isBuffIcon)
	if isBuffIcon then
		cachedViewerChildren[viewer] = nil
	end

	if not cachedViewerChildren[viewer] then
		cachedViewerChildren[viewer] = { viewer:GetChildren() }
	end

	return cachedViewerChildren[viewer]
end

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
end

local function OnItemDataLoaded(item)
	local frame = item.SCMTargetFrame
	if frame and frame.Icon then
		frame.Icon:SetTexture(item:GetItemIcon())
	end
	item.SCMTargetFrame = nil
end

local function ProcessItemConfig(itemConfig, validChildren)
	for slotID, config in pairs(itemConfig) do
		local itemID = GetInventoryItemID("player", slotID)
		if itemID and C_Item.GetItemSpell(itemID) then
			local frame = SCM.itemFrames[slotID] or CreateFrame("Frame", nil, UIParent, "PermokItemIconTemplate")
			frame:SetScale(cachedViewerScale)
			if not SCM.itemFrames[slotID] then
				frame.Cooldown:SetScript("OnCooldownDone", OnIconCooldownDone)
				SCM.itemFrames[slotID] = frame
			end

			if not frame.itemID or frame.itemID ~= itemID then
				frame.itemID = itemID
				frame.SCMCooldownID = "i:" .. itemID
				frame.SCMConfig = config
				frame.Icon:SetTexture(C_Item.GetItemIconByID(itemID))

				local item = Item:CreateFromItemID(itemID)
				item.SCMTargetFrame = frame
				item:ContinueOnItemLoad(OnItemDataLoaded)
				frame.SCMOrder = 100 + slotID

				local start, duration = GetInventoryItemCooldown("player", slotID)
				if start and start > 0 then
					frame.Cooldown:SetCooldown(start, duration)
					frame.Icon:SetDesaturated(true)
				else
					frame.Icon:SetDesaturated(false)
				end
			end

			SetChildVisibilityState(frame, true, true)
			AddChildToGroup(validChildren, config.anchorGroup or 1, frame)
		else
			if SCM.itemFrames[slotID] then
				SetChildVisibilityState(SCM.itemFrames[slotID], false, true)
			end
		end
	end
end

local function HideItemIcons()
	for _, itemFrame in pairs(SCM.itemFrames) do
		SetChildVisibilityState(itemFrame, false, true)
	end
end

local function HideCustomIcons()
	CustomIcons.HideIcons(SetChildVisibilityState)
end

local function SetupCustomIconFrame(frame)
	frame.Cooldown:SetScript("OnCooldownDone", OnIconCooldownDone)
	SetupChildHooks(frame)
end

local function GetCustomIconContext()
	return {
		viewerScale = cachedViewerScale,
		setChildVisibilityState = SetChildVisibilityState,
		setupFrame = SetupCustomIconFrame,
		addChildToGroup = AddChildToGroup,
	}
end

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

local function OnManagedAnchorChildSetPoint(child)
	ApplyManagedAnchorPoint(child)
end

local function OnManagedAnchorChildClearAllPoints(child)
	ApplyManagedAnchorPoint(child)
end

local function OrderCDManagerSpells_Actual()
	cachedViewerScale = 1

	wipe(cachedChildrenTbl)
	wipe(cachedCooldownFrameTbl)

	local config = SCM.currentConfig
	local options = SCM.db.global.options
	for _, cooldownViewer in ipairs({ EssentialCooldownViewer, UtilityCooldownViewer, BuffIconCooldownViewer }) do
		ProcessChildren(cooldownViewer, cachedChildrenTbl, SCM.currentConfig, cooldownViewer == BuffIconCooldownViewer)
	end

	for group, children in pairs(cachedChildrenTbl) do
		local visibleChildren = GetOrCreateBucket(cachedVisibleChildren, group)
		wipe(visibleChildren)
		for _, child in ipairs(children) do
			if child.SCMShouldBeVisible then
				visibleChildren[#visibleChildren + 1] = child
			end
		end

		cachedCooldownFrameTbl[group] = visibleChildren
	end

	if SCM.itemConfig and next(SCM.itemConfig) then
		ProcessItemConfig(SCM.itemConfig, cachedCooldownFrameTbl)
	else
		HideItemIcons()
	end

	if options.enableCustomIcons ~= false then
		local customIconContext = GetCustomIconContext()
		CustomIcons.ProcessIcons(SCM.customConfig, cachedCooldownFrameTbl, false, customIconContext)
		CustomIcons.ProcessIcons(SCM.globalCustomConfig, cachedCooldownFrameTbl, true, customIconContext)
	else
		HideCustomIcons()
	end

	for group, visibleChildren in pairs(cachedCooldownFrameTbl) do
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
				local targetViewer = cachedCooldownFrameTbl[scaleData.viewer]
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
				child:SetScale(cachedViewerScale)
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
					hooksecurefunc(child, "SetPoint", OnManagedAnchorChildSetPoint)
					hooksecurefunc(child, "ClearAllPoints", OnManagedAnchorChildClearAllPoints)
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

		if not InCombatLockdown() then
			groupAnchor:SetSize(max(initialWidth, maxGroupWidth, 1), max(initialHeight, accumulatedY - baseSpacing, 1))

			if group == 1 then
				if SCM.db.global.options.adjustResourceWidth then
					if not SCM.registeredCustomFrame and SCRB and SCRB.registerCustomFrame then
						SCM.registeredCustomFrame = true
						SCRB.registerCustomFrame(SCM:GetAnchor(1))
					else
						SCM:UpdateResourceBarWidth(maxGroupWidth)
					end
				end

				SCM:UpdateUUFValues(SCM.db.global.options, maxGroupWidth, rowConfig)
				SCM:ApplyCustomAnchors(maxGroupWidth, rowConfig)
			end
		end
	end

	for _, children in pairs(cachedChildrenTbl) do
		for _, child in ipairs(children) do
			SetChildVisibilityState(child, child.SCMShouldBeVisible, true)
		end
	end

	local allAnchors = {}
	for group, anchorConfig in pairs(config.anchorConfig) do
		allAnchors[group] = anchorConfig
	end
	for index, anchorConfig in pairs(SCM.globalAnchorConfig or {}) do
		allAnchors[ToGlobalGroup(index)] = anchorConfig
	end

	for group, anchorConfig in pairs(allAnchors) do
		if not cachedCooldownFrameTbl[group] then
			local rowConfig = anchorConfig.rowConfig

			local p, a, r, x, y = unpack(anchorConfig and anchorConfig.anchor or DEFAULT_ANCHOR)
			local initialIconWidth = rowConfig[1].iconWidth or rowConfig[1].size or 47
			SCM:GetAnchor(group, p, a, r, x, y, anchorConfig.growDir, initialIconWidth, not cachedCooldownFrameTbl[group])

			if group == 1 then
				if not SCM.registeredCustomFrame and SCRB and SCRB.registerCustomFrame then
					SCM.registeredCustomFrame = true
					SCRB.registerCustomFrame(anchorConfig)
				else
					SCM:UpdateResourceBarWidth(initialIconWidth)
				end

				if not InCombatLockdown() then
					SCM:UpdateUUFValues(SCM.db.global.options, initialIconWidth, rowConfig)
				end
			end
		end
	end
end

local isThrottled = false
local hasPendingUpdate = false

local function OnOrderThrottleTick()
	isThrottled = false
	if hasPendingUpdate then
		hasPendingUpdate = false
		OrderCDManagerSpells_Actual()
	end
end

local function OrderCDManagerSpells(isBuffIcon, config)
	if isBuffIcon then
		OrderCDManagerSpells_Actual()
		return
	elseif isThrottled then
		hasPendingUpdate = true
		return
	end

	OrderCDManagerSpells_Actual()
	isThrottled = true
	C_Timer.After(0, OnOrderThrottleTick)
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
	local anchorFrame = self.anchorFrames[group]
	if not anchorFrame then
		anchorFrame = CreateFrame("Frame", "SCM_GroupAnchor_" .. group, UIParent)
		anchorFrame:SetFrameStrata("HIGH")
		anchorFrame.debugTexture = anchorFrame:CreateTexture(nil, "BACKGROUND")
		anchorFrame:SetScale(cachedViewerScale)

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

local function OnResourceBarWidthChanged(self)
	UIParent.SetWidth(self, self.SCMWidth)
end

function SCM:UpdateResourceBarWidth(maxGroupWidth)
	for _, resourceBarName in ipairs(SCM.db.global.options.resourceBars) do
		local resourceBar = _G[resourceBarName]
		if resourceBar and resourceBar:IsShown() then
			resourceBar.SCMWidth = max(200, maxGroupWidth)
			resourceBar:SetWidth(max(200, maxGroupWidth))

			if not resourceBar.SCMHook then
				resourceBar.SCMHook = true
				hooksecurefunc(resourceBar, "SetWidth", OnResourceBarWidthChanged)
				hooksecurefunc(resourceBar, "SetSize", OnResourceBarWidthChanged)
			end
		end
	end
end

function SCM:UpdateUUFValues(options, maxGroupWidth, rowConfig)
	local offset = min((maxGroupWidth - 150), 0)
	local mainAnchor = SCM:GetAnchor(1)

	if UUF_Player then
		if options.anchorUUF and options.anchorUUFRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
			if not UUF_Player.SCMOriginalAnchor then
				UUF_Player.SCMOriginalAnchor = { UUF_Player:GetPoint() }
				UUF_Player.SCMOriginalWidth = UUF_Player:GetWidth()
				UUF_Player.SCMOriginalHeight = UUF_Player:GetHeight()
			end
			UUF_Player:ClearAllPoints()

			mainAnchor.SetPoint(UUF_Player, "TOPRIGHT", mainAnchor, "TOPLEFT", offset, 0)

			UUF_Player.SCMOffset = offset
			UUF_Player.SCMHeight = rowConfig[1].size
			UUF_Player.SCMAnchor = mainAnchor
			UUF_Player.SCMCustomAnchor = true

			UUF_Player:SetHeight(rowConfig[1].size)
			UUF_Player_HealthBar:SetHeight(rowConfig[1].size - 2)
			UUF_Player_HealthBackground:SetHeight(rowConfig[1].size - 2)

			if not UUF_Player.SCMHook then
				UUF_Player.SCMHook = true
				hooksecurefunc(UUF_Player, "SetPoint", function(self)
					if options.anchorUUF and options.anchorUUFRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
						self.SCMAnchor.SetPoint(self, "TOPRIGHT", self.SCMAnchor, "TOPLEFT", self.SCMOffset, 0)
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBackground, self.SCMHeight - 2)
					end
				end)

				hooksecurefunc(UUF_Player, "SetSize", function(self)
					if options.anchorUUF and options.anchorUUFRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBackground, self.SCMHeight - 2)
					end
				end)
			end
		elseif UUF_Player.SCMCustomAnchor then
			UUF_Player:ClearAllPoints()
			UUF_Player.SCMAnchor.SetPoint(UUF_Player, unpack(UUF_Player.SCMOriginalAnchor))
			UUF_Player.SCMAnchor.SetHeight(UUF_Player, UUF_Player.SCMOriginalHeight)
			UUF_Player.SCMAnchor.SetHeight(UUF_Player_HealthBar, UUF_Player.SCMOriginalHeight - 2)
			UUF_Player.SCMAnchor.SetHeight(UUF_Player_HealthBackground, UUF_Player.SCMOriginalHeight - 2)

			UUF_Player.SCMCustomAnchor = nil
			UUF_Player.SCMOffset = nil
			UUF_Player.SCMHeight = nil
			UUF_Player.SCMAnchor = nil
			UUF_Player.SCMOriginalHeight = nil
			UUF_Player.SCMOriginalAnchor = nil
		end
	end

	if UUF_Target then
		if options.anchorUUF and options.anchorUUFRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
			if not UUF_Target.SCMOriginalAnchor then
				UUF_Target.SCMOriginalAnchor = { UUF_Target:GetPoint() }
				UUF_Target.SCMOriginalWidth = UUF_Target:GetWidth()
				UUF_Target.SCMOriginalHeight = UUF_Target:GetHeight()
			end

			UUF_Target:ClearAllPoints()
			mainAnchor.SetPoint(UUF_Target, "TOPLEFT", mainAnchor, "TOPRIGHT", -offset, 0)

			UUF_Target.SCMOffset = -offset
			UUF_Target.SCMHeight = rowConfig[1].size
			UUF_Target.SCMAnchor = mainAnchor
			UUF_Target.SCMCustomAnchor = true

			UUF_Target:SetHeight(rowConfig[1].size)
			UUF_Target_HealthBar:SetHeight(rowConfig[1].size - 2)
			UUF_Target_HealthBackground:SetHeight(rowConfig[1].size - 2)

			if not UUF_Target.SCMHook then
				UUF_Target.SCMHook = true
				hooksecurefunc(UUF_Target, "SetPoint", function(self)
					if options.anchorUUF and options.anchorUUFRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
						self.SCMAnchor.SetPoint(self, "TOPLEFT", self.SCMAnchor, "TOPRIGHT", self.SCMOffset, 0)
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBackground, self.SCMHeight - 2)
					end
				end)

				hooksecurefunc(UUF_Target, "SetSize", function(self)
					if options.anchorUUF and options.anchorUUFRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBackground, self.SCMHeight - 2)
					end
				end)
			end
		elseif UUF_Target.SCMCustomAnchor then
			UUF_Target:ClearAllPoints()
			UUF_Target.SCMAnchor.SetPoint(UUF_Target, unpack(UUF_Target.SCMOriginalAnchor))
			UUF_Target.SCMAnchor.SetHeight(UUF_Target, UUF_Target.SCMOriginalHeight)
			UUF_Target.SCMAnchor.SetHeight(UUF_Target_HealthBar, UUF_Target.SCMOriginalHeight - 2)
			UUF_Target.SCMAnchor.SetHeight(UUF_Target_HealthBackground, UUF_Target.SCMOriginalHeight - 2)

			UUF_Target.SCMCustomAnchor = nil
			UUF_Target.SCMOffset = nil
			UUF_Target.SCMHeight = nil
			UUF_Target.SCMAnchor = nil
			UUF_Target.SCMOriginalHeight = nil
			UUF_Target.SCMOriginalAnchor = nil
		end
	end

	if ElvUF_Player then
		if options.anchorElVUI and options.anchorElVUIRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
			if not ElvUF_Player.SCMOriginalAnchor then
				ElvUF_Player.SCMOriginalAnchor = { ElvUF_Player:GetPoint() }
				ElvUF_Player.SCMOriginalWidth = ElvUF_Player:GetWidth()
				ElvUF_Player.SCMOriginalHeight = ElvUF_Player:GetHeight()
			end

			ElvUF_Player:ClearAllPoints()
			mainAnchor.SetPoint(ElvUF_Player, "TOPRIGHT", mainAnchor, "TOPLEFT", offset, 0)

			ElvUF_Player.SCMOffset = offset
			ElvUF_Player.SCMHeight = rowConfig[1].size
			ElvUF_Player.SCMAnchor = mainAnchor

			ElvUF_Player:SetHeight(rowConfig[1].size)
			ElvUF_Player_HealthBar:SetHeight(rowConfig[1].size - 2)
			--ElvUF_Player_HealthBackground:SetHeight(rowConfig[1].size - 2)

			if not ElvUF_Player.SCMHook then
				ElvUF_Player.SCMHook = true
				hooksecurefunc(ElvUF_Player, "SetPoint", function(self)
					if options.anchorElvUF then
						self.SCMAnchor.SetPoint(self, "TOPRIGHT", self.SCMAnchor, "TOPLEFT", self.SCMOffset, 0)
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(ElvUF_Player_HealthBar, self.SCMHeight - 2)
					end
				end)

				hooksecurefunc(ElvUF_Player, "SetSize", function(self)
					if options.anchorElvUF then
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(ElvUF_Player_HealthBar, self.SCMHeight - 2)
					end
				end)
			end
		elseif ElvUF_Player.SCMCustomAnchor then
			ElvUF_Player:ClearAllPoints()
			ElvUF_Player.SCMAnchor.SetPoint(ElvUF_Player, unpack(ElvUF_Player.SCMOriginalAnchor))
			ElvUF_Player.SCMAnchor.SetHeight(ElvUF_Player, ElvUF_Player.SCMOriginalHeight)
			ElvUF_Player.SCMAnchor.SetHeight(ElvUF_Player_HealthBar, ElvUF_Player.SCMOriginalHeight - 2)

			ElvUF_Player.SCMCustomAnchor = nil
			ElvUF_Player.SCMOffset = nil
			ElvUF_Player.SCMHeight = nil
			ElvUF_Player.SCMAnchor = nil
			ElvUF_Player.SCMOriginalHeight = nil
			ElvUF_Player.SCMOriginalAnchor = nil
		end
	end

	if ElvUF_Target then
		if options.anchorElVUI and options.anchorElVUIRoles[(select(5, GetSpecializationInfo(GetSpecialization())))] then
			if not ElvUF_Target.SCMOriginalAnchor then
				ElvUF_Target.SCMOriginalAnchor = { ElvUF_Target:GetPoint() }
				ElvUF_Target.SCMOriginalWidth = ElvUF_Target:GetWidth()
				ElvUF_Target.SCMOriginalHeight = ElvUF_Target:GetHeight()
			end

			ElvUF_Target:ClearAllPoints()
			mainAnchor.SetPoint(ElvUF_Target, "TOPLEFT", mainAnchor, "TOPRIGHT", -offset, 0)

			ElvUF_Target.SCMOffset = -offset
			ElvUF_Target.SCMHeight = rowConfig[1].size
			ElvUF_Target.SCMAnchor = mainAnchor

			ElvUF_Target:SetHeight(rowConfig[1].size)
			ElvUF_Target_HealthBar:SetHeight(rowConfig[1].size - 2)
			--ElvUF_Target_HealthBackground:SetHeight(rowConfig[1].size - 2)

			if not ElvUF_Target.SCMHook then
				ElvUF_Target.SCMHook = true
				hooksecurefunc(ElvUF_Target, "SetPoint", function(self)
					if options.anchorElvUF then
						self.SCMAnchor.SetPoint(self, "TOPLEFT", self.SCMAnchor, "TOPRIGHT", self.SCMOffset, 0)
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(ElvUF_Target_HealthBar, self.SCMHeight - 2)
					end
				end)

				hooksecurefunc(ElvUF_Target, "SetSize", function(self)
					if options.anchorElvUF then
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(ElvUF_Target_HealthBar, self.SCMHeight - 2)
					end
				end)
			end
		elseif ElvUF_Target.SCMCustomAnchor then
			ElvUF_Target:ClearAllPoints()
			ElvUF_Target.SCMAnchor.SetPoint(ElvUF_Target, unpack(ElvUF_Target.SCMOriginalAnchor))
			ElvUF_Target.SCMAnchor.SetHeight(ElvUF_Target, ElvUF_Target.SCMOriginalHeight)
			ElvUF_Target.SCMAnchor.SetHeight(ElvUF_Target_HealthBar, ElvUF_Target.SCMOriginalHeight - 2)

			ElvUF_Target.SCMCustomAnchor = nil
			ElvUF_Target.SCMOffset = nil
			ElvUF_Target.SCMHeight = nil
			ElvUF_Target.SCMAnchor = nil
			ElvUF_Target.SCMOriginalHeight = nil
			ElvUF_Target.SCMOriginalAnchor = nil
		end
	end
end

function SCM:ApplyCustomAnchors(maxGroupWidth, rowConfig)
	for frame, options in pairs(self.CustomAnchors) do
		frame = type(frame) == "string" and _G[frame] or frame
		if frame and type(frame) == "table" and options.anchorIndex and options.xOffset and options.yOffset then
			if not frame.SCMHook then
				frame.SCMHook = true
				frame.OriginalClearAllPoints = frame.ClearAllPoints
				frame.OriginalSetPoint = frame.SetPoint
				frame.ClearAllPoints = nop
				frame.SetPoint = nop

				if options.setWidth then
					frame.OriginalSetWidth = frame.SetWidth
					frame.SetWidth = nop
				end
			end

			frame:OriginalClearAllPoints()
			local point = options.point
			local anchorRef = options.anchorFrame
			local relativePoint = options.relativePoint
			local xOffset = options.xOffset
			local yOffset = options.yOffset

			if point and anchorRef and relativePoint then
				local setPoint = frame.OriginalSetPoint
				local anchorRefType = type(anchorRef)
				local isAnchorList = anchorRefType == "table"

				if isAnchorList then
					for i = 1, #anchorRef do
						local ref = anchorRef[i]
						local anchor
						local anchorIndex = tonumber(ref)
						if anchorIndex then
							anchor = SCM:GetAnchor(anchorIndex)
						else
							local refType = type(ref)
							if refType == "string" then
								anchor = _G[ref]
							elseif refType == "table" then
								anchor = ref
							end
						end

						if anchor and anchor:IsVisible() then
							setPoint(frame, point, anchor, relativePoint, xOffset, yOffset)
							break
						end
					end
				else
					local anchor
					local anchorIndex = tonumber(anchorRef)
					if anchorIndex then
						anchor = SCM:GetAnchor(anchorIndex)
					elseif anchorRefType == "string" then
						anchor = _G[anchorRef]
					elseif anchorRefType == "table" then
						anchor = anchorRef
					end

					if anchor and anchor:IsVisible() then
						setPoint(frame, point, anchor, relativePoint, xOffset, yOffset)
						break
					end
				end
			else
				frame:OriginalSetPoint("BOTTOM", SCM:GetAnchor(options.anchorIndex), "TOP", options.xOffset, options.yOffset)
			end

			if options.setWidth then
				frame:OriginalSetWidth(max(200, maxGroupWidth - (options.widthOffset or 0)))
			end
		end
	end
end

function SCM:ApplyEssentialCDManagerConfig()
	if C_CVar.GetCVar("cooldownViewerEnabled") == "1" then
		if SCM.currentConfig then
			OrderCDManagerSpells(false, SCM.currentConfig)
		end
	end
end

function SCM:ApplyUtilityCDManagerConfig()
	if SCM.currentConfig then
		OrderCDManagerSpells(false, SCM.currentConfig)
	end
end

function SCM:ApplyBuffIconCDManagerConfig()
	if SCM.currentConfig then
		OrderCDManagerSpells(true, SCM.currentConfig)
	end
end

function SCM:ApplyAllCDManagerConfigs()
	if C_CVar.GetCVar("cooldownViewerEnabled") == "1" and SCM.currentConfig then
		OrderCDManagerSpells(false, SCM.currentConfig)
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

function SCM:UpdateDB()
	local class = UnitClassBase("player")
	local specID = GetSpecializationInfo(GetSpecialization())

	local currentConfig = self.DB:LoadData()
	local specAnchorConfig = currentConfig and currentConfig.anchorConfig[specID]
	local specSpellConfig = currentConfig and currentConfig.spellConfig[specID]
	local itemConfig = currentConfig and currentConfig.itemConfig and currentConfig.itemConfig[specID]
	local customConfig = currentConfig and currentConfig.customConfig and currentConfig.customConfig[specID]

	self.db.profile[class] = self.db.profile[class] or {}
	self.db.profile[class][specID] = self.db.profile[class][specID]
		or {
			anchorConfig = CopyTable(specAnchorConfig or self.DB.defaultAnchorConfig),
			itemConfig = itemConfig or {},
			spellConfig = specSpellConfig or {},
			customConfig = customConfig or {},
		}

	self.currentConfig = self.db.profile[class][specID]
	self.currentConfig.customConfig = self.currentConfig.customConfig or {}
	self.anchorConfig = self.currentConfig.anchorConfig
	self.spellConfig = self.currentConfig.spellConfig
	self.itemConfig = self.currentConfig.itemConfig
	self.customConfig = self.currentConfig.customConfig
	self.globalAnchorConfig = self.db.global.globalAnchorConfig or {}
	self.globalCustomConfig = self.db.global.globalCustomConfig or {}
end

local function OnEssentialCooldownViewerLayout()
	SCM:ApplyEssentialCDManagerConfig()
end

local function OnUtilityCooldownViewerLayout()
	SCM:ApplyUtilityCDManagerConfig()
end

local function OnBuffCooldownViewerLayout()
	SCM:ApplyBuffIconCDManagerConfig()
end

local function OnCooldownViewerSettingsRefreshLayout(self)
	wipe(cachedChildrenTbl)
	SCM:UpdateCooldownInfo(true, self:GetDataProvider())
	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()
end

local pendingCustomGlowChildren = {}

local function StartPendingCustomGlows()
	for child in pairs(pendingCustomGlowChildren) do
		pendingCustomGlowChildren[child] = nil
		if child and child.SCMActiveGlow then
			SCM:StartCustomGlow(child)
		end
	end
end

local function OnSpellAlertManagerShowAlert(_, child)
	local options = SCM.db.global.options
	if not child.SCMConfig or not options.useCustomGlow or child.SCMActiveGlow then
		return
	end

	child.SCMActiveGlow = true
	child.SpellActivationAlert:Hide()
	pendingCustomGlowChildren[child] = true
	RunNextFrame(StartPendingCustomGlows)
end

local function OnSpellAlertManagerHideAlert(_, child)
	if child.SCMConfig and child.SCMActiveGlow then
		child.SCMActiveGlow = nil
		SCM:StopCustomGlow(child)
	end
end

function SCM:SetHooks()
	hooksecurefunc(EssentialCooldownViewer, "Layout", OnEssentialCooldownViewerLayout)
	hooksecurefunc(UtilityCooldownViewer, "Layout", OnUtilityCooldownViewerLayout)
	hooksecurefunc(BuffIconCooldownViewer, "Layout", OnBuffCooldownViewerLayout)
	hooksecurefunc(CooldownViewerSettings, "RefreshLayout", OnCooldownViewerSettingsRefreshLayout)

	if ActionButtonSpellAlertManager then
		hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", OnSpellAlertManagerShowAlert)
		hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", OnSpellAlertManagerHideAlert)
	end
end

function SCM:PLAYER_ENTERING_WORLD(isInitialLogin, isReload)
	if isInitialLogin or isReload then
		SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
		SCM:UpdateDB()

		SCM:ApplyAllCDManagerConfigs()
		SCM:SetHooks()
	elseif self.isInInstance ~= IsInInstance() then
		SCM:ApplyAllCDManagerConfigs()
	end

	self.isInInstance = IsInInstance()
end

function SCM:BAG_UPDATE_DELAYED()
	SCM:ApplyAllCDManagerConfigs()
end

local function SetCooldownVisual(frame, start, duration)
	if start and start > 0 then
		frame.Cooldown:SetCooldown(start, duration)
		frame.Icon:SetDesaturated(true)
		return true
	end

	frame.Cooldown:Clear()
	frame.Icon:SetDesaturated(false)
	return false
end

local function UpdateBagCooldownFrames()
	local GetItemCooldown = C_Item.GetItemCooldown

	for _, frame in pairs(SCM.itemFrames) do
		local start, duration = GetItemCooldown(frame.itemID)
		SetCooldownVisual(frame, start, duration)
	end

	CustomIcons.UpdateBagIcons(SetCooldownVisual, SetChildVisibilityState)
end

function SCM:BAG_UPDATE_COOLDOWN()
	RunNextFrame(UpdateBagCooldownFrames)
end

function SCM:PLAYER_EQUIPMENT_CHANGED()
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:PLAYER_REGEN_ENABLED()
	if not self.appliedOptions then
		self:ApplyOptions()
	end

	SCM:ApplyAllCDManagerConfigs()
end

function SCM:PLAYER_REGEN_DISABLED() end

function SCM:EDIT_MODE_LAYOUTS_UPDATED()
	SCM:ApplyOptions()
end

local function RefreshCooldownViewerData()
	wipe(cachedViewerChildren)
	SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:TRAIT_CONFIG_UPDATED()
	C_Timer.After(0.2, RefreshCooldownViewerData)
end

function SCM:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
	C_Timer.After(0.2, RefreshCooldownViewerData)
end

local function OnProfileChanged(_, _, _, skipReset)
	-- Hopefully players won't change profiles that much that we reach the frame limit :)
	if not skipReset then
		SCM.DB:ResetData()
	end

	SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()

	if SCM.OptionsFrame and SCM.OptionsFrame:IsShown() and SCM.db.global.options.showAnchorHighlight then
		for _, anchorFrame in pairs(SCM.anchorFrames) do
			anchorFrame.debugTexture:Show()
			anchorFrame.debugText:Show()
		end
	end
end

function SCM:LoadNewProfile()
	OnProfileChanged(nil, nil, nil, true)
end

function SCM:PixelPerfect()
	local screenHeight = select(2, GetPhysicalScreenSize())
	local scale = UIParent:GetEffectiveScale()
	return (768 / screenHeight) / scale
end

local function OnEventFrameEvent(_, event, ...)
	if SCM[event] then
		SCM[event](SCM, ...)
	end
end

local function OnSCMAddonLoaded()
	SCM.db = LibStub("AceDB-3.0"):New(addonName .. "DB", SCM.DefaultDB, true)
	SCM.db.RegisterCallback(SCM, "OnProfileChanged", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileCopied", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileReset", OnProfileChanged)

	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
	eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
	eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
	eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	eventFrame:SetScript("OnEvent", OnEventFrameEvent)
end

EventUtil.ContinueOnAddOnLoaded(addonName, OnSCMAddonLoaded)
