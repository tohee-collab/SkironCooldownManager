local _, SCM = ...
local LSM = LibStub("LibSharedMedia-3.0")

local MIN_BAR_WIDTH = 200
local RESOURCE_BAR_FRAME_NAME = "SCM_ResourceBarContainer"
local MOUNTED_VISIBILITY_CONDITION = "[combat]show;[mounted][stance:3]hide;show"

local UNIT_POWER_SPELL_IDS = Constants.UnitPowerSpellIDs
local SPELL_ID_VOID_METAMORPHOSIS = UNIT_POWER_SPELL_IDS.VOID_METAMORPHOSIS_SPELL_ID or 1217607
local SPELL_ID_DARK_HEART = UNIT_POWER_SPELL_IDS.DARK_HEART_SPELL_ID or 1225789
local SPELL_ID_SILENCE_THE_WHISPERS = UNIT_POWER_SPELL_IDS.SILENCE_THE_WHISPERS_SPELL_ID or 1227702
local SPELL_ID_MAELSTROM_WEAPON = UNIT_POWER_SPELL_IDS.MAELSTROM_WEAPON or 344179
local SPELL_ID_TIP_OF_THE_SPEAR = 260286

local SCMConstants = SCM.Constants
local CHARGED_COMBO_POINT_COLOR = SCMConstants.ChargedComboPointColor
local DEFAULT_RESOURCE_BAR_ANCHOR = "ANCHOR:1"
local RESOURCE_BAR_RECONFIGURE_EVENTS = {
	PLAYER_ENTERING_WORLD = true,
	PLAYER_GAINS_VEHICLE_DATA = true,
	PLAYER_LOSES_VEHICLE_DATA = true,
	UNIT_DISPLAYPOWER = true,
	UPDATE_SHAPESHIFT_FORM = true,
	UNIT_MAXPOWER = true,
}

local function GetPowerColorByInfo(powerToken, powerType)
	local colorInfo = GetPowerBarColor(powerType)
	if colorInfo then
		return colorInfo
	end

	return SCMConstants.FallbackPowerColorByToken[powerToken]
end

local function GetPowerColor(powerToken, powerType, altR, altG, altB)
	local barOptions = SCM.db.profile.options.resourceBar
	local powerTypeColorOverride = powerToken and barOptions and barOptions.powerTypeColorOverrides[powerToken]
	if powerTypeColorOverride then
		local color = powerTypeColorOverride.color
		return color.r, color.g, color.b
	end

	local colorInfo = GetPowerColorByInfo(powerToken, powerType)
	if colorInfo and colorInfo.r and colorInfo.g and colorInfo.b then
		return colorInfo.r, colorInfo.g, colorInfo.b
	end

	if altR and altG and altB then
		return altR, altG, altB
	end

	return 0.25, 0.55, 1.00
end

local function ShouldHideManaForCurrentRole(barOptions)
	local specializationIndex = GetSpecialization()
	if not specializationIndex then
		return
	end

	local role = select(5, GetSpecializationInfo(specializationIndex))
	return barOptions.hideManaRoles[role]
end

local function UpdateResourceBarBackdropInfo(barOptions)
	if not barOptions.showBorder then
		return
	end

	local backdropSize = barOptions.backdropSize
	if not backdropSize or backdropSize <= 0 then
		return
	end

	local backdropInfo = CopyTable(BACKDROP_SCM_PIXEL)
	-- FUCK PIXEL PERFECT ISSUES
	backdropInfo.edgeSize = backdropSize
	return backdropInfo
end

local function CalculateResourceBarPixelInset(region)
	if region.barOptions and not region.barOptions.showBorder then
		return 0
	end

	local backdropSize = (region.barOptions and region.barOptions.backdropSize) or 0
	if backdropSize <= 0 then
		return 0
	end

	--local halfBorderSize = backdropSize * 0.5
	return PixelUtil.GetNearestPixelSize(backdropSize * 0.5, region:GetEffectiveScale(), 1)
end

local function UpdateResourceBarBorder(bar, barOptions)
	if not bar or not bar.BorderFrame then
		return
	end

	local borderFrame = bar.BorderFrame
	borderFrame:SetFrameLevel(bar:GetFrameLevel() + 1)

	local backdropInfo = UpdateResourceBarBackdropInfo(barOptions)
	if not backdropInfo then
		borderFrame:SetBackdrop(nil)
		borderFrame:Hide()
		return
	end

	borderFrame:SetBackdrop(backdropInfo)
	borderFrame:ApplyBackdrop()

	local color = barOptions.backdropColor or {}
	borderFrame:SetBackdropBorderColor(color.r or 0, color.g or 0, color.b or 0, color.a == nil and 1 or color.a)
	borderFrame:Show()
end

local function SetRegionPoint(region, bar)
	local inset = CalculateResourceBarPixelInset(bar)
	region:ClearAllPoints()
	PixelUtil.SetPoint(region, "TOPLEFT", bar, "TOPLEFT", inset, -inset)
	PixelUtil.SetPoint(region, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -inset, inset)
	return inset
end

local function UpdateResourceBarBackgroundTexture(bar, barOptions)
	local backgroundTexture = bar.Background
	local backgroundTextureName = barOptions.useBackgroundTexture and (barOptions.backgroundTexture or barOptions.texture)
	if not backgroundTextureName then
		backgroundTexture:Hide()
		return
	end

	local backgroundColor = barOptions.backgroundColor
	backgroundTexture:SetVertexColor(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a)

	backgroundTexture:SetTexture(LSM:Fetch("statusbar", backgroundTextureName))
	SetRegionPoint(backgroundTexture, bar)
	backgroundTexture:Show()
end

local function GetRuneValues()
	local currentFillValue = 0
	local readyRuneCount = 0
	local maxRuneCount = 0
	local runeChargeSegments = {}
	local currentTime = GetTime()

	for runeIndex = 1, 6 do
		local cooldownStartTime, cooldownDuration, runeReady = GetRuneCooldown(runeIndex)
		if runeReady ~= nil then
			maxRuneCount = maxRuneCount + 1
			if runeReady then
				currentFillValue = currentFillValue + 1
				readyRuneCount = readyRuneCount + 1
				runeChargeSegments[maxRuneCount] = {
					progress = 1,
					remaining = 0,
					index = runeIndex,
				}
			elseif cooldownStartTime and cooldownDuration and cooldownDuration > 0 then
				local elapsedSinceRechargeStart = currentTime - cooldownStartTime
				local chargeProgress = Clamp(elapsedSinceRechargeStart / cooldownDuration, 0, 1)

				local remaining = cooldownDuration - elapsedSinceRechargeStart
				if remaining < 0 then
					remaining = 0
				end

				runeChargeSegments[maxRuneCount] = {
					progress = chargeProgress,
					remaining = remaining,
					index = runeIndex,
				}
				currentFillValue = currentFillValue + chargeProgress
			else
				runeChargeSegments[maxRuneCount] = {
					progress = 0,
					remaining = math.huge,
					index = runeIndex,
				}
			end
		end
	end

	return currentFillValue, maxRuneCount, readyRuneCount, runeChargeSegments
end

local function GetSoulFragmentValues()
	local currentValue = 0
	local maxValue = 0

	if C_UnitAuras.GetPlayerAuraBySpellID(SPELL_ID_VOID_METAMORPHOSIS) then
		local auraData = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_ID_SILENCE_THE_WHISPERS)
		currentValue = auraData and auraData.applications or 0
		maxValue = GetCollapsingStarCost() or 0
	else
		local auraData = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_ID_DARK_HEART)
		currentValue = auraData and auraData.applications or 0
	end

	if maxValue <= 0 then
		maxValue = C_Spell.GetSpellMaxCumulativeAuraApplications(SPELL_ID_DARK_HEART) or 0
	end

	return currentValue, maxValue
end

local function GetEssenceValue()
	local currentValue = UnitPower("player", Enum.PowerType.Essence) or 0
	local maxValue = UnitPowerMax("player", Enum.PowerType.Essence) or 0
	local fillValue = currentValue

	if currentValue < maxValue then
		local partialValue = UnitPartialPower("player", Enum.PowerType.Essence) or 0
		local partialProgress = Clamp(partialValue / 1000, 0, 1)

		fillValue = fillValue + partialProgress
	end

	return fillValue, maxValue, currentValue
end

local function GetTipOfTheSpearValue()
	local currentValue = 0
	local maxValue = 3

	local auraData = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_ID_TIP_OF_THE_SPEAR)
	if auraData then
		currentValue = auraData.applications or 0
	end

	return currentValue, maxValue
end

local function GetMaelstromWeaponValue()
	local currentValue = 0
	local maxValue = 10

	local auraData = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_ID_MAELSTROM_WEAPON)
	if auraData then
		currentValue = auraData.applications or 0
	end

	return currentValue, maxValue
end

local function GetCurrentPowerValue(resourceKind, powerType)
	if resourceKind == "runes" then
		return GetRuneValues()
	end

	if resourceKind == "stagger" then
		local currentValue = UnitStagger("player") or 0
		local maxValue = UnitHealthMax("player") or 0
		return currentValue, maxValue
	end

	if resourceKind == "maelstromWeapon" then
		return GetMaelstromWeaponValue()
	end

	if resourceKind == "soulFragments" then
		local currentValue, maxValue = GetSoulFragmentValues()
		return currentValue, maxValue
	end

	if resourceKind == "destructionSoulShards" then
		local currentRawValue = UnitPower("player", Enum.PowerType.SoulShards, true)
		local maxRawValue = UnitPowerMax("player", Enum.PowerType.SoulShards, true)
		local currentValue = currentRawValue / 10
		local maxValue = maxRawValue / 10
		return currentValue, maxValue
	end

	if resourceKind == "tipOfTheSpear" then
		return GetTipOfTheSpearValue()
	end

	if powerType == Enum.PowerType.Essence then
		return GetEssenceValue()
	end

	local currentValue = UnitPower("player", powerType)
	local maxValue = UnitPowerMax("player", powerType)
	return currentValue, maxValue
end

local function UpdateStaggerBarColor(bar, currentValue, maxValue)
	local staggerPercent = maxValue > 0 and currentValue / maxValue or 0
	if staggerPercent >= 0.60 then
		bar:SetStatusBarColor(1.00, 0.42, 0.42)
	elseif staggerPercent >= 0.30 then
		bar:SetStatusBarColor(1.00, 0.98, 0.72)
	else
		bar:SetStatusBarColor(0.52, 1.00, 0.52)
	end
end

local function HideRegions(regionList)
	if not regionList then
		return
	end

	for _, region in ipairs(regionList) do
		region:Hide()
	end
end

local function GetNumSegments(bar, maxValue)
	local segmentCount = bar.segmentCount or maxValue
	if not segmentCount or segmentCount <= 0 then
		return
	end

	return max(1, segmentCount)
end

local function UpdateBarTextPosition(bar, barOptions)
	local text = bar.Text.Value
	if not text then
		return
	end

	local anchorRegion = bar.Text or bar
	text:ClearAllPoints()
	PixelUtil.SetPoint(text, "CENTER", anchorRegion, "CENTER", barOptions.textXOffset, barOptions.textYOffset, 1, 1)
end

local function ResetResourceBar(bar)
	bar.resourceKind = nil
	bar.powerType = nil
	bar.powerToken = nil
	bar.segmentCount = nil
	bar.SCMRegisterUnitAura = nil
	bar.Text.Value:SetText("")

	HideRegions(bar.SegmentTicks)
	HideRegions(bar.SegmentFillBars)
	HideRegions(bar.RuneSegmentBars)

	bar.SCMSegmentedDisplay = nil
	bar.SCMTicksDirty = true

	bar:GetStatusBarTexture():SetAlpha(1)

	bar:Hide()
end

local function ConfigureBarForResource(bar, resource, altR, altG, altB)
	bar.resourceKind = resource.resourceKind or "power"
	bar.powerType = resource.powerType
	bar.powerToken = resource.powerToken
	bar.segmentCount = resource.segmentCount
	if bar.SCMUseSegmentedSecondaryDisplay and bar.powerType == Enum.PowerType.Mana then
		bar.segmentCount = nil
	end
	bar.SCMRegisterUnitAura = resource.registerUnitAura
	bar.SCMTicksDirty = true

	local overrideColor = bar.SCMIsPrimaryResourceBar and SCM.primaryResourceBarColorOverride
	local r, g, b
	if overrideColor then
		r, g, b = overrideColor.r, overrideColor.g, overrideColor.b
	else
		r, g, b = GetPowerColor(bar.powerToken, bar.powerType, altR, altG, altB)
	end
	bar:SetStatusBarColor(r, g, b)
	bar:Show()
end

local function CreateTicks(bar, tickCount, tickColor)
	bar.SegmentTicks = bar.SegmentTicks or {}

	for tickIndex = #bar.SegmentTicks + 1, tickCount do
		local tick = bar.SegmentTicks[tickIndex] or bar:CreateTexture(nil, "OVERLAY")
		tick:SetColorTexture(tickColor.r, tickColor.g, tickColor.b, tickColor.a)
		bar.SegmentTicks[tickIndex] = tick
	end

	return bar.SegmentTicks
end

local function UpdateTicks(bar, maxValue)
	local segmentCount = GetNumSegments(bar, maxValue)
	if
		not bar.barOptions.showTicks
		or (not (bar.segmentCount and bar.segmentCount > 1) and not (bar.powerToken and SCMConstants.SegmentTicksByPowerToken[bar.powerToken]))
		or type(segmentCount) ~= "number"
		or segmentCount <= 1
	then
		HideRegions(bar.SegmentTicks)
		return
	end

	local barOptions = bar.barOptions
	local tickCount = segmentCount - 1
	local tickColor = barOptions.tickColor
	if not SCM.isOptionsOpen and not bar.SCMTicksDirty then
		return
	end

	local tickTextures = CreateTicks(bar, tickCount, tickColor)
	local tickWidth = barOptions.tickWidth

	if not tickTextures or #tickTextures == 0 then
		return
	end

	if tickWidth <= 0 then
		HideRegions(bar.SegmentTicks)
		return
	end

	local offset = bar:GetWidth() / segmentCount
	for tickIndex = 1, tickCount do
		local tick = tickTextures[tickIndex]
		tick:SetColorTexture(tickColor.r, tickColor.g, tickColor.b, tickColor.a)
		tick:SetPoint("LEFT", tickIndex * offset, 0)
		tick:SetWidth(tickWidth)
		tick:SetHeight(bar:GetHeight())
		tick:Show()
	end

	for tickIndex = tickCount + 1, #tickTextures do
		tickTextures[tickIndex]:Hide()
	end

	bar.SCMTicksDirty = false
end

local function GetChargedSegmentMap(bar, segmentCount, currentValue)
	if bar.powerType == Enum.PowerType.ComboPoints and UnitClassBase("player") == "ROGUE" then
		local chargedComboPoints = GetUnitChargedPowerPoints("player")
		if not chargedComboPoints or #chargedComboPoints == 0 then
			return
		end

		local chargedSegmentMap = {}
		for _, pointIndex in ipairs(chargedComboPoints) do
			chargedSegmentMap[pointIndex] = true
		end

		return chargedSegmentMap
	end

	if bar.resourceKind ~= "maelstromWeapon" or type(segmentCount) ~= "number" or type(currentValue) ~= "number" then
		return
	end

	local overflowCount = floor(currentValue - segmentCount)
	if overflowCount <= 0 then
		return
	end
	if overflowCount > segmentCount then
		overflowCount = segmentCount
	end

	local chargedSegmentMap = {}
	for segmentIndex = 1, overflowCount do
		chargedSegmentMap[segmentIndex] = true
	end

	return chargedSegmentMap
end

local function ShouldUseSegmentedSecondaryDisplay(bar, segmentCount)
	if not bar.SCMUseSegmentedSecondaryDisplay or type(segmentCount) ~= "number" or segmentCount <= 1 then
		return
	end

	if bar.segmentCount and bar.segmentCount > 1 then
		return true
	end

	return bar.powerToken and SCMConstants.SegmentTicksByPowerToken[bar.powerToken]
end

local function CreateSegments(bar, segmentCount)
	bar.SegmentFillBars = bar.SegmentFillBars or {}
	local texturePath = bar.SCMTexturePath or LSM:Fetch("statusbar", bar.barOptions.texture)

	for segmentIndex = #bar.SegmentFillBars + 1, segmentCount do
		local segmentBar = bar.SegmentFillBars[segmentIndex] or CreateFrame("StatusBar", nil, bar)
		segmentBar:SetMinMaxValues(0, 1)
		segmentBar:SetStatusBarTexture(texturePath)
		segmentBar:SetFrameLevel(2)
		bar.SegmentFillBars[segmentIndex] = segmentBar
	end

	return bar.SegmentFillBars
end

local function GetProgressValues(bar, segmentCount, currentValue, resourceSegmentValues)
	local segmentProgressValues = {}

	if bar.resourceKind == "runes" then
		local orderedRuneSegments = {}
		for runeIndex = 1, segmentCount do
			orderedRuneSegments[runeIndex] = resourceSegmentValues[runeIndex] or { progress = 0, remaining = math.huge, index = runeIndex }
		end

		table.sort(orderedRuneSegments, function(leftRune, rightRune)
			if leftRune.remaining == rightRune.remaining then
				return leftRune.index < rightRune.index
			end

			return leftRune.remaining < rightRune.remaining
		end)

		for segmentIndex = 1, segmentCount do
			local runeSegment = orderedRuneSegments[segmentIndex]
			segmentProgressValues[segmentIndex] = (runeSegment and runeSegment.progress) or 0
		end

		return segmentProgressValues
	end

	for segmentIndex = 1, segmentCount do
		segmentProgressValues[segmentIndex] = currentValue >= segmentIndex and 1 or 0
	end

	return segmentProgressValues
end

local function UpdateSegments(bar, maxValue, currentValue, resourceSegmentValues)
	local segmentCount = GetNumSegments(bar, maxValue)
	if not ShouldUseSegmentedSecondaryDisplay(bar, segmentCount) then
		bar.SCMSegmentedDisplay = nil
		HideRegions(bar.SegmentFillBars)
		HideRegions(bar.RuneSegmentBars)
		bar:GetStatusBarTexture():SetAlpha(1)
		return
	end

	bar.SCMSegmentedDisplay = true
	bar.segmentCount = segmentCount
	bar:GetStatusBarTexture():SetAlpha(0)
	HideRegions(bar.RuneSegmentBars)

	local segmentBars = CreateSegments(bar, segmentCount)
	local texturePath = bar.SCMTexturePath or LSM:Fetch("statusbar", bar.barOptions.texture)
	local r, g, b = GetPowerColor(bar.powerToken, bar.powerType)
	local overflowR, overflowG, overflowB = CHARGED_COMBO_POINT_COLOR.r, CHARGED_COMBO_POINT_COLOR.g, CHARGED_COMBO_POINT_COLOR.b
	if bar.resourceKind == "maelstromWeapon" then
		local overflowColor = SCM.db.profile.options.resourceBar.maelstromOverflowColor
		if overflowColor and overflowColor.r and overflowColor.g and overflowColor.b then
			overflowR, overflowG, overflowB = overflowColor.r, overflowColor.g, overflowColor.b
		end
	end
	local chargedSegments = GetChargedSegmentMap(bar, segmentCount, currentValue)
	local segmentProgressValues = GetProgressValues(bar, segmentCount, currentValue, resourceSegmentValues)
	local segmentWidth = bar:GetWidth() / segmentCount
	local segmentHeight = bar:GetHeight()
	local borderSize = (not bar.barOptions.showBorder and 0 or (bar.barOptions.backdropSize or 0)) * 2

	for segmentIndex = 1, segmentCount do
		local segmentBar = segmentBars[segmentIndex]
		segmentBar:ClearAllPoints()
		segmentBar:SetStatusBarTexture(texturePath)
		segmentBar:SetPoint("LEFT", (segmentIndex - 1) * segmentWidth, 0)
		segmentBar:SetWidth(segmentWidth)
		segmentBar:SetHeight(segmentHeight - borderSize)
		if chargedSegments and chargedSegments[segmentIndex] then
			if bar.resourceKind == "maelstromWeapon" then
				segmentBar:SetStatusBarColor(overflowR, overflowG, overflowB)
			else
				segmentBar:SetStatusBarColor(CHARGED_COMBO_POINT_COLOR.r, CHARGED_COMBO_POINT_COLOR.g, CHARGED_COMBO_POINT_COLOR.b)
			end
		else
			segmentBar:SetStatusBarColor(r, g, b)
		end
		segmentBar:SetValue(segmentProgressValues[segmentIndex] or 0)
		segmentBar:Show()
	end

	for segmentIndex = segmentCount + 1, #segmentBars do
		segmentBars[segmentIndex]:Hide()
	end
end

local function ApplyBarAppearance(bar, barOptions)
	if not bar then
		return
	end

	bar.barOptions = barOptions
	bar.SCMTicksDirty = true

	local texturePath = LSM:Fetch("statusbar", barOptions.texture)
	bar.SCMTexturePath = texturePath
	bar:SetStatusBarTexture(texturePath)

	if bar.SegmentFillBars then
		for _, segmentBar in ipairs(bar.SegmentFillBars) do
			segmentBar:SetStatusBarTexture(texturePath)
		end
	end

	local statusBarTexture = bar:GetStatusBarTexture()
	SetRegionPoint(statusBarTexture, bar)
	UpdateResourceBarBackgroundTexture(bar, barOptions)

	PixelUtil.SetHeight(bar, barOptions.height, barOptions.height)

	local text = bar.Text
	local fontPath = LSM:Fetch("font", barOptions.font)
	local fontFlags = barOptions.textOutline

	if not fontFlags or fontFlags == "NONE" then
		fontFlags = ""
	end

	text.Value:SetFont(fontPath, barOptions.fontSize, fontFlags)
	text.Value:SetShadowColor(0, 0, 0, 0)
	UpdateBarTextPosition(bar, barOptions)
	text:SetShown(barOptions.showValues)

	if bar.BorderFrame then
		UpdateResourceBarBorder(bar, barOptions)
	end

	if bar.Text then
		bar.Text:SetFrameStrata(bar:GetFrameStrata())
		bar.Text:SetFrameLevel(bar:GetFrameLevel() + 2)
	end
end

local function InitializeBarSkin(bar)
	if not bar or bar.SCMStyled then
		return
	end

	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar.Text.Value:SetTextColor(1, 1, 1, 1)
	bar:SetBackdrop(nil)

	if not bar.BorderFrame then
		bar.BorderFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	end

	-- If anyone wants to explain to me how to fix this then I'm all ears
	bar.BorderFrame:ClearAllPoints()
	PixelUtil.SetPoint(bar.BorderFrame, "TOPLEFT", bar, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(bar.BorderFrame, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

	local barOptions = bar.barOptions or SCM.db.profile.options.resourceBar
	UpdateResourceBarBorder(bar, barOptions)
	bar.SCMStyled = true
end

local function BarNeedsContinuousRefresh(bar)
	if not bar.powerToken or not bar:IsShown() then
		return
	end

	if bar.resourceKind == "runes" then
		local _, maxValue, displayValue = GetRuneValues()
		return type(displayValue) == "number" and type(maxValue) == "number" and displayValue < maxValue
	end

	if bar.powerType == Enum.PowerType.Essence then
		local currentValue = UnitPower("player", Enum.PowerType.Essence) or 0
		local maxValue = UnitPowerMax("player", Enum.PowerType.Essence) or 0
		return currentValue < maxValue
	end
end
local function RegisterBarEvents(bar, barOptions)
	bar:UnregisterAllEvents()

	if not bar.powerToken then
		return
	end

	if bar.SCMRegisterUnitAura then
		bar:RegisterUnitEvent("UNIT_AURA", "player")
		return
	end

	if bar.resourceKind == "runes" then
		bar:RegisterEvent("RUNE_POWER_UPDATE")
		return
	end

	local powerUpdateEvent = barOptions.useFrequentPowerUpdates and "UNIT_POWER_FREQUENT" or "UNIT_POWER_UPDATE"
	bar:RegisterUnitEvent(powerUpdateEvent, "player")

	if bar.powerType ~= nil then
		bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	end

	if bar.powerType == Enum.PowerType.ComboPoints then
		bar:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
	end
end

local function OnResourceBarEvent(bar)
	local controller = bar and bar.Controller
	if not controller then
		return
	end

	controller:RefreshBarDisplay(bar)
	controller:UpdateBarLayout()
	controller:UpdateContainerShownState()
	controller:UpdateRefreshState()
end

local SCMResourceBarControllerMixin = {}
function SCM:ApplyResourceBarHideWhileMountedSettings(value)
	local container = _G[RESOURCE_BAR_FRAME_NAME]
	if not container or InCombatLockdown() then
		return
	end

	if value then
		RegisterAttributeDriver(container, "state-visibility", MOUNTED_VISIBILITY_CONDITION)
	else
		UnregisterAttributeDriver(container, "state-visibility")
		if container.SCMResourceBarInitialized and container.UpdateContainerShownState then
			container:UpdateContainerShownState()
		end
	end
end

function SCMResourceBarControllerMixin:ApplyResourceBarOptions()
	local barOptions = SCM.db.profile.options.resourceBar
	self.barOptions = barOptions
	self.primaryBarOptions = barOptions.primaryBar
	self.secondaryBarOptions = barOptions.secondaryBar

	ApplyBarAppearance(self.PrimaryBar, self.primaryBarOptions)
	ApplyBarAppearance(self.SecondaryBar, self.secondaryBarOptions)

	return barOptions
end

function SCMResourceBarControllerMixin:ApplyFrameWidthOptions(bar)
	if InCombatLockdown() then
		return
	end

	local specificBarOptions = bar.barOptions
	local generalBarOptions = self.barOptions
	local anchor = generalBarOptions.anchorFrame or DEFAULT_RESOURCE_BAR_ANCHOR
	if type(anchor) == "string" then
		anchor = SCM.Utils.GetAnchorFrame(anchor)
	end

	if anchor then
		local desiredWidth = max(MIN_BAR_WIDTH, specificBarOptions.matchAnchorWidth and (anchor and anchor:GetWidth() or 0) or specificBarOptions.width)
		local previousWidth = bar:GetWidth() or 0
		bar:SetWidth(desiredWidth)

		if not bar.SCMResourceBarHook then
			bar.SCMResourceBarHook = true
			anchor:HookScript("OnSizeChanged", function(_, width)
				if not InCombatLockdown() and specificBarOptions.matchAnchorWidth then
					SCM:RefreshResourceBarConfig()
				end
			end)
		end

		if previousWidth ~= desiredWidth then
			bar.SCMTicksDirty = true
		end

		local offset = 0
		if bar.segmentCount then
			if bar.segmentCount == 5 then
				offset = SCM:PixelPerfect()
			end
		end
		--No idea whats going in with these fucking pixels. BRB taking a math class
		self:ClearAllPoints()
		PixelUtil.SetPoint(self, generalBarOptions.point, anchor, generalBarOptions.relativePoint, (generalBarOptions.xOffset or 0) + offset, generalBarOptions.yOffset or 0)
	end
end

function SCMResourceBarControllerMixin:UpdateRefreshState()
	local needsContinuousRefresh = BarNeedsContinuousRefresh(self.PrimaryBar) or BarNeedsContinuousRefresh(self.SecondaryBar)
	if needsContinuousRefresh then
		if not self:GetScript("OnUpdate") then
			self:SetScript("OnUpdate", self.OnUpdate)
		end
	else
		self:SetScript("OnUpdate", nil)
		self.totalElapsed = nil
	end
end

function SCMResourceBarControllerMixin:OnUpdate(elapsed)
	self.totalElapsed = (self.totalElapsed or 0) + elapsed
	if self.totalElapsed < (SCMConstants.RefreshInterval or 0.05) then
		return
	end

	self.totalElapsed = 0
	self:RefreshBarDisplay(self.PrimaryBar)
	self:RefreshBarDisplay(self.SecondaryBar)
	self:UpdateRefreshState()
end

function SCMResourceBarControllerMixin:RefreshResourceBars()
	local barOptions = self:ApplyResourceBarOptions()
	if not barOptions.enabled then
		SCM:ApplyResourceBarHideWhileMountedSettings(false)
		self:UnregisterAllEvents()
		self.SCMResourceBarEventsRegistered = false
		self.PrimaryBar:UnregisterAllEvents()
		self.SecondaryBar:UnregisterAllEvents()
		self:SetScript("OnUpdate", nil)
		self.totalElapsed = nil
		ResetResourceBar(self.PrimaryBar)
		ResetResourceBar(self.SecondaryBar)
		self:UpdateContainerShownState()
		return
	end

	if barOptions.primaryBar.enabled then
		self:ConfigurePrimaryBar()
		RegisterBarEvents(self.PrimaryBar, barOptions)
		self:ApplyFrameWidthOptions(self.PrimaryBar)
		self:RefreshBarDisplay(self.PrimaryBar)
	else
		self.PrimaryBar:UnregisterAllEvents()
		ResetResourceBar(self.PrimaryBar)
	end

	if barOptions.secondaryBar.enabled then
		self:ConfigureSecondaryBar()
		RegisterBarEvents(self.SecondaryBar, barOptions)
		self:ApplyFrameWidthOptions(self.SecondaryBar)
		self:RefreshBarDisplay(self.SecondaryBar)
	else
		self.SecondaryBar:UnregisterAllEvents()
		ResetResourceBar(self.SecondaryBar)
	end

	if barOptions.primaryBar.enabled or barOptions.secondaryBar.enabled then
		self:RegisterResourceBarEvents()
		self:UpdateBarLayout()
		self:UpdateContainerShownState()
		self:UpdateRefreshState()

		EventRegistry:TriggerEvent("SkironCooldownManager.ResourceBar.LayoutUpdated")
	end

	SCM:ApplyResourceBarHideWhileMountedSettings(barOptions.hideWhileMounted)
end

function SCMResourceBarControllerMixin:ConfigurePrimaryBar()
	local powerType, powerToken, altR, altG, altB = UnitPowerType("player")
	if not powerType or not powerToken then
		ResetResourceBar(self.PrimaryBar)
		return
	end

	if powerType == Enum.PowerType.Mana and ShouldHideManaForCurrentRole(self.primaryBarOptions) then
		ResetResourceBar(self.PrimaryBar)
		return
	end

	ConfigureBarForResource(self.PrimaryBar, {
		powerType = powerType,
		powerToken = powerToken,
	}, altR, altG, altB)
end

function SCMResourceBarControllerMixin:ConfigureSecondaryBar()
	local primaryPowerType = UnitPowerType("player")
	local secondaryResource

	if not UnitInVehicle("player") then
		local className = UnitClassBase("player")
		local specializationIndex = C_SpecializationInfo.GetSpecialization()
		local specializationID = C_SpecializationInfo.GetSpecializationInfo(specializationIndex)

		secondaryResource = SCMConstants.SpecSecondaryPower[specializationID] or SCMConstants.ClassSecondaryPower[className]
		if secondaryResource and secondaryResource.showWhenPrimaryPowerType and primaryPowerType ~= secondaryResource.showWhenPrimaryPowerType then
			secondaryResource = nil
		end

		if not secondaryResource then
			local classManaSecondaryPower = SCMConstants.ClassManaSecondaryPower[className]
			secondaryResource = classManaSecondaryPower and classManaSecondaryPower[primaryPowerType]
		end
	end

	if secondaryResource and secondaryResource.powerType == primaryPowerType then
		secondaryResource = nil
	end

	if secondaryResource and secondaryResource.powerType == Enum.PowerType.Mana and ShouldHideManaForCurrentRole(self.secondaryBarOptions) then
		secondaryResource = nil
	end

	if not secondaryResource then
		ResetResourceBar(self.SecondaryBar)
		return
	end

	ConfigureBarForResource(self.SecondaryBar, secondaryResource)
end

function SCMResourceBarControllerMixin:RefreshBarDisplay(bar)
	if not bar.powerToken then
		return
	end

	local currentValue, maxValue, displayValue, resourceSegmentValues = GetCurrentPowerValue(bar.resourceKind, bar.powerType)
	if not (currentValue and maxValue) then
		UpdateSegments(bar, nil, nil, nil)
		UpdateTicks(bar, nil)
		bar:Hide()
		return
	end

	displayValue = displayValue == nil and currentValue or displayValue
	bar:SetMinMaxValues(0, maxValue)
	bar:SetValue(currentValue)
	UpdateSegments(bar, maxValue, currentValue, resourceSegmentValues)
	UpdateTicks(bar, maxValue)
	self:ApplyFrameWidthOptions(bar)

	local overrideColor = bar.SCMIsPrimaryResourceBar and SCM.primaryResourceBarColorOverride
	if overrideColor then
		bar:SetStatusBarColor(overrideColor.r, overrideColor.g, overrideColor.b)
	elseif bar.resourceKind == "stagger" and not SCM.db.profile.options.resourceBar.powerTypeColorOverrides[bar.powerToken] then
		UpdateStaggerBarColor(bar, currentValue, maxValue)
	end

	local text = bar.Text
	local overrideText = bar.SCMIsPrimaryResourceBar and SCM.primaryResourceBarTextOverride
	if overrideText ~= nil then
		if text then
			text.Value:SetText(overrideText)
		end
	elseif displayValue then
		if text then
			if bar.powerType == Enum.PowerType.Mana then
				text.Value:SetText(string.format("%d%%", (UnitPowerPercent("player", bar.powerType, false, CurveConstants.ScaleTo100))))
			else
				text.Value:SetText(AbbreviateLargeNumbers(displayValue))
			end
		end
	elseif text then
		text.Value:SetText("")
	end
	bar:Show()
end

function SCMResourceBarControllerMixin:UpdateBarLayout()
	local barOptions = self.barOptions
	local primaryShown = self.PrimaryBar:IsShown()
	local secondaryShown = self.SecondaryBar:IsShown()
	local primaryHeight = (self.primaryBarOptions and self.primaryBarOptions.height) or 0
	local secondaryHeight = (self.secondaryBarOptions and self.secondaryBarOptions.height) or 0
	local spacing = barOptions.spacing
	local growsUp = barOptions.growDirection == "UP"

	self.SecondaryBar:ClearAllPoints()
	self.PrimaryBar:ClearAllPoints()

	if primaryShown then
		self.PrimaryBar:SetPoint("BOTTOM", self, "BOTTOM")
	end

	if secondaryShown then
		if primaryShown then
			if growsUp then
				self.SecondaryBar:SetPoint("BOTTOM", self.PrimaryBar, "TOP", 0, spacing)
			else
				self.SecondaryBar:SetPoint("TOP", self.PrimaryBar, "BOTTOM", 0, -spacing)
			end
		else
			self.SecondaryBar:SetPoint("BOTTOM", self, "BOTTOM")
		end
	end

	if primaryShown and secondaryShown then
		PixelUtil.SetHeight(self, primaryHeight + secondaryHeight + spacing)
	elseif primaryShown or secondaryShown then
		PixelUtil.SetHeight(self, primaryShown and primaryHeight or secondaryHeight)
	else
		self:SetHeight(0)
	end
end

function SCMResourceBarControllerMixin:UpdateContainerShownState()
	local barOptions = self.barOptions
	if not barOptions.enabled then
		self:Hide()
		return
	end

	if barOptions.hideWhileMounted and self:GetAttribute("statehidden") then
		return
	end

	self:SetShown(self.PrimaryBar:IsShown() or self.SecondaryBar:IsShown())
end

function SCMResourceBarControllerMixin:OnAttributeChanged(name, value)
	if name ~= "statehidden" or value then
		return
	end

	self:UpdateContainerShownState()
end

function SCMResourceBarControllerMixin:OnEvent(event)
	if RESOURCE_BAR_RECONFIGURE_EVENTS[event] then
		self:RefreshResourceBars()
	end
end

function SCMResourceBarControllerMixin:RegisterResourceBarEvents()
	if not self.SCMResourceBarEventsRegistered then
		self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		self:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		self:RegisterEvent("PLAYER_GAINS_VEHICLE_DATA")
		self:RegisterEvent("PLAYER_LOSES_VEHICLE_DATA")
		self.SCMResourceBarEventsRegistered = true
	end
end

function SCMResourceBarControllerMixin:Initialize()
	InitializeBarSkin(self.PrimaryBar)
	InitializeBarSkin(self.SecondaryBar)
	self.PrimaryBar.SCMIsPrimaryResourceBar = true
	self.SecondaryBar.SCMIsPrimaryResourceBar = nil
	self.PrimaryBar.SCMUseSegmentedSecondaryDisplay = false
	self.SecondaryBar.SCMUseSegmentedSecondaryDisplay = true
	self.PrimaryBar.Controller = self
	self.SecondaryBar.Controller = self
	self.PrimaryBar:SetScript("OnEvent", OnResourceBarEvent)
	self.SecondaryBar:SetScript("OnEvent", OnResourceBarEvent)

	self:SetScript("OnAttributeChanged", self.OnAttributeChanged)
	self:SetScript("OnEvent", self.OnEvent)
	self:RegisterResourceBarEvents()

	self:RefreshResourceBars()
end

function SCM:InitializeResourceBars()
	local container = _G[RESOURCE_BAR_FRAME_NAME]
	local barOptions = self.db.profile.options.resourceBar
	if not container or container.SCMResourceBarInitialized or not barOptions.enabled then
		return
	end

	local primaryBar = _G["SCM_PrimaryResourceBar"]
	local secondaryBar = _G["SCM_SecondaryResourceBar"]

	container.SCMResourceBarInitialized = true
	container.PrimaryBar = primaryBar
	container.SecondaryBar = secondaryBar
	Mixin(container, SCMResourceBarControllerMixin)
	container:Initialize()
end

function SCM:RefreshResourceBarConfig()
	local container = _G[RESOURCE_BAR_FRAME_NAME]
	if not container then
		return
	end

	if not container.SCMResourceBarInitialized then
		self:InitializeResourceBars()
		container = _G[RESOURCE_BAR_FRAME_NAME]
		if not container or not container.SCMResourceBarInitialized then
			return
		end
	end

	container:RefreshResourceBars()
end

function SCM:SetPrimaryResourceBarColorOverride(r, g, b)
	self.primaryResourceBarColorOverride = {
		r = r,
		g = g,
		b = b,
	}

	self:RefreshResourceBarConfig()
	return true
end

function SCM:ClearPrimaryResourceBarColorOverride()
	if not self.primaryResourceBarColorOverride then
		return
	end

	self.primaryResourceBarColorOverride = nil
	self:RefreshResourceBarConfig()
	return true
end

function SCM:SetPrimaryResourceBarTextOverride(text)
	if not text then
		return
	end

	self.primaryResourceBarTextOverride = tostring(text)
	self:RefreshResourceBarConfig()
	return true
end

function SCM:ClearPrimaryResourceBarTextOverride()
	if not self.primaryResourceBarTextOverride then
		return
	end

	self.primaryResourceBarTextOverride = nil
	self:RefreshResourceBarConfig()
	return true
end
