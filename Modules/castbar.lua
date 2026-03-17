local addonName, SCM = ...
local LSM = LibStub("LibSharedMedia-3.0")

local castBarHooksSet

local CAST_START_EVENTS = {
	UNIT_SPELLCAST_START           = true,
	UNIT_SPELLCAST_INTERRUPTIBLE   = true,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
	UNIT_SPELLCAST_SENT            = true,
}

local CAST_STOP_EVENTS = {
	UNIT_SPELLCAST_STOP          = true,
	UNIT_SPELLCAST_CHANNEL_STOP  = true,
	UNIT_SPELLCAST_INTERRUPTED   = true,
	UNIT_SPELLCAST_FAILED        = true,
	UNIT_SPELLCAST_EMPOWER_STOP  = true,
}

local DEFAULT_ICON_POSITION = "LEFT"
local ICON_SPACING = 1

local function GetCastBarOptions()
	return SCM.db
		and SCM.db.global
		and SCM.db.global.options
		and SCM.db.global.options.castBar
end

local function GetCastBarColor(key, fallback)
	local options = GetCastBarOptions()
	return (options and options[key]) or fallback
end

local function GetIconOptions()
	local options = GetCastBarOptions()
	if not options then return end

	local ico = options.icon
	if type(ico) ~= "table" then
		ico = {}
		options.icon = ico
	end

	if ico.enable        == nil then ico.enable        = true end
	if ico.matchBarHeight == nil then ico.matchBarHeight = true end
	if ico.size          == nil then ico.size          = options.height or 24 end
	if ico.zoom          == nil then ico.zoom          = 0.08 end
	if ico.position ~= "LEFT" and ico.position ~= "RIGHT" then
		ico.position = DEFAULT_ICON_POSITION
	end

	return ico
end

local function ResolveFrameReference(ref)
	if type(ref) == "table" then return ref end
	if type(ref) ~= "string" or ref == "" or ref == "NONE" then return nil end

	local anchorID = ref:match("ANCHOR:(%d+)")
	if anchorID then return SCM:GetAnchor(tonumber(anchorID)) end

	return _G[ref] or SCM[ref]
end

local function ApplyAnchors(frame, anchors, defaultRelativeFrame)
	if not frame or type(anchors) ~= "table" then return end

	local relFrame = ResolveFrameReference(anchors[2]) or defaultRelativeFrame
	frame:ClearAllPoints()
	frame:SetPoint(anchors[1] or "CENTER", relFrame or UIParent, anchors[3] or anchors[1] or "CENTER", anchors[4] or 0, anchors[5] or 0)
end

local function ApplyRelativeAnchor(frame, anchors, relativeFrame)
	if not frame or type(anchors) ~= "table" or not relativeFrame then return end

	frame:ClearAllPoints()
	frame:SetPoint(anchors[1] or "CENTER", relativeFrame, anchors[2] or anchors[1] or "CENTER", anchors[3] or 0, anchors[4] or 0)
end

local function GetIconSize()
	local options = GetCastBarOptions()
	local ico     = GetIconOptions()
	if not options or not ico then return 0 end

	return max(ico.matchBarHeight and (options.height or 24) or (ico.size or options.height or 24), 1)
end

local function GetIconZoom()
	local ico  = GetIconOptions()
	if not ico then return 0 end
	return max(min(ico.zoom or 0, 0.49), 0)
end

local function GetIconPosition()
	local ico = GetIconOptions()
	return (ico and ico.position == "RIGHT") and "RIGHT" or DEFAULT_ICON_POSITION
end

local function GetTexturePath(name)
	return LSM:Fetch("statusbar", name) or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function GetFontPath(name)
	return LSM:Fetch("font", name) or STANDARD_TEXT_FONT
end

local function ClearPips()
	local castBar = SCM.CastBar
	if not castBar then return end

	for _, pip in ipairs(castBar.Pips) do
		pip:Hide()
		pip:SetParent(nil)
	end
	wipe(castBar.Pips)
end

local function CreatePips(empoweredStages)
	local castBar = SCM.CastBar
	if not castBar or type(empoweredStages) ~= "table" then return end

	ClearPips()

	local totalWidth  = castBar.Status:GetWidth()
	local totalHeight = castBar.Status:GetHeight()
	local cumulative  = 0

	for i, proportion in ipairs(empoweredStages) do
		if i < #empoweredStages then
			cumulative = cumulative + proportion
			local pip = castBar.Status:CreateTexture(nil, "OVERLAY")
			pip:SetColorTexture(1, 1, 1, 0.9)
			pip:SetSize(1, max(totalHeight - 2, 1))
			pip:SetPoint("LEFT", castBar.Status, "LEFT", totalWidth * cumulative, 0)
			pip:Show()
			castBar.Pips[#castBar.Pips + 1] = pip
		end
	end
end

local function ApplyTextStyle(fs, fontPath, fontSize, fontOutline, justify, width)
	fs:SetFont(fontPath, fontSize, fontOutline)
	fs:SetJustifyH(justify)
	fs:SetWordWrap(false)
	fs:SetWidth(width)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
end

local function UpdateTextLayout()
	local castBar = SCM.CastBar
	local options = GetCastBarOptions()
	if not castBar or not options then return end

	local fontPath    = GetFontPath(options.font)
	local fontSize    = options.fontSize or 12
	local fontOutline = options.fontOutline or ""
	local statusWidth = max(castBar.Status:GetWidth(), 1)

	ApplyTextStyle(castBar.SpellNameText,    fontPath, fontSize, fontOutline, "LEFT",  max(statusWidth - 54, 1))
	ApplyTextStyle(castBar.CastDurationText, fontPath, fontSize, fontOutline, "RIGHT", min(statusWidth, 54))

	local spellName   = options.spellName
	local castDuration = options.castDuration

	ApplyRelativeAnchor(castBar.SpellNameText,    spellName    and spellName.anchors,    castBar.Status)
	ApplyRelativeAnchor(castBar.CastDurationText, castDuration and castDuration.anchors, castBar.Status)

	castBar.SpellNameText:SetShown(not not (spellName    and spellName.enable))
	castBar.CastDurationText:SetShown(not not (castDuration and castDuration.enable))
end

local function GetMatchedCastBarWidth()
	local options = GetCastBarOptions()
	if not options or not options.matchParentWidth then return end

	local anchorFrame = ResolveFrameReference(options.anchors and options.anchors[2])
	if not anchorFrame or not anchorFrame.GetWidth then return end

	local w = anchorFrame:GetWidth()
	return (w and w > 0) and w or nil
end

local function UpdateIconTexture(spellTexture)
	local castBar = SCM.CastBar
	local ico     = GetIconOptions()
	if not castBar or not castBar.IconFrame or not ico then return end

	castBar.CurrentSpellTexture = spellTexture

	if ico.enable and spellTexture then
		castBar.IconFrame.Icon:SetTexture(spellTexture)
		castBar.IconFrame:Show()
	else
		castBar.IconFrame.Icon:SetTexture(nil)
		castBar.IconFrame:Hide()
	end
end

local function LayoutCastBarContents(borderSize)
	local castBar = SCM.CastBar
	local ico     = GetIconOptions()
	if not castBar or not castBar.IconFrame or not ico then return end

	local innerWidth  = max(castBar:GetWidth()  - borderSize * 2, 1)
	local innerHeight = max(castBar:GetHeight() - borderSize * 2, 1)
	local spacing     = ico.enable and min(SCM:PixelPerfect(ICON_SPACING), max(innerWidth - 1, 0)) or 0
	local iconSize    = 0
	local iconZoom    = GetIconZoom()

	if ico.enable then
		iconSize = min(SCM:PixelPerfect(GetIconSize()), innerHeight, max(innerWidth - spacing - 1, 0))
	end

	castBar.Status:ClearAllPoints()
	castBar.IconFrame:ClearAllPoints()
	castBar.IconFrame.Icon:ClearAllPoints()
	castBar.IconFrame.Icon:SetAllPoints(castBar.IconFrame)
	castBar.IconFrame.Icon:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)

	if ico.enable and iconSize > 0 then
		castBar.IconFrame:SetSize(iconSize, iconSize)
		if GetIconPosition() == "RIGHT" then
			castBar.IconFrame:SetPoint("RIGHT",      castBar, "RIGHT",      -borderSize, 0)
			castBar.Status:SetPoint("TOPLEFT",       castBar, "TOPLEFT",    borderSize, -borderSize)
			castBar.Status:SetPoint("BOTTOMRIGHT",   castBar, "BOTTOMRIGHT", -(borderSize + iconSize + spacing), borderSize)
		else
			castBar.IconFrame:SetPoint("LEFT",       castBar, "LEFT",       borderSize, 0)
			castBar.Status:SetPoint("TOPLEFT",       castBar, "TOPLEFT",    borderSize + iconSize + spacing, -borderSize)
			castBar.Status:SetPoint("BOTTOMRIGHT",   castBar, "BOTTOMRIGHT", -borderSize, borderSize)
		end
	else
		castBar.Status:SetPoint("TOPLEFT",     castBar, "TOPLEFT",    borderSize, -borderSize)
		castBar.Status:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -borderSize, borderSize)
	end

	UpdateIconTexture(castBar.CurrentSpellTexture)
end

local function UpdateStatusBarLook(fillColor, bgColor)
	local castBar     = SCM.CastBar
	local options     = GetCastBarOptions()
	local globalOpts  = SCM.db and SCM.db.global and SCM.db.global.options
	if not castBar or not options or not globalOpts then return end

	local borderSize    = max((SCM:PixelPerfect() or 1) * (globalOpts.borderSize or 0), 0)
	local texturePath   = GetTexturePath(options.texture)
	local borderColor   = options.borderColor or { r = 0, g = 0, b = 0, a = 1 }
	local bgCol         = bgColor    or GetCastBarColor("bgColor", { r = 0,   g = 0,   b = 0,   a = 0.8 })
	local fgCol         = fillColor  or castBar.CurrentFillColor or GetCastBarColor("fgColor", { r = 0.5, g = 0.5, b = 1,   a = 1   })
	local width         = GetMatchedCastBarWidth() or options.width or 270

	castBar.CurrentFillColor = fgCol
	castBar:SetSize(SCM:PixelPerfect(width), SCM:PixelPerfect(options.height or 24))
	ApplyAnchors(castBar, options.anchors)

	castBar:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = borderSize })
	castBar:SetBackdropBorderColor(borderColor.r or 0, borderColor.g or 0, borderColor.b or 0, borderColor.a or 1)

	castBar.Background:ClearAllPoints()
	castBar.Background:SetPoint("TOPLEFT",     castBar, "TOPLEFT",    borderSize,  -borderSize)
	castBar.Background:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -borderSize,  borderSize)
	castBar.Background:SetColorTexture(bgCol.r or 0, bgCol.g or 0, bgCol.b or 0, bgCol.a or 0.8)

	LayoutCastBarContents(borderSize)
	castBar.Status:SetStatusBarTexture(texturePath)
	castBar.Status:SetStatusBarColor(fgCol.r or 1, fgCol.g or 1, fgCol.b or 1, fgCol.a or 1)

	UpdateTextLayout()
end

local function HideCastBar()
	local castBar = SCM.CastBar
	if not castBar then return end

	ClearPips()
	castBar:SetScript("OnUpdate", nil)
	castBar.Status:SetValue(0)
	castBar.SpellNameText:SetText("")
	castBar.CastDurationText:SetText("")
	castBar.CurrentFillColor = nil
	UpdateIconTexture(nil)
	castBar:Hide()
end

local function FormatDurationText(t)
	return t < 5 and string.format("%.1f", t) or string.format("%.0f", t)
end

local function StartCast(durationInfo, spellName, fillColor, isChannel, empoweredStages, spellTexture)
	local castBar = SCM.CastBar
	if not castBar or not durationInfo then return end

	local totalDuration = durationInfo:GetTotalDuration()
	if not totalDuration or totalDuration <= 0 then return end

	castBar.CurrentFillColor = fillColor
	UpdateStatusBarLook(fillColor)
	UpdateIconTexture(spellTexture)

	if empoweredStages then
		CreatePips(empoweredStages)
	else
		ClearPips()
	end

	castBar.Status:SetMinMaxValues(0, totalDuration)
	castBar.Status:SetValue(isChannel and totalDuration or 0)
	castBar.SpellNameText:SetText(spellName or "")
	castBar.CastDurationText:SetText(FormatDurationText(totalDuration))

	castBar:SetScript("OnUpdate", function()
		local remaining = max(durationInfo:GetRemainingDuration(), 0)
		castBar.Status:SetValue(isChannel and remaining or totalDuration - remaining)

		if castBar.CastDurationText:IsShown() then
			castBar.CastDurationText:SetText(FormatDurationText(remaining))
		end

		if remaining <= 0 then HideCastBar() end
	end)

	castBar:Show()
end

local DEFAULT_FG_COLOR        = { r = 0.5, g = 0.5, b = 1,    a = 1 }
local DEFAULT_INTERRUPT_COLOR = { r = 1,   g = 0.25, b = 0.25, a = 1 }

local function UpdateCastBarValues(_, event)
	if CAST_START_EVENTS[event] then
		local durationInfo                                = UnitCastingDuration("player")
		local spellName, _, spellTexture, _, _, _, _, notInterruptible = UnitCastingInfo("player")
		if not durationInfo or not spellName then return end

		local color = notInterruptible
			and GetCastBarColor("interruptColor", DEFAULT_INTERRUPT_COLOR)
			or  GetCastBarColor("fgColor",        DEFAULT_FG_COLOR)
		StartCast(durationInfo, spellName, color, false, nil, spellTexture)
		return
	end

	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		local durationInfo                = UnitChannelDuration("player")
		local spellName, _, spellTexture  = UnitChannelInfo("player")
		if not durationInfo or not spellName then return end

		StartCast(durationInfo, spellName, GetCastBarColor("fgColor", DEFAULT_FG_COLOR), true, nil, spellTexture)
		return
	end

	if event == "UNIT_SPELLCAST_EMPOWER_START" then
		local durationInfo               = UnitEmpoweredChannelDuration("player")
		local spellName, _, spellTexture = UnitChannelInfo("player")
		local stages                     = UnitEmpoweredStagePercentages("player")
		if not durationInfo or not spellName then return end

		StartCast(durationInfo, spellName, GetCastBarColor("fgColor", DEFAULT_FG_COLOR), true, stages, spellTexture)
		return
	end

	if CAST_STOP_EVENTS[event] then
		HideCastBar()
	end
end

local function ResumeCurrentCast()
	local durationInfo                                               = UnitCastingDuration("player")
	local spellName, _, spellTexture, _, _, _, _, notInterruptible  = UnitCastingInfo("player")
	if durationInfo and spellName then
		local color = notInterruptible
			and GetCastBarColor("interruptColor", DEFAULT_INTERRUPT_COLOR)
			or  GetCastBarColor("fgColor",        DEFAULT_FG_COLOR)
		StartCast(durationInfo, spellName, color, false, nil, spellTexture)
		return true
	end

	local channelName, _, channelTexture = UnitChannelInfo("player")

	local empoweredDuration = UnitEmpoweredChannelDuration("player")
	if empoweredDuration and channelName then
		StartCast(empoweredDuration, channelName, GetCastBarColor("fgColor", DEFAULT_FG_COLOR), true, UnitEmpoweredStagePercentages("player"), channelTexture)
		return true
	end

	local channelDuration = UnitChannelDuration("player")
	if channelDuration and channelName then
		StartCast(channelDuration, channelName, GetCastBarColor("fgColor", DEFAULT_FG_COLOR), true, nil, channelTexture)
		return true
	end

	return false
end

function SCM:RefreshCastBarWidth(delay)
	local castBar = self.CastBar
	local options = GetCastBarOptions()
	if not castBar or not options or not options.matchParentWidth then return end

	C_Timer.After(delay or 0.05, function()
		local anchorWidth = GetMatchedCastBarWidth()
		if anchorWidth and anchorWidth > 0 then
			UpdateStatusBarLook(castBar.CurrentFillColor)
			if castBar:IsShown() and castBar.Status:GetStatusBarTexture() then
				CreatePips(UnitEmpoweredStagePercentages("player"))
			end
		end
	end)
end

local function EnsureHooks()
	if castBarHooksSet then return end
	castBarHooksSet = true

	if not EditModeManagerFrame then return end

	local function OnEditModeToggle()
		if not InCombatLockdown() then SCM:RefreshCastBarWidth() end
	end

	hooksecurefunc(EditModeManagerFrame, "EnterEditMode", OnEditModeToggle)
	hooksecurefunc(EditModeManagerFrame, "ExitEditMode",  OnEditModeToggle)
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

	castBar.IconFrame      = CreateFrame("Frame", nil, castBar)
	castBar.IconFrame:SetFrameLevel(castBar:GetFrameLevel() + 2)
	castBar.IconFrame.Icon = castBar.IconFrame:CreateTexture(nil, "ARTWORK")

	castBar.SpellNameText    = castBar.Status:CreateFontString(nil, "OVERLAY")
	castBar.CastDurationText = castBar.Status:CreateFontString(nil, "OVERLAY")

	self.CastBar = castBar
	self:UpdateCastBar()
	return castBar
end

function SCM:UpdateCastBar()
	local castBar = self.CastBar
	local options = GetCastBarOptions()
	if not castBar or not options then return end

	UpdateStatusBarLook(GetCastBarColor("fgColor", DEFAULT_FG_COLOR))

	if options.enable then
		castBar:UnregisterAllEvents()
		HideCastBar()

		local events = {
			"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
			"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTIBLE",
			"UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_SENT",
			"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
			"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
		}
		for _, event in ipairs(events) do
			castBar:RegisterUnitEvent(event, "player")
		end

		castBar:SetScript("OnEvent", UpdateCastBarValues)
		if not ResumeCurrentCast() then castBar:Hide() end
		self:RefreshCastBarWidth(0.1)
	else
		castBar:SetScript("OnEvent", nil)
		castBar:UnregisterAllEvents()
		HideCastBar()
	end
end

local function OnProfileChanged()
	if SCM.CastBar then SCM:UpdateCastBar() end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	if not SCM.db then return end

	SCM.db.RegisterCallback(SCM, "OnProfileChanged", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileCopied",  OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileReset",   OnProfileChanged)

	SCM:CreateCastBar()
end)