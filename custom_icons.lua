local SCM = select(2, ...)

SCM.CustomIcons = SCM.CustomIcons or {}
SCM.customIconFrames = SCM.customIconFrames or {}

local CustomIcons = SCM.CustomIcons
local NormalizeIconType = SCM.Utils.NormalizeIconType

local function SetCustomIconCountText(frame, iconType, id)
	frame.ChargeCount.Current:SetText("")
	frame.ChargeCount.Current:Hide()

	if iconType == "spell" then
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

local function UpdateCustomIconCooldown(frame, iconType, config)
	if iconType == "spell" then
		local durationObject = C_Spell.GetSpellCooldownDuration(config.spellID)
		frame.Cooldown:SetCooldownFromDurationObject(durationObject)
		frame.Icon:SetDesaturation(C_CurveUtil.EvaluateColorValueFromBoolean(durationObject:IsZero(), 0, 1))
		return not durationObject:IsZero()
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

	frame.Cooldown:Clear()
	frame.Icon:SetDesaturated(false)
	return false
end

local function ResolveCustomIconTexture(config, iconType)
	if iconType == "spell" and config.spellID then
		return C_Spell.GetSpellTexture(config.spellID)
	end

	if iconType == "item" and config.itemID then
		return C_Item.GetItemIconByID(config.itemID)
	end
end

local function ShouldShowCustomIcon(config, iconType, hasCount, isOnCooldown)
	if SCM.isOptionsOpen then
		return true
	end

	local canShowIcon = iconType == "spell" or hasCount
	return canShowIcon and (not config.hideWhenNotOnCooldown or isOnCooldown)
end

local function ConfigureCustomIconFrame(frame, id, config, viewerScale)
	frame:SetScale(viewerScale)
	frame.SCMConfig = config
	frame.SCMOrder = config.order
	frame.SCMCooldownID = id
	frame.SCMSpellID = config.spellID
	frame.SCMIconType = NormalizeIconType(config)
end

function CustomIcons.HideIcons(setChildVisibilityState)
	for _, customFrame in pairs(SCM.customIconFrames) do
		setChildVisibilityState(customFrame, false, true)
	end
end

function CustomIcons.ProcessIcons(iconConfig, validChildren, isGlobal, context)
	if not context then
		return
	end

	local viewerScale = context.viewerScale or 1
	local setChildVisibilityState = context.setChildVisibilityState
	local setupFrame = context.setupFrame
	local addChildToGroup = context.addChildToGroup

	for id, config in pairs(iconConfig or {}) do
		local isNewFrame = not SCM.customIconFrames[id]
		local frameName = "PRMKCUSTOMICONBUTTON" .. tostring(id)
		local frame = SCM.customIconFrames[id] or CreateFrame("Frame", frameName, UIParent, "PermokItemIconTemplate")
		SCM.customIconFrames[id] = frame
		ConfigureCustomIconFrame(frame, id, config, viewerScale)

		local iconType = frame.SCMIconType
		local iconTexture = ResolveCustomIconTexture(config, iconType)
		if not iconTexture and SCM.isOptionsOpen then
			iconTexture = 134400
		end

		if iconTexture then
			frame.Icon:SetTexture(iconTexture)
			if isNewFrame and setupFrame then
				setupFrame(frame)
			end

			local hasCount = SetCustomIconCountText(frame, iconType, config.spellID or config.itemID)
			local isOnCooldown = UpdateCustomIconCooldown(frame, iconType, config)
			local shouldShow = ShouldShowCustomIcon(config, iconType, hasCount, isOnCooldown)
			setChildVisibilityState(frame, shouldShow, true)

			if shouldShow then
				SCM:SkinChild(frame, config)
				addChildToGroup(validChildren, config.anchorGroup or 1, frame, isGlobal)
			end
		else
			setChildVisibilityState(frame, false, true)
		end
	end
end

function CustomIcons.UpdateBagIcons(setCooldownVisual, setChildVisibilityState)
	local GetItemCooldown = C_Item.GetItemCooldown

	for _, frame in pairs(SCM.customIconFrames) do
		if frame:IsShown() then
			local config = frame.SCMConfig
			local itemID = config and config.itemID
			if itemID and NormalizeIconType(config) == "item" then
				local start, duration = GetItemCooldown(itemID)
				setCooldownVisual(frame, start, duration)
				if not SetCustomIconCountText(frame, "item", itemID) and not SCM.isOptionsOpen then
					setChildVisibilityState(frame, false, true)
				end
			end
		end
	end
end
