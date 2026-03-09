local SCM = select(2, ...)

SCM.CustomIcons = SCM.CustomIcons or {}
SCM.customIconFrames = SCM.customIconFrames or {}

local CustomIcons = SCM.CustomIcons
local GetIconType = SCM.Utils.GetIconType

local CustomItemFrames = {}
local CustomSpellFrames = {}

function CustomIcons.GetCustomIconFrames(config)
	local iconType = GetIconType(config)
	if iconType == "spell" then
		return CustomSpellFrames
	end

	return CustomItemFrames
end

local function SetCustomIconCountText(frame, iconType, id)
	frame.ChargeCount.Current:SetText("")
	frame.ChargeCount.Current:Hide()

	if iconType == "spell" or iconType == "slot" then
		return
	end

	local count = C_Item.GetItemCount(id)
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

local function UpdateCustomIconCooldown(frame, iconType, config)
	if iconType == "spell" then
		local durationObject = C_Spell.GetSpellChargeDuration(config.spellID)
		if durationObject then
			frame.Cooldown:SetCooldownFromDurationObject(durationObject)
			frame.Icon:SetDesaturation(durationObject:EvaluateRemainingPercent(desaturationCurve))
		else
			durationObject = C_Spell.GetSpellCooldownDuration(config.spellID)
			frame.Cooldown:SetCooldownFromDurationObject(durationObject)
			frame.Icon:SetDesaturation(C_CurveUtil.EvaluateColorValueFromBoolean(durationObject:IsZero(), 0, 1))
		end

		return frame.Cooldown:IsShown()
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
			return true
		end
	end

	if iconType == "slot" and config.slotID then
		local startTime, duration = GetInventoryItemCooldown("player", config.slotID)
		if startTime and startTime > 0 then
			frame.Cooldown:SetCooldown(startTime, duration)
			frame.Icon:SetDesaturated(true)
			return true
		end
	end

	frame.Cooldown:Clear()
	frame.Icon:SetDesaturated(false)
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

	frame.ChargeCount.Current:SetText(chargeInfo.currentCharges)
	frame.ChargeCount.Current:Show()
end

local function DoesItemOrSpellExists(config)
	local iconType = GetIconType(config)
	if iconType == "spell" then
		return config.spellID and C_Spell.DoesSpellExist(config.spellID)
	end

	if iconType == "item" then
		return config.itemID and C_Item.DoesItemExistByID(config.itemID)
	end

	if iconType == "slot" then
		if config.slotID then
			local itemID = GetInventoryItemID("player", config.slotID)
			if itemID then
				return C_Item.DoesItemExistByID(itemID)
			end
		end
	end
end

local function ResolveCustomIconTexture(config, iconType)
	if iconType == "spell" and config.spellID then
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

	local canShowIcon = iconType == "spell" or iconType == "slot" or hasCount
	return canShowIcon and (not config.hideWhenNotOnCooldown or isOnCooldown)
end

local function ConfigureCustomIconFrame(frame, id, config, viewerScale, anchorGroup)
	frame:SetScale(viewerScale)

	frame.spellID = config.spellID
	frame.itemID = config.itemID
	frame.slotID = config.slotID

	frame.SCMConfig = config
	frame.SCMOrder = config.order
	frame.SCMCooldownID = id
	frame.SCMSpellID = config.spellID
	frame.SCMIconType = GetIconType(config)
	frame.SCMGroup = anchorGroup
end

function CustomIcons.HideIcons()
	for _, customFrame in pairs(SCM.customIconFrames) do
		SCM.SetChildVisibilityState(customFrame, false, true)
	end
end

function CustomIcons.CreateIcons(customConfig, isGlobal)
	local viewerScale = 1

	for id, config in pairs(customConfig) do
		local customFrames = CustomIcons.GetCustomIconFrames(config)
		if not customFrames[id] and DoesItemOrSpellExists(config) then
			local frameName = (isGlobal and "SCM_Custom_Icon_Global_" or "SCM_Custom_Icon_") .. tostring(id)
			local frame = CreateFrame("Frame", frameName, UIParent, "SCMItemIconTemplate")
			customFrames[id] = frame
			ConfigureCustomIconFrame(frame, id, config, viewerScale, config.anchorGroup or 1)

			local iconType = frame.SCMIconType
			local iconTexture = ResolveCustomIconTexture(config, iconType)
			if not iconTexture then
				iconTexture = 134400
			end

			frame.Icon:SetTexture(iconTexture)
			SCM.SetupCustomIconFrame(frame)
			SCM.SetChildVisibilityState(frame, false, true)
			SCM:SkinChild(frame, config)

			frame.UpdateCooldown = UpdateCustomIconCooldown

			if iconType == "spell" then
				UpdateCustomIconCharges(frame, config.spellID)

				if C_Spell.GetSpellCharges(config.spellID) then
					frame.UpdateCharges = UpdateCustomIconCharges
				end
			end
		end
	end
end

function CustomIcons.ProcessIcons(customConfig, validChildren, isGlobal)
	for id, config in pairs(customConfig) do
		local anchorGroup = config.anchorGroup or 1
		local customFrames = CustomIcons.GetCustomIconFrames(config)
		if customFrames[id] and SCM.IsScopedAnchorGroupAllowed(anchorGroup, isGlobal) then
			local frame = customFrames[id]
			local iconType = frame.SCMIconType
			local iconTexture = ResolveCustomIconTexture(config, iconType)
			if not iconTexture and SCM.isOptionsOpen then
				iconTexture = 134400
			end

			if iconTexture then
				frame.Icon:SetTexture(iconTexture)
				local hasCount = SetCustomIconCountText(frame, iconType, config.spellID or config.itemID)
				local isOnCooldown = UpdateCustomIconCooldown(frame, iconType, config)
				local shouldShow = ShouldShowCustomIcon(config, iconType, hasCount, isOnCooldown)
				SCM.SetChildVisibilityState(frame, shouldShow, true)

				if shouldShow then
					if iconType == "spell" then
						UpdateCustomIconCharges(frame, config.spellID)
					end

					SCM.AddChildToScopedGroup(validChildren, anchorGroup, frame, isGlobal)
				end
			else
				SCM.SetChildVisibilityState(frame, false, true)
			end
		end
	end
end
