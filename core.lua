local addonName, SCM = ...
SCM.anchorFrames = {}
SCM.itemFrames = {}
SCM.customIconFrames = {}
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

local function ToGlobalGroup(index)
	return 100 + (index or 1)
end

local function GetAnchorConfigForGroup(config, group)
	if config and config.anchorConfig and config.anchorConfig[group] then
		return config.anchorConfig[group]
	end

	if SCM.globalAnchorConfig and group >= 100 then
		return SCM.globalAnchorConfig[group - 100]
	end
end

local function SortBySCMOrder(a, b)
	return (a.SCMOrder or 0) < (b.SCMOrder or 0)
end

function SCM:Debug(...)
	if self.db.global.options.debug then
		print(addonName, ...)
	end
end

local function ApplyHideChildNow(child)
	child.SCMHidden = true
	UIParent.SetAlpha(child, 0)
	child:EnableMouse(false)
	SCM:Debug("HIDE", GetTime(), child.SCMSpellID or "unknown", child.SCMCooldownID or "unknown")

	if not child.SCMAlphaHook then
		child.SCMAlphaHook = true
		hooksecurefunc(child, "SetAlpha", function(self)
			UIParent.SetAlpha(self, self.SCMHidden and 0 or 1)
		end)
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
			child.SCMHideTimer = nil
			if child.viewerFrame and not child.SCMHidden then
				ApplyHideChildNow(child)
			end
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

local function UpdateChildDesaturation(child, shouldDesaturate)
	if child.Icon and child.SCMConfig and child.SCMSpellID and not SCM.db.global.options.testSetting[child.SCMSpellID] then
		if child.SCMConfig.desaturate then
			child.Icon:SetDesaturated(shouldDesaturate)
		else
			child.Icon:SetDesaturated(false)
		end
	end
end

local function SetupChildHooks(child)
	if child.SCMShowHook or child == UIParent then
		return
	end
	child.SCMShowHook = true

	child:HookScript("OnShow", function(self)
		UIParent.SetAlpha(self, self.SCMHidden and 0 or 1)
		SCM:ApplyAllCDManagerConfigs()
	end)

	child:HookScript("OnHide", function(self)
		SCM:ApplyAllCDManagerConfigs()
	end)
end

local function SetupBuffIconHooks(child, options)
	if child.SCMShowHook then
		return
	end

	SetupChildHooks(child)

	hooksecurefunc(child.Cooldown, "SetCooldown", function(self)
		local parent = self:GetParent()
		if parent and parent.SCMConfig then
			ShowChild(parent)
			UpdateChildDesaturation(parent, false)
			SCM:ApplyAllCDManagerConfigs()
		end
	end)

	local function HandleCooldownEnd(self)
		if not options.hideBuffsWhenInactive then
			return
		end

		local parent = self:GetParent()
		if not parent or not parent.SCMConfig then
			return
		end

		if not parent.SCMConfig.alwaysShow then
			SCM:ApplyAllCDManagerConfigs()
		else
			UpdateChildDesaturation(parent, true)
		end
	end

	hooksecurefunc(child.Cooldown, "Clear", HandleCooldownEnd)
	child.Cooldown:HookScript("OnCooldownDone", HandleCooldownEnd)
	hooksecurefunc(child, "TriggerPandemicAlert", function(self)
		if options.pandemicGlowOption ~= "keepPandemicGlow" then
			child.SCMPandemic = true
		end
	end)

	hooksecurefunc(child, "ShowPandemicStateFrame", function(self)
		if self.PandemicIcon and self.PandemicIcon:GetAlpha() ~= 0 then
			self.PandemicIcon:SetAlpha(0)

			if options.pandemicGlowOption == "replacePandemicGlow" then
				RunNextFrame(function()
					SCM:StartCustomGlow(self)
				end)
			end
		end
	end)

	hooksecurefunc(child, "HidePandemicStateFrame", function(self)
		if self.SCMPandemic and options.pandemicGlowOption == "replacePandemicGlow" then
			SCM:StopCustomGlow(self)
			self.SCMPandemic = nil
		end
	end)
end

local function ProcessBuffIcon(child, childData, validChildren, group, options)
	SetupBuffIconHooks(child, options)

	local isActive = child:IsActive()
	local isInactive = not child.Cooldown:IsShown()
	--if not issecretvalue(child.Icon:GetTexture()) then
	--	--isInactive = false
	--end
	local forceShow = SCM.simulateBuffs or childData.alwaysShow

	local shouldHide = options.hideBuffsWhenInactive and isInactive and not forceShow

	if shouldHide then
		child.SCMShouldBeVisible = false
		HideChild(child)
		return
	end

	child.SCMShouldBeVisible = true
	ShowChild(child)
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

local function SetupRegularIconHooks(child)
	if child.SCMRegularCooldownHook or not child.Cooldown then
		return
	end

	child.SCMRegularCooldownHook = true
	SetupChildHooks(child)

	local function HandleRegularCooldownChange(self)
		local parent = self:GetParent()
		if parent and parent.SCMConfig and parent.SCMConfig.hideWhenNotOnCooldown then
			RunNextFrame(function()
				SCM:ApplyAllCDManagerConfigs()
			end)
		end
	end

	hooksecurefunc(child.Cooldown, "SetCooldown", HandleRegularCooldownChange)
	hooksecurefunc(child.Cooldown, "Clear", HandleRegularCooldownChange)
	child.Cooldown:HookScript("OnCooldownDone", HandleRegularCooldownChange)
end

local function ProcessRegularIcon(child, childData)
	SetupRegularIconHooks(child)

	if childData.hideWhenNotOnCooldown and not IsChildOnCooldown(child) then
		child.SCMShouldBeVisible = false
	else
		child.SCMShouldBeVisible = true
	end
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
		child.SCMShouldBeVisible = false
		HideChild(child)
		return
	end

	local childData = spellConfig[spellID]
	local group = childData.source[categoryIndex] or childData.source[SCM.Constants.SourcePairs[categoryIndex]]

	if not group then
		child.SCMShouldBeVisible = false
		HideChild(child)
		return
	end

	validChildren[group] = validChildren[group] or {}
	tinsert(validChildren[group], child)

	child.SCMConfig = childData
	child.SCMOrder = childData.anchorGroup[group].order
	child.SCMCooldownID = cooldownID

	SCM:SkinChild(child, childData)

	if isBuffIcon then
		ProcessBuffIcon(child, childData, validChildren, group, options)
	else
		ProcessRegularIcon(child, childData)
	end
end

local function ProcessChildren(viewer, validChildren, config, isBuffIcon, isOnShow)
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

local function ProcessItemConfig(itemConfig, validChildren)
	for slotID, config in pairs(itemConfig) do
		local itemID = GetInventoryItemID("player", slotID)
		if itemID and C_Item.GetItemSpell(itemID) then
			local frame = SCM.itemFrames[slotID] or CreateFrame("Frame", nil, UIParent, "PermokItemIconTemplate")
			frame:SetScale(cachedViewerScale)

			if not SCM.itemFrames[slotID] then
				frame.Cooldown:SetScript("OnCooldownDone", function()
					frame.Icon:SetDesaturated(false)
				end)
			end
			if not frame.itemID or frame.itemID ~= itemID then
				frame.itemID = itemID
				frame.SCMCooldownID = "i:" .. itemID
				frame.SCMConfig = config
				frame.Icon:SetTexture(C_Item.GetItemIconByID(itemID))

				local item = Item:CreateFromItemID(itemID)
				item:ContinueOnItemLoad(function()
					frame.Icon:SetTexture(item:GetItemIcon())
				end)

				frame.SCMOrder = 100 + slotID
				SCM.itemFrames[slotID] = frame

				local start, duration, enable = GetInventoryItemCooldown("player", slotID)
				if start and start > 0 then
					frame.Cooldown:SetCooldown(start, duration)
					frame.Icon:SetDesaturated(true)
				else
					frame.Icon:SetDesaturated(false)
				end
				frame:Show()
			end

			validChildren[config.anchorGroup or 1] = validChildren[config.anchorGroup or 1] or {}
			tinsert(validChildren[config.anchorGroup or 1], frame)
		elseif SCM.itemFrames[slotID] then
			SCM.itemFrames[slotID]:Hide()
		end
	end
end

local function HideItemIcons()
	for _, itemFrame in pairs(SCM.itemFrames) do
		itemFrame:Hide()
	end
end

local function GetCurveCharges(spellID)
	local charges = 0
	if SCM.GetSpellChargesFromCurve then
		charges = SCM:GetSpellChargesFromCurve(spellID) or 0
	elseif C_Spell and C_Spell.GetSpellCharges then
		local chargeInfo = C_Spell.GetSpellCharges(spellID)
		charges = chargeInfo and chargeInfo.currentCharges or 0
	end
	return charges
end

function SCM:GetSpellChargesFromCurve(spellID)
	if CooldownViewerManager and CooldownViewerManager.GetSecretChargesCurveValue then
		local ok, value = pcall(CooldownViewerManager.GetSecretChargesCurveValue, CooldownViewerManager, spellID)
		if ok and type(value) == "number" then
			return value
		end
	end
end

local function SetCustomIconCountText(frame, iconType, id)
	frame.SpellChargesText:SetText("")
	frame.ItemCountText:SetText("")
	frame.SpellChargesText:Hide()
	frame.ItemCountText:Hide()

	if iconType == "spell" then
		local charges = GetCurveCharges(id)
		if charges and charges > 0 then
			frame.SpellChargesText:SetText(charges)
			frame.SpellChargesText:Show()
		end
	else
		local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, false, false, true) or GetItemCount(id, false, false)
		if count and count > 0 then
			frame.ItemCountText:SetText(count)
			frame.ItemCountText:Show()
		end
	end
end

local function ProcessCustomIcons(iconConfig, validChildren, isGlobal)
	for index, config in ipairs(iconConfig or {}) do
		local frameID = (isGlobal and "global:" or "spec:") .. (config.id or tostring(index))
		local frame = SCM.customIconFrames[frameID] or CreateFrame("Frame", nil, UIParent, "PermokItemIconTemplate")
		SCM.customIconFrames[frameID] = frame
		frame:SetScale(cachedViewerScale)
		frame.SCMConfig = config
		frame.SCMOrder = config.order or index
		frame.SCMCooldownID = frameID
		frame.SCMSpellID = config.spellID

		local iconType = config.iconType or (config.spellID and "spell") or "item"
		local iconTexture
		if iconType == "spell" and config.spellID then
			iconTexture = C_Spell.GetSpellTexture(config.spellID)
			frame.SCMSpellID = config.spellID
		elseif iconType == "item" and config.itemID then
			iconTexture = C_Item.GetItemIconByID(config.itemID)
		end

		if SCM.isOptionsOpen and not iconTexture then
			iconTexture = 134400
		end

		local shouldShow = iconTexture ~= nil
		if shouldShow then
			frame.Icon:SetTexture(iconTexture)
			SetCustomIconCountText(frame, iconType, config.spellID or config.itemID)
			frame:Show()
			SCM:SkinChild(frame, config)
			local anchor = config.anchorGroup or 1
			if isGlobal then
				anchor = ToGlobalGroup(anchor)
			end
			validChildren[anchor] = validChildren[anchor] or {}
			tinsert(validChildren[anchor], frame)
		else
			frame:Hide()
		end
	end
end

local function HideUnusedCustomIcons(specConfig, globalConfig)
	local keep = {}
	for _, cfg in ipairs(specConfig or {}) do
		keep["spec:" .. (cfg.id or "")] = true
	end
	for _, cfg in ipairs(globalConfig or {}) do
		keep["global:" .. (cfg.id or "")] = true
	end

	for id, frame in pairs(SCM.customIconFrames) do
		if not keep[id] then
			frame:Hide()
		end
	end
end

local function OrderCDManagerSpells_Actual()
	cachedViewerScale = 1

	wipe(cachedChildrenTbl)
	wipe(cachedCooldownFrameTbl)

	local config = SCM.currentConfig
	for _, cooldownViewer in ipairs({ EssentialCooldownViewer, UtilityCooldownViewer, BuffIconCooldownViewer }) do
		ProcessChildren(cooldownViewer, cachedChildrenTbl, SCM.currentConfig, cooldownViewer == BuffIconCooldownViewer)
	end

	for group, children in pairs(cachedChildrenTbl) do
		cachedVisibleChildren[group] = cachedVisibleChildren[group] or {}
		local visibleChildren = cachedVisibleChildren[group]
		wipe(visibleChildren)
		for _, child in ipairs(children) do
			--if child:IsShown() and child:GetAlpha() > 0 then
			if child.SCMShouldBeVisible then
				table.insert(visibleChildren, child)
			end
			--end
		end

		cachedCooldownFrameTbl[group] = visibleChildren
	end

	if SCM.itemConfig and next(SCM.itemConfig) then
		ProcessItemConfig(SCM.itemConfig, cachedCooldownFrameTbl)
	else
		HideItemIcons()
	end

	ProcessCustomIcons(SCM.customIcons, cachedCooldownFrameTbl, false)
	ProcessCustomIcons(SCM.globalCustomIcons, cachedCooldownFrameTbl, true)
	HideUnusedCustomIcons(SCM.customIcons, SCM.globalCustomIcons)

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
					hooksecurefunc(child, "SetSize", function(s)
						groupAnchor.SetSize(s, s.width, s.height)
					end)
					hooksecurefunc(child, "SetWidth", function(s)
						groupAnchor.SetWidth(s, s.width)
					end)
					hooksecurefunc(child, "SetHeight", function(s)
						groupAnchor.SetHeight(s, s.height)
					end)
				end

				if not child.SCMPointHook then
					child.SCMPointHook = true

					hooksecurefunc(child, "SetPoint", function(s)
						local anchorData = s.SCMAnchorData
						if anchorData then
							groupAnchor.ClearAllPoints(s)
							groupAnchor.SetPoint(s, anchorData[1], anchorData[2], anchorData[3], anchorData[4], anchorData[5])
						end
					end)

					hooksecurefunc(child, "ClearAllPoints", function(s)
						local anchorData = s.SCMAnchorData
						if anchorData then
							groupAnchor.ClearAllPoints(s)
							groupAnchor.SetPoint(s, anchorData[1], anchorData[2], anchorData[3], anchorData[4], anchorData[5])
						end
					end)
				end

				local anchorData = child.SCMAnchorData or {}
				child.SCMAnchorData = anchorData
				if anchorData[1] ~= startPoint or anchorData[2] ~= groupAnchor or anchorData[3] ~= startPoint or anchorData[4] ~= offsetX or anchorData[5] ~= offsetY then
					anchorData[1] = startPoint
					anchorData[2] = groupAnchor
					anchorData[3] = startPoint
					anchorData[4] = offsetX
					anchorData[5] = offsetY
					groupAnchor.ClearAllPoints(child)
					groupAnchor.SetPoint(child, anchorData[1], anchorData[2], anchorData[3], anchorData[4], anchorData[5])
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
					if not SCM.registeredCustomFrame and SCRB and SCRB.registeredCustomFrame then
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
			if not child.SCMShouldBeVisible then
				HideChild(child)
			else
				ShowChild(child)
			end
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
				if not SCM.registeredCustomFrame and SCRB and SCRB.registeredCustomFrame then
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

	C_Timer.After(0, function()
		isThrottled = false

		if hasPendingUpdate then
			hasPendingUpdate = false
			OrderCDManagerSpells_Actual()
		end
	end)
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
		anchorFrame.debugText:SetText(group)
		anchorFrame.debugText:SetFontHeight(35)
		anchorFrame.debugText:SetShown(self.OptionsFrame ~= nil)
		anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)

		anchorFrame.debugTexture:HookScript("OnShow", function(self)
			anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
			LibCustomGlow.PixelGlow_Start(anchorFrame, nil, nil, nil, nil, nil, nil, nil, nil, "SCM")
		end)

		anchorFrame.debugTexture:HookScript("OnHide", function(self)
			self.isGlowActive = false
			LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
		end)

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

function SCM:UpdateResourceBarWidth(maxGroupWidth)
	for _, resourceBarName in ipairs(SCM.db.global.options.resourceBars) do
		local resourceBar = _G[resourceBarName]
		if resourceBar and resourceBar:IsShown() then
			resourceBar.SCMWidth = max(200, maxGroupWidth)
			resourceBar:SetWidth(max(200, maxGroupWidth))

			if not resourceBar.SCMHook then
				resourceBar.SCMHook = true
				hooksecurefunc(resourceBar, "SetWidth", function(self, width)
					UIParent.SetWidth(self, self.SCMWidth)
				end)

				hooksecurefunc(resourceBar, "SetSize", function(self, width, height)
					UIParent.SetWidth(self, self.SCMWidth)
				end)
			end
		end
	end
end

function SCM:UpdateUUFValues(options, maxGroupWidth, rowConfig)
	if options.anchorUUF then
		local offset = min((maxGroupWidth - 150), 0)
		local mainAnchor = SCM:GetAnchor(1)
		if UUF_Player then
			UUF_Player:ClearAllPoints()
			mainAnchor.SetPoint(UUF_Player, "TOPRIGHT", mainAnchor, "TOPLEFT", offset, 0)

			UUF_Player.SCMOffset = offset
			UUF_Player.SCMHeight = rowConfig[1].size
			UUF_Player.SCMAnchor = mainAnchor

			UUF_Player:SetHeight(rowConfig[1].size)
			UUF_Player_HealthBar:SetHeight(rowConfig[1].size - 2)
			UUF_Player_HealthBackground:SetHeight(rowConfig[1].size - 2)

			if not UUF_Player.SCMHook then
				UUF_Player.SCMHook = true
				hooksecurefunc(UUF_Player, "SetPoint", function(self)
					if options.anchorUUF then
						self.SCMAnchor.SetPoint(self, "TOPRIGHT", self.SCMAnchor, "TOPLEFT", self.SCMOffset, 0)
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBackground, self.SCMHeight - 2)
					end
				end)

				hooksecurefunc(UUF_Player, "SetSize", function(self)
					if options.anchorUUF then
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Player_HealthBackground, self.SCMHeight - 2)
					end
				end)
			end
		end

		if UUF_Target then
			UUF_Target:ClearAllPoints()
			mainAnchor.SetPoint(UUF_Target, "TOPLEFT", mainAnchor, "TOPRIGHT", -offset, 0)

			UUF_Target.SCMOffset = -offset
			UUF_Target.SCMHeight = rowConfig[1].size
			UUF_Target.SCMAnchor = mainAnchor

			UUF_Target:SetHeight(rowConfig[1].size)
			UUF_Target_HealthBar:SetHeight(rowConfig[1].size - 2)
			UUF_Target_HealthBackground:SetHeight(rowConfig[1].size - 2)

			if not UUF_Target.SCMHook then
				UUF_Target.SCMHook = true
				hooksecurefunc(UUF_Target, "SetPoint", function(self)
					if options.anchorUUF then
						self.SCMAnchor.SetPoint(self, "TOPLEFT", self.SCMAnchor, "TOPRIGHT", self.SCMOffset, 0)
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBackground, self.SCMHeight - 2)
					end
				end)

				hooksecurefunc(UUF_Target, "SetSize", function(self)
					if options.anchorUUF then
						self.SCMAnchor.SetHeight(self, self.SCMHeight)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBar, self.SCMHeight - 2)
						self.SCMAnchor.SetHeight(UUF_Target_HealthBackground, self.SCMHeight - 2)
					end
				end)
			end
		end
	end
end

function SCM:ApplyCustomAnchors(maxGroupWidth, rowConfig)
	for frame, options in pairs(self.CustomAnchors) do
		frame = type(frame) == "string" and _G[frame] or frame
		if frame and options.anchorIndex and options.xOffset and options.yOffset then
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
			frame:OriginalSetPoint("BOTTOM", SCM:GetAnchor(options.anchorIndex), "TOP", options.xOffset, options.yOffset)

			if options.setWidth then
				frame:OriginalSetWidth(max(200, maxGroupWidth))
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
	local customIcons = currentConfig and currentConfig.customIcons and currentConfig.customIcons[specID]

	self.db.profile[class] = self.db.profile[class] or {}
	self.db.profile[class][specID] = self.db.profile[class][specID]
		or {
			anchorConfig = CopyTable(specAnchorConfig or self.DB.defaultAnchorConfig),
			itemConfig = itemConfig or {},
			spellConfig = specSpellConfig or {},
			customIcons = customIcons or {},
		}

	self.currentConfig = self.db.profile[class][specID]
	self.currentConfig.customIcons = self.currentConfig.customIcons or {}
	self.anchorConfig = self.currentConfig.anchorConfig
	self.spellConfig = self.currentConfig.spellConfig
	self.itemConfig = self.currentConfig.itemConfig
	self.customIcons = self.currentConfig.customIcons
	self.globalAnchorConfig = self.db.global.globalAnchorConfig or {}
	self.globalCustomIcons = self.db.global.globalCustomIcons or {}
end

function SCM:SetHooks()
	hooksecurefunc(EssentialCooldownViewer, "Layout", function()
		SCM:ApplyEssentialCDManagerConfig()
	end)

	hooksecurefunc(UtilityCooldownViewer, "Layout", function()
		SCM:ApplyUtilityCDManagerConfig()
	end)

	hooksecurefunc(BuffIconCooldownViewer, "Layout", function()
		SCM:ApplyBuffIconCDManagerConfig()
	end)

	hooksecurefunc(CooldownViewerSettings, "RefreshLayout", function(self)
		wipe(cachedChildrenTbl)

		SCM:UpdateCooldownInfo(true, self:GetDataProvider())
		SCM:UpdateDB()
		SCM:ApplyAllCDManagerConfigs()
	end)

	if ActionButtonSpellAlertManager then
		local options = self.db.global.options
		hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, child)
			if child.SCMConfig and options.useCustomGlow and not child.SCMActiveGlow then
				child.SCMActiveGlow = true
				child.SpellActivationAlert:Hide()
				RunNextFrame(function()
					SCM:StartCustomGlow(child)
				end)
			end
		end)

		hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, child)
			if child.SCMConfig and child.SCMActiveGlow then
				child.SCMActiveGlow = nil
				SCM:StopCustomGlow(child)
			end
		end)
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

function SCM:BAG_UPDATE_COOLDOWN()
	RunNextFrame(function()
		for _, frame in pairs(SCM.itemFrames) do
			local start, duration, enable = C_Item.GetItemCooldown(frame.itemID)
			if start and start > 0 then
				frame.Cooldown:SetCooldown(start, duration)
				frame.Icon:SetDesaturated(true)
			else
				frame.Cooldown:Clear()
				frame.Icon:SetDesaturated(false)
			end
		end
	end)
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

function SCM:TRAIT_CONFIG_UPDATED()
	C_Timer.After(0.2, function()
		wipe(cachedViewerChildren)

		SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
		SCM:UpdateDB()
		SCM:ApplyAllCDManagerConfigs()
	end)
end

function SCM:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
	C_Timer.After(0.2, function()
		wipe(cachedViewerChildren)
		SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
		SCM:UpdateDB()
		SCM:ApplyAllCDManagerConfigs()
	end)
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

EventUtil.ContinueOnAddOnLoaded(addonName, function()
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
	eventFrame:SetScript("OnEvent", function(_, event, ...)
		if SCM[event] then
			SCM[event](SCM, ...)
		end
	end)
end)
