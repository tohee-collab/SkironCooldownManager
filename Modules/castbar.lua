local addonName, SCM = ...
local LSM = LibStub("LibSharedMedia-3.0")

local castBarHooksSet

local CAST_START_EVENTS = {
	UNIT_SPELLCAST_START = true,
	UNIT_SPELLCAST_INTERRUPTIBLE = true,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
	UNIT_SPELLCAST_SENT = true,
}

local CAST_STOP_EVENTS = {
	UNIT_SPELLCAST_STOP = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local function GetCastBarOptions()
	return SCM.db and SCM.db.global and SCM.db.global.options and SCM.db.global.options.castBar
end

local function GetFillColor()
	local options = GetCastBarOptions()
	local color = options and options.fgColor
	return color or { r = 0.5, g = 0.5, b = 1, a = 1 }
end

local function GetBackgroundColor()
	local options = GetCastBarOptions()
	local color = options and options.bgColor
	return color or { r = 0, g = 0, b = 0, a = 0.8 }
end

local function GetInterruptColor()
	local options = GetCastBarOptions()
	local color = options and options.interruptColor
	return color or { r = 1, g = 0.25, b = 0.25, a = 1 }
end

local function ResolveFrameReference(reference)
	if type(reference) == "table" then
		return reference
	end

	if type(reference) ~= "string" or reference == "" or reference == "NONE" then
		return nil
	end

	local anchorID = reference:match("ANCHOR:(%d+)")
	if anchorID then
		return SCM:GetAnchor(tonumber(anchorID))
	end

	return _G[reference] or SCM[reference]
end

local function ApplyAnchors(frame, anchors, defaultRelativeFrame)
	if not frame or type(anchors) ~= "table" then
		return
	end

	local point = anchors[1] or "CENTER"
	local relativeFrame = ResolveFrameReference(anchors[2])
	if not relativeFrame and defaultRelativeFrame then
		relativeFrame = defaultRelativeFrame
	end

	frame:ClearAllPoints()
	frame:SetPoint(point, relativeFrame or UIParent, anchors[3] or point, anchors[4] or 0, anchors[5] or 0)
end

local function ApplyCastBarTextAnchor(frame, anchors, relativeFrame)
	if not frame or type(anchors) ~= "table" or not relativeFrame then
		return
	end

	frame:ClearAllPoints()
	frame:SetPoint(anchors[1] or "CENTER", relativeFrame, anchors[2] or anchors[1] or "CENTER", anchors[3] or 0, anchors[4] or 0)
end

local function GetTexturePath(textureName)
	return LSM:Fetch("statusbar", textureName) or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function GetFontPath(fontName)
	return LSM:Fetch("font", fontName) or STANDARD_TEXT_FONT
end

local function ClearPips()
	local castBar = SCM.CastBar
	if not castBar or not castBar.Pips then
		return
	end

	for _, pip in ipairs(castBar.Pips) do
		pip:Hide()
		pip:SetParent(nil)
	end

	wipe(castBar.Pips)
end

local function CreatePips(empoweredStages)
	local castBar = SCM.CastBar
	if not castBar or type(empoweredStages) ~= "table" then
		return
	end

	ClearPips()

	local totalWidth = castBar.Status:GetWidth()
	local totalHeight = castBar.Status:GetHeight()
	local cumulativePercentage = 0

	for i, stageProportion in ipairs(empoweredStages) do
		if i < #empoweredStages then
			cumulativePercentage = cumulativePercentage + stageProportion

			local pip = castBar.Status:CreateTexture(nil, "OVERLAY")
			pip:SetColorTexture(1, 1, 1, 0.9)
			pip:SetSize(1, max(totalHeight - 2, 1))
			pip:SetPoint("LEFT", castBar.Status, "LEFT", totalWidth * cumulativePercentage, 0)
			pip:Show()

			castBar.Pips[#castBar.Pips + 1] = pip
		end
	end
end

local function UpdateTextLayout()
	local castBar = SCM.CastBar
	local options = GetCastBarOptions()
	if not castBar or not options then
		return
	end

	local fontPath = GetFontPath(options.font)
	local fontSize = options.fontSize or 12
	local fontOutline = options.fontOutline or ""
	local statusWidth = max(castBar.Status:GetWidth(), 1)

	castBar.SpellNameText:SetFont(fontPath, fontSize, fontOutline)
	castBar.SpellNameText:SetJustifyH("LEFT")
	castBar.SpellNameText:SetWordWrap(false)
	castBar.SpellNameText:SetWidth(max(statusWidth - 54, 1))
	castBar.SpellNameText:SetShadowColor(0, 0, 0, 1)
	castBar.SpellNameText:SetShadowOffset(1, -1)
	ApplyCastBarTextAnchor(castBar.SpellNameText, options.spellName and options.spellName.anchors, castBar.Status)
	castBar.SpellNameText:SetShown(not not (options.spellName and options.spellName.enable))

	castBar.CastDurationText:SetFont(fontPath, fontSize, fontOutline)
	castBar.CastDurationText:SetJustifyH("RIGHT")
	castBar.CastDurationText:SetWordWrap(false)
	castBar.CastDurationText:SetWidth(min(statusWidth, 54))
	castBar.CastDurationText:SetShadowColor(0, 0, 0, 1)
	castBar.CastDurationText:SetShadowOffset(1, -1)
	ApplyCastBarTextAnchor(castBar.CastDurationText, options.castDuration and options.castDuration.anchors, castBar.Status)
	castBar.CastDurationText:SetShown(not not (options.castDuration and options.castDuration.enable))
end

local function GetMatchedCastBarWidth()
	local options = GetCastBarOptions()
	if not options or not options.matchParentWidth then
		return
	end

	local anchorFrame = ResolveFrameReference(options.anchors and options.anchors[2])
	if not anchorFrame or not anchorFrame.GetWidth then
		return
	end

	local anchorWidth = anchorFrame:GetWidth()
	if anchorWidth and anchorWidth > 0 then
		return anchorWidth
	end
end

local function UpdateStatusBarLook(fillColor, bgColor)
	local castBar = SCM.CastBar
	local options = GetCastBarOptions()
	local globalOptions = SCM.db and SCM.db.global and SCM.db.global.options
	if not castBar or not options or not globalOptions then
		return
	end

	local borderSize = max((SCM:PixelPerfect() or 1) * (globalOptions.borderSize or 0), 0)
	local texturePath = GetTexturePath(options.texture)
	local borderColor = options.borderColor or { r = 0, g = 0, b = 0, a = 1 }
	local backgroundColor = bgColor or GetBackgroundColor()
	local activeFillColor = fillColor or GetFillColor()
	local width = GetMatchedCastBarWidth() or options.width or 270

	castBar:SetSize(SCM:PixelPerfect(width), SCM:PixelPerfect(options.height or 24))
	ApplyAnchors(castBar, options.anchors)

	castBar:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = borderSize,
	})
	castBar:SetBackdropBorderColor(borderColor.r or 0, borderColor.g or 0, borderColor.b or 0, borderColor.a or 1)

	castBar.Background:ClearAllPoints()
	castBar.Background:SetPoint("TOPLEFT", castBar, "TOPLEFT", borderSize, -borderSize)
	castBar.Background:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -borderSize, borderSize)
	castBar.Background:SetColorTexture(backgroundColor.r or 0, backgroundColor.g or 0, backgroundColor.b or 0, backgroundColor.a or 0.8)

	castBar.Status:ClearAllPoints()
	castBar.Status:SetPoint("TOPLEFT", castBar, "TOPLEFT", borderSize, -borderSize)
	castBar.Status:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -borderSize, borderSize)
	castBar.Status:SetStatusBarTexture(texturePath)
	castBar.Status:SetStatusBarColor(activeFillColor.r or 1, activeFillColor.g or 1, activeFillColor.b or 1, activeFillColor.a or 1)

	UpdateTextLayout()
end

local function HideCastBar()
	local castBar = SCM.CastBar
	if not castBar then
		return
	end

	ClearPips()
	castBar:SetScript("OnUpdate", nil)
	castBar.Status:SetValue(0)
	castBar.SpellNameText:SetText("")
	castBar.CastDurationText:SetText("")
	castBar:Hide()
end

local function FormatDurationText(remainingDuration)
	if remainingDuration < 5 then
		return string.format("%.1f", remainingDuration)
	end

	return string.format("%.0f", remainingDuration)
end

local function StartCast(durationInfo, spellName, fillColor, isChannel, empoweredStages)
	local castBar = SCM.CastBar
	if not castBar or not durationInfo then
		return
	end

	local totalDuration = durationInfo:GetTotalDuration()
	if not totalDuration or totalDuration <= 0 then
		return
	end

	UpdateStatusBarLook(fillColor)

	if empoweredStages then
		CreatePips(empoweredStages)
	else
		ClearPips()
	end

	castBar.Status:SetMinMaxValues(0, totalDuration)
	castBar.SpellNameText:SetText(spellName or "")
	castBar.CastDurationText:SetText(FormatDurationText(totalDuration))
	castBar:SetScript("OnUpdate", function()
		local remainingDuration = max(durationInfo:GetRemainingDuration(), 0)
		if isChannel then
			castBar.Status:SetValue(remainingDuration)
		else
			castBar.Status:SetValue(totalDuration - remainingDuration)
		end

		if castBar.CastDurationText:IsShown() then
			castBar.CastDurationText:SetText(FormatDurationText(remainingDuration))
		end

		if remainingDuration <= 0 then
			HideCastBar()
		end
	end)
	castBar:Show()
end

local function UpdateCastBarValues(_, event)
	local castBar = SCM.CastBar
	if not castBar then
		return
	end

	if CAST_START_EVENTS[event] then
		local durationInfo = UnitCastingDuration("player")
		local spellName, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("player")
		if not durationInfo or not spellName then
			return
		end

		StartCast(durationInfo, spellName, notInterruptible and GetInterruptColor() or GetFillColor(), false)
		return
	end

	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		local durationInfo = UnitChannelDuration("player")
		local spellName = UnitChannelInfo("player")
		if not durationInfo or not spellName then
			return
		end

		StartCast(durationInfo, spellName, GetFillColor(), true)
		return
	end

	if event == "UNIT_SPELLCAST_EMPOWER_START" then
		local durationInfo = UnitEmpoweredChannelDuration("player")
		local spellName = UnitChannelInfo("player")
		local empoweredStages = UnitEmpoweredStagePercentages("player")
		if not durationInfo or not spellName then
			return
		end

		StartCast(durationInfo, spellName, GetFillColor(), true, empoweredStages)
		return
	end

	if CAST_STOP_EVENTS[event] then
		HideCastBar()
	end
end

function SCM:RefreshCastBarWidth(delay)
	local castBar = self.CastBar
	local options = GetCastBarOptions()
	if not castBar or not options or not options.matchParentWidth then
		return
	end

	C_Timer.After(delay or 0.05, function()
		local anchorWidth = GetMatchedCastBarWidth()
		if anchorWidth and anchorWidth > 0 then
			castBar:SetWidth(self:PixelPerfect(anchorWidth))
			UpdateTextLayout()
			if castBar:IsShown() and castBar.Status:GetStatusBarTexture() then
				CreatePips(UnitEmpoweredStagePercentages("player"))
			end
		end
	end)
end

local function EnsureHooks()
	if castBarHooksSet then
		return
	end

	castBarHooksSet = true

	if EditModeManagerFrame then
		hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
			if not InCombatLockdown() then
				SCM:RefreshCastBarWidth()
			end
		end)
		hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
			if not InCombatLockdown() then
				SCM:RefreshCastBarWidth()
			end
		end)
	end
end

function SCM:CreateCastBar()
	if self.CastBar then
		self:UpdateCastBar()
		return self.CastBar
	end

	EnsureHooks()

	local castBar = CreateFrame("Frame", "SCM_CastBar", UIParent, "BackdropTemplate")
	castBar:SetFrameStrata("HIGH")
	castBar.Pips = {}

	castBar.Background = castBar:CreateTexture(nil, "BACKGROUND")

	castBar.Status = CreateFrame("StatusBar", nil, castBar)
	castBar.Status:SetFrameLevel(castBar:GetFrameLevel() + 1)
	castBar.Status:SetMinMaxValues(0, 1)
	castBar.Status:SetValue(0)

	castBar.SpellNameText = castBar.Status:CreateFontString(nil, "OVERLAY")
	castBar.CastDurationText = castBar.Status:CreateFontString(nil, "OVERLAY")

	self.CastBar = castBar
	self:UpdateCastBar()
	return castBar
end

function SCM:UpdateCastBar()
	local castBar = self.CastBar
	local options = GetCastBarOptions()
	if not castBar or not options then
		return
	end

	UpdateStatusBarLook(GetFillColor())

	if options.enable then
		castBar:UnregisterAllEvents()
		HideCastBar()
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
		castBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
		castBar:SetScript("OnEvent", UpdateCastBarValues)
		castBar:Hide()
		self:RefreshCastBarWidth(0.1)
	else
		castBar:SetScript("OnEvent", nil)
		castBar:UnregisterAllEvents()
		HideCastBar()
	end
end

local function OnProfileChanged()
	if SCM.CastBar then
		SCM:UpdateCastBar()
	end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	if not SCM.db then
		return
	end

	SCM.db.RegisterCallback(SCM, "OnProfileChanged", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileCopied", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileReset", OnProfileChanged)

	SCM:CreateCastBar()
end)
