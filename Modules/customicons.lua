local SCM = select(2, ...)

local CustomIcons = SCM.CustomIcons
local CDM = SCM.CDM
local Icons = SCM.Icons
local GetIconType = SCM.Utils.GetIconType

local CustomItemFrames = {}
local CustomSpellFrames = {}
local CustomIconFramePool

function CustomIcons.GetCustomIconFrames(config)
	local iconType = GetIconType(config)
	if not iconType then
		return
	end

	if iconType == "spell" or iconType == "timer" then
		return CustomSpellFrames
	end

	return CustomItemFrames
end

local function ResetCustomIconFrame(_, frame)
	SCM:StopCustomGlow(frame)

	local customFrames = frame.SCMFrameRegistry
	local frameID = frame.SCMFrameID
	if customFrames and frameID and customFrames[frameID] == frame then
		customFrames[frameID] = nil
	end

	frame.SCMReleased = true
	frame.SCMFrameRegistry = nil
	frame.SCMFrameID = nil
	frame.SCMAnchorFrame = nil
	frame.SCMAnchorData = nil
	frame.SCMConfig = nil
	frame.SCMOrder = nil
	frame.SCMCooldownID = nil
	frame.SCMSpellID = nil
	frame.SCMIconType = nil
	frame.SCMGroup = nil
	frame.SCMGlobal = nil
	frame.SCMShouldBeVisible = nil
	frame.SCMChanged = nil
	frame.SCMHidden = nil
	frame.SCMCustom = nil
	frame.SCMIconTexture = nil
	frame.SCMActiveGlow = nil
	frame.SCMGlowWhileActive = nil
	frame.SCMPandemic = nil
	frame.spellID = nil
	frame.itemID = nil
	frame.slotID = nil
	frame.lastCastStartTime = nil
	frame.UpdateCooldown = nil
	frame.UpdateCharges = nil
	frame.width = nil
	frame.height = nil

	frame:EnableMouse(false)
	frame:SetAlpha(1)
	frame:Hide()
	frame:ClearAllPoints()
	frame.Icon:SetDesaturated(false)
	frame.Icon:SetTexture(nil)
	frame.Cooldown:Clear()
	frame.ChargeCount.Current:SetText("")
	frame.ChargeCount.Current:Hide()
end

local function GetCustomIconFramePool()
	if not CustomIconFramePool then
		CustomIconFramePool = CreateFramePool("Frame", UIParent, "SCMItemIconTemplate", ResetCustomIconFrame)
	end

	return CustomIconFramePool
end

local function OnIconCooldownDone(self)
	local parent = self:GetParent()
	if not parent or parent.SCMReleased or not parent.SCMConfig then
		return
	end

	if parent.Icon then
		parent.Icon:SetDesaturated(false)
	end

	if parent.UpdateCooldown then
		parent.isOnGCD = nil
		parent.UpdateCooldown(parent, parent.SCMIconType, parent.SCMConfig)
	end

	if parent.UpdateCharges then
		parent.UpdateCharges(parent, parent.spellID)
	end

	if parent and parent.SCMGroup then
		SCM:ApplyAnchorGroupCDManagerConfig(parent.SCMGroup, parent.SCMGlobal)
	end
end

local function AcquireCustomIconFrame(customFrames, id)
	local frame = customFrames[id]
	if frame and not frame.SCMReleased then
		return frame
	end

	frame = GetCustomIconFramePool():Acquire()
	frame.SCMReleased = nil
	frame.SCMFrameRegistry = customFrames
	frame.SCMFrameID = id
	customFrames[id] = frame

	if not frame.SCMCustomIconInitialized then
		frame.Cooldown:SetScript("OnCooldownDone", OnIconCooldownDone)
		frame.GCDCooldown:SetScript("OnCooldownDone", OnIconCooldownDone)
		frame.Cooldown:SetCountdownFont("GameFontHighlightHugeOutline")
		frame.SCMCustomIconInitialized = true
	end

	return frame
end

local function ReleaseCustomIconFrame(frame)
	if not frame or frame.SCMReleased then
		return
	end

	Icons.SetChildVisibilityState(frame, false, true)
	GetCustomIconFramePool():Release(frame)
end

local function SetCustomIconCountText(frame, iconType, config)
	frame.ChargeCount.Current:SetText("")
	frame.ChargeCount.Current:Hide()

	if iconType == "spell" or iconType == "slot" or iconType == "timer" then
		return
	end

	local itemID = config.itemID
	if not itemID then
		return
	end

	local count = C_Item.GetItemCount(itemID)
	if not count or count <= 0 then
		return
	end

	frame.ChargeCount.Current:SetText(count)
	frame.ChargeCount.Current:Show()
	return true
end

local desaturationCurve = C_CurveUtil.CreateCurve()
desaturationCurve:SetType(Enum.LuaCurveType.Step)
desaturationCurve:AddPoint(0, 0)
desaturationCurve:AddPoint(0.001, 1)

local function UpdateCustomIconGlow(frame, isActive)
	if not frame or not frame.SCMConfig then
		return
	end

	if frame.SCMConfig.glowWhileActive and isActive then
		if not frame.SCMGlowWhileActive then
			frame.SCMGlowWhileActive = true
			SCM:StartCustomGlow(frame)
		end
	elseif frame.SCMGlowWhileActive then
		frame.SCMGlowWhileActive = nil
		SCM:StopCustomGlow(frame)
	end
end

local function GetActiveCustomTimer(frame, iconType, config, now)
	local duration
	if iconType == "spell" or iconType == "timer" then
		duration = config.duration
	end

	if not duration or duration <= 0 then
		return
	end

	local startTime = frame.lastCastStartTime
	if not startTime then
		return
	end

	if startTime + duration > now then
		return startTime, duration
	end

	frame.lastCastStartTime = nil
end

local function UpdateCustomIconCooldown(frame, iconType, config)
	local now = GetTime()
	local customTimerStart, customTimerDuration = GetActiveCustomTimer(frame, iconType, config, now)
	if customTimerStart then
		frame.Cooldown:SetCooldown(customTimerStart, customTimerDuration)
		frame.Icon:SetDesaturated(false)
		UpdateCustomIconGlow(frame, true)
		return true
	end

	if iconType == "spell" then
		local spellCooldown = C_Spell.GetSpellCooldown(config.spellID)
		if config.showGCD and spellCooldown.isOnGCD then
			frame.GCDCooldown:SetCooldown(spellCooldown.startTime, spellCooldown.duration)
		end

		local durationObject = C_Spell.GetSpellChargeDuration(config.spellID)
		if durationObject then
			frame.Cooldown:SetCooldownFromDurationObject(durationObject)

			if not spellCooldown.isOnGCD then
				frame.Icon:SetDesaturation(C_Spell.GetSpellCooldownDuration(config.spellID):EvaluateRemainingDuration(desaturationCurve))

				local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(frame.Icon:IsDesaturated(), 0, 1)
				frame.Cooldown:SetEdgeColor(1, 1, 1, alpha)
				frame.Cooldown:SetSwipeColor(1, 1, 1, alpha)
				frame.Cooldown:SetReverse(frame.Icon:IsDesaturated())
			end
		else
			durationObject = C_Spell.GetSpellCooldownDuration(config.spellID)
			frame.Cooldown:SetCooldownFromDurationObject(durationObject)
			if not spellCooldown or not spellCooldown.isOnGCD then
				frame.Icon:SetDesaturation(C_CurveUtil.EvaluateColorValueFromBoolean(durationObject:IsZero(), 0, 1))
			end
		end

		local isOnCooldown = frame.Cooldown:IsShown()
		UpdateCustomIconGlow(frame, false)
		return isOnCooldown
	end

	if iconType == "item" then
		local startTime, duration, _, modRate = C_Item.GetItemCooldown(config.itemID)
		if startTime and startTime > 0 then
			if modRate then
				frame.Cooldown:SetCooldown(startTime, duration, modRate)
			else
				frame.Cooldown:SetCooldown(startTime, duration)
			end
			frame.Icon:SetDesaturated(true)
			UpdateCustomIconGlow(frame, false)
			return true
		end
	end

	if iconType == "slot" and config.slotID then
		local startTime, duration = GetInventoryItemCooldown("player", config.slotID)
		if startTime and startTime > 0 then
			frame.Cooldown:SetCooldown(startTime, duration)
			frame.Icon:SetDesaturated(true)
			UpdateCustomIconGlow(frame, false)
			return true
		end
	end

	frame.Cooldown:Clear()
	frame.Icon:SetDesaturated(false)
	UpdateCustomIconGlow(frame, false)
end

local function UpdateCustomIconCharges(frame, spellID)
	if not spellID then
		return
	end

	local chargeInfo = C_Spell.GetSpellCharges(spellID)
	if not chargeInfo then
		frame.ChargeCount.Current:Hide()
		return
	end

	frame.ChargeCount.Current:SetText(C_Spell.GetSpellDisplayCount(spellID))
	frame.ChargeCount.Current:Show()
end

local function DoesItemOrSpellExists(config)
	local iconType = GetIconType(config)
	if iconType == "spell" or iconType == "timer" then
		return config.spellID and C_Spell.DoesSpellExist(config.spellID)
	end

	if iconType == "item" then
		return config.itemID and C_Item.DoesItemExistByID(config.itemID)
	end

	if iconType == "slot" then
		if config.slotID then
			local itemID = GetInventoryItemID("player", config.slotID)
			if itemID then
				return C_Item.DoesItemExistByID(itemID) and C_Item.GetItemSpell(itemID)
			end
		end
	end
end

local function GetItemOrSlotSpellID(config)
	local iconType = GetIconType(config)
	if iconType == "item" then
		return config.itemID and C_Item.DoesItemExistByID(config.itemID) and select(2, C_Item.GetItemSpell(config.itemID))
	end

	if iconType == "slot" then
		if config.slotID then
			local itemID = GetInventoryItemID("player", config.slotID)
			if itemID then
				return C_Item.DoesItemExistByID(itemID) and select(2, C_Item.GetItemSpell(itemID))
			end
		end
	end
end

local function ShouldLoadCustomIcon(config)
	local loadRoles = config.loadRoles
	if loadRoles then
		if not next(loadRoles) then
			return true
		end

		return loadRoles[SCM.currentRole]
	end

	return true
end

local function ResolveCustomIconTexture(config, iconType)
	if (iconType == "spell" or iconType == "timer") and config.spellID then
		return C_Spell.GetSpellTexture(config.spellID)
	end

	if iconType == "item" and config.itemID then
		return C_Item.GetItemIconByID(config.itemID)
	end

	if iconType == "slot" and config.slotID then
		local itemID = GetInventoryItemID("player", config.slotID)
		if itemID then
			return C_Item.GetItemIconByID(itemID)
		end
		return GetInventoryItemTexture("player", config.slotID)
	end
end

local function ShouldShowCustomIcon(config, iconType, hasCount, isOnCooldown)
	if SCM.isOptionsOpen then
		return true
	end

	if iconType == "timer" then
		return isOnCooldown and true or false
	end

	local canShowIcon = iconType == "spell" or iconType == "slot" or hasCount
	return canShowIcon and (not config.hideWhenNotOnCooldown or isOnCooldown)
end

local function ConfigureCustomIconFrame(frame, id, config, viewerScale, anchorGroup, isGlobal)
	frame:SetScale(viewerScale)

	frame.SCMConfig = config
	frame.SCMOrder = config.order
	frame.SCMCooldownID = id
	frame.SCMIconType = GetIconType(config)
	frame.SCMGroup = anchorGroup
	frame.SCMGlobal = isGlobal and true or nil
	frame.SCMCustom = true

	if config.slotID or config.itemID then
		frame.SCMSpellID = GetItemOrSlotSpellID(config) or nil
		config.spellID = frame.SCMSpellID
	else
		frame.SCMSpellID = config.spellID
	end
end

local function UpdateCustomIconFrameState(frame, config)
	local iconType = frame.SCMIconType
	local iconTexture = ResolveCustomIconTexture(config, iconType)
	if not iconTexture then
		iconTexture = 134400
	end

	frame.SCMIconTexture = iconTexture
	frame.Icon:SetTexture(iconTexture)
	frame.UpdateCooldown = UpdateCustomIconCooldown
	frame.UpdateCharges = nil

	if iconType == "spell" then
		local chargeInfo = C_Spell.GetSpellCharges(config.spellID)
		UpdateCustomIconCharges(frame, config.spellID)

		if chargeInfo then
			frame.UpdateCharges = UpdateCustomIconCharges
		end
	else
		frame.ChargeCount.Current:SetText("")
		frame.ChargeCount.Current:Hide()
	end
end

function CustomIcons.HideIcons()
	for _, customFrame in pairs(CustomItemFrames) do
		Icons.SetChildVisibilityState(customFrame, false, true)
	end

	for _, customFrame in pairs(CustomSpellFrames) do
		Icons.SetChildVisibilityState(customFrame, false, true)
	end
end

function CustomIcons.ReleaseIcon(id, config)
	local customFrames = CustomIcons.GetCustomIconFrames(config)
	if customFrames and customFrames[id] then
		ReleaseCustomIconFrame(customFrames[id])
	end
end

function CustomIcons.ReleaseAllIcons()
	for _, customFrame in pairs(CustomItemFrames) do
		ReleaseCustomIconFrame(customFrame)
	end

	for _, customFrame in pairs(CustomSpellFrames) do
		ReleaseCustomIconFrame(customFrame)
	end
end

function CustomIcons.CreateIcons(customConfig, isGlobal)
	local viewerScale = 1

	for id, config in pairs(customConfig) do
		local customFrames = CustomIcons.GetCustomIconFrames(config)
		if customFrames then
			if DoesItemOrSpellExists(config) and ShouldLoadCustomIcon(config) then
				local frame = AcquireCustomIconFrame(customFrames, id)
				ConfigureCustomIconFrame(frame, id, config, viewerScale, config.anchorGroup or 1, isGlobal)
				UpdateCustomIconFrameState(frame, config)
				Icons.SetChildVisibilityState(frame, false, true)
				SCM:SkinChild(frame, config)
			elseif customFrames[id] then
				ReleaseCustomIconFrame(customFrames[id])
			end
		end
	end
end

function CustomIcons.ProcessIcons(customConfig, validChildren, isGlobal)
	for id, config in pairs(customConfig) do
		local anchorGroup = config.anchorGroup or 1
		local customFrames = CustomIcons.GetCustomIconFrames(config)
		if customFrames then
			if customFrames[id] and DoesItemOrSpellExists(config) and ShouldLoadCustomIcon(config) then
				if CDM.IsScopedAnchorGroupAllowed(anchorGroup, isGlobal) then
					local frame = customFrames[id]
					local iconType = frame.SCMIconType
					local iconTexture = ResolveCustomIconTexture(config, iconType)
					if not iconTexture and SCM.isOptionsOpen then
						iconTexture = 134400
					end

					if iconTexture then
						if frame.SCMIconTexture ~= iconTexture then
							frame.SCMIconTexture = iconTexture
							frame.Icon:SetTexture(iconTexture)
						end
						local hasCount = SetCustomIconCountText(frame, iconType, config)
						local isOnCooldown = UpdateCustomIconCooldown(frame, iconType, config)
						local shouldShow = ShouldShowCustomIcon(config, iconType, hasCount, isOnCooldown)

						Icons.SetChildVisibilityState(frame, shouldShow, true)

						if shouldShow then
							if iconType == "spell" then
								UpdateCustomIconCharges(frame, config.spellID)
							end

							CDM.AddChildToScopedGroup(validChildren, anchorGroup, frame, isGlobal)
						end
					else
						Icons.SetChildVisibilityState(frame, false, true)
					end
				end
			elseif customFrames[id] then
				Icons.SetChildVisibilityState(customFrames[id], false, true)
			end
		end
	end
end

function CustomIcons.UpdateIcons(customConfig, key)
	for id, config in pairs(customConfig) do
		if config[key] then
			local customFrames = CustomIcons.GetCustomIconFrames(config)
			if customFrames then
				if customFrames[id] then
					local frame = customFrames[id]
					local iconType = frame.SCMIconType
					UpdateCustomIconCooldown(frame, iconType, config)
				end
			end
		end
	end
end

local function UpdateCountTextForConfigTable(customConfig, spellID)
	for id, config in pairs(customConfig) do
		if not spellID or config.spellID == spellID then
			local frame = CustomItemFrames[id]
			if frame and not frame.SCMReleased then
				SetCustomIconCountText(frame, frame.SCMIconType, config)
			end
		end
	end
end

function CustomIcons.UpdateItemCountText(spellID)
	local customConfig = SCM.customConfig
	if customConfig then
		UpdateCountTextForConfigTable(customConfig.itemConfig, spellID)
	end

	local globalCustomConfig = SCM.globalCustomConfig
	if globalCustomConfig then
		UpdateCountTextForConfigTable(globalCustomConfig.itemConfig, spellID)
	end
end

function SCM:CreateAllCustomIcons()
	for _, config in pairs(self.customConfig) do
		CustomIcons.CreateIcons(config)
	end

	for _, config in pairs(self.globalCustomConfig) do
		CustomIcons.CreateIcons(config, true)
	end
end

function SCM:UpdateCustomIconsGCD()
	for _, config in pairs(self.customConfig) do
		CustomIcons.UpdateIcons(config, "showGCD")
	end

	for _, config in pairs(self.globalCustomConfig) do
		CustomIcons.UpdateIcons(config, "showGCD")
	end
end

function SCM:AddCustomIcon(anchorGroup, iconType, configID, order, uniqueID, isGlobal)
	local configTable = SCM:GetConfigTable(iconType, isGlobal)
	if not configTable then
		return
	end

	uniqueID = uniqueID or SCM:GetUniqueID(configID, iconType, isGlobal)

	if not order then
		order = 1
		for _, entry in pairs(configTable) do
			if entry.anchorGroup == anchorGroup and (entry.order or 0) >= order then
				order = (entry.order or 0) + 1
			end
		end
	end

	configTable[uniqueID] = {
		id = uniqueID,
		iconType = iconType,
		spellID = (iconType == "spell" or iconType == "timer") and configID or nil,
		itemID = iconType == "item" and configID or nil,
		slotID = iconType == "slot" and configID or nil,
		anchorGroup = anchorGroup,
		order = order,
		loadRoles = { ["TANK"] = true, ["HEALER"] = true, ["DAMAGER"] = true },
	}

	CustomIcons.CreateIcons(configTable, isGlobal)

	return uniqueID
end

function SCM:RemoveCustomIcon(id, isGlobal, iconType)
	local configTable = SCM:GetConfigTable(iconType, isGlobal)
	if configTable and configTable[id] then
		local config = configTable[id]
		configTable[id] = nil

		CustomIcons.ReleaseIcon(id, config)
	end
end
