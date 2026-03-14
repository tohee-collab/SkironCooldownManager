local addonName, SCM = ...
local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

SCM.MainTabs.CastBar = { value = "CastBar", text = "Cast Bar", order = 6, subgroups = {} }

local FONT_OUTLINES = {
	[""] = "None",
	OUTLINE = "Outline",
	THICKOUTLINE = "Thick Outline",
	MONOCHROME = "Monochrome",
}

local function RefreshCastBar()
	SCM:CreateCastBar()
	SCM:UpdateCastBar()
end

local function AddHeader(widget, text)
	local label = AceGUI:Create("Label")
	label:SetRelativeWidth(1.0)
	label:SetHeight(18)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	widget:AddChild(label)
end

local function AddAnchorControls(parent, title, anchors, refreshFn, relativeFrameHelp)
	local anchorGroup = AceGUI:Create("InlineGroup")
	anchorGroup:SetTitle(title)
	anchorGroup:SetFullWidth(true)
	anchorGroup:SetLayout("flow")
	parent:AddChild(anchorGroup)

	local point = AceGUI:Create("Dropdown")
	point:SetRelativeWidth(0.33)
	point:SetLabel("Point")
	point:SetList(SCM.Constants.AnchorPoints)
	point:SetValue(anchors[1])
	point:SetCallback("OnValueChanged", function(_, _, value)
		anchors[1] = value
		refreshFn()
	end)
	anchorGroup:AddChild(point)

	local relativeTo = AceGUI:Create("EditBox")
	relativeTo:SetRelativeWidth(0.33)
	relativeTo:SetLabel(relativeFrameHelp or "Anchor Frame")
	relativeTo:SetText(anchors[2] or "")
	relativeTo:SetCallback("OnEnterPressed", function(self, _, text)
		anchors[2] = text ~= "" and text or nil
		self:SetText(anchors[2] or "")
		refreshFn()
	end)
	anchorGroup:AddChild(relativeTo)

	local relativePoint = AceGUI:Create("Dropdown")
	relativePoint:SetRelativeWidth(0.33)
	relativePoint:SetLabel("Relative Point")
	relativePoint:SetList(SCM.Constants.AnchorPoints)
	relativePoint:SetValue(anchors[3])
	relativePoint:SetCallback("OnValueChanged", function(_, _, value)
		anchors[3] = value
		refreshFn()
	end)
	anchorGroup:AddChild(relativePoint)

	local xOffset = AceGUI:Create("Slider")
	xOffset:SetRelativeWidth(0.5)
	xOffset:SetLabel("X Offset")
	xOffset:SetSliderValues(-500, 500, 1)
	xOffset:SetValue(anchors[4] or 0)
	xOffset:SetCallback("OnValueChanged", function(_, _, value)
		anchors[4] = value
		refreshFn()
	end)
	anchorGroup:AddChild(xOffset)

	local yOffset = AceGUI:Create("Slider")
	yOffset:SetRelativeWidth(0.5)
	yOffset:SetLabel("Y Offset")
	yOffset:SetSliderValues(-500, 500, 1)
	yOffset:SetValue(anchors[5] or 0)
	yOffset:SetCallback("OnValueChanged", function(_, _, value)
		anchors[5] = value
		refreshFn()
	end)
	anchorGroup:AddChild(yOffset)
end

local function AddCastBarTextAnchorControls(parent, title, anchors, refreshFn)
	local anchorGroup = AceGUI:Create("InlineGroup")
	anchorGroup:SetTitle(title)
	anchorGroup:SetFullWidth(true)
	anchorGroup:SetLayout("flow")
	parent:AddChild(anchorGroup)

	local enable = AceGUI:Create("CheckBox")
	enable:SetRelativeWidth(1)
	enable:SetLabel("Enable")
	enable:SetValue(anchors.enable)
	enable:SetCallback("OnValueChanged", function(_, _, value)
		anchors.enable = value
		refreshFn()
	end)
	anchorGroup:AddChild(enable)

	local point = AceGUI:Create("Dropdown")
	point:SetRelativeWidth(0.5)
	point:SetLabel("Point")
	point:SetList(SCM.Constants.AnchorPoints)
	point:SetValue(anchors.anchors[1])
	point:SetCallback("OnValueChanged", function(_, _, value)
		anchors.anchors[1] = value
		refreshFn()
	end)
	anchorGroup:AddChild(point)

	local relativePoint = AceGUI:Create("Dropdown")
	relativePoint:SetRelativeWidth(0.5)
	relativePoint:SetLabel("Relative Point")
	relativePoint:SetList(SCM.Constants.AnchorPoints)
	relativePoint:SetValue(anchors.anchors[2])
	relativePoint:SetCallback("OnValueChanged", function(_, _, value)
		anchors.anchors[2] = value
		refreshFn()
	end)
	anchorGroup:AddChild(relativePoint)

	local xOffset = AceGUI:Create("Slider")
	xOffset:SetRelativeWidth(0.5)
	xOffset:SetLabel("X Offset")
	xOffset:SetSliderValues(-500, 500, 1)
	xOffset:SetValue(anchors.anchors[3] or 0)
	xOffset:SetCallback("OnValueChanged", function(_, _, value)
		anchors.anchors[3] = value
		refreshFn()
	end)
	anchorGroup:AddChild(xOffset)

	local yOffset = AceGUI:Create("Slider")
	yOffset:SetRelativeWidth(0.5)
	yOffset:SetLabel("Y Offset")
	yOffset:SetSliderValues(-500, 500, 1)
	yOffset:SetValue(anchors.anchors[4] or 0)
	yOffset:SetCallback("OnValueChanged", function(_, _, value)
		anchors.anchors[4] = value
		refreshFn()
	end)
	anchorGroup:AddChild(yOffset)
end

local function CastBar(self)
	self:ReleaseChildren()

	local options = SCM.db.global.options.castBar

	local rootGroup = AceGUI:Create("InlineGroup")
	rootGroup:SetLayout("fill")
	rootGroup:SetFullWidth(true)
	rootGroup:SetFullHeight(true)
	self:AddChild(rootGroup)

	local scrollFrame = AceGUI:Create("ScrollFrame")
	scrollFrame:SetLayout("flow")
	rootGroup:AddChild(scrollFrame)

	local help = AceGUI:Create("Label")
	help:SetRelativeWidth(1.0)
	help:SetHeight(24)
	help:SetJustifyH("CENTER")
	help:SetText("|TInterface\\common\\help-i:40:40:0:0|tPress Enter in text fields to apply frame names.")
	scrollFrame:AddChild(help)

	local generalGroup = AceGUI:Create("InlineGroup")
	generalGroup:SetTitle("General")
	generalGroup:SetFullWidth(true)
	generalGroup:SetLayout("flow")
	scrollFrame:AddChild(generalGroup)

	local enable = AceGUI:Create("CheckBox")
	enable:SetRelativeWidth(0.5)
	enable:SetLabel("Enable Cast Bar")
	enable:SetValue(options.enable)
	enable:SetCallback("OnValueChanged", function(_, _, value)
		options.enable = value
		RefreshCastBar()
	end)
	generalGroup:AddChild(enable)

	local matchParentWidth = AceGUI:Create("CheckBox")
	matchParentWidth:SetRelativeWidth(0.5)
	matchParentWidth:SetLabel("Match Parent Width")
	matchParentWidth:SetValue(options.matchParentWidth)
	matchParentWidth:SetCallback("OnValueChanged", function(_, _, value)
		options.matchParentWidth = value
		RefreshCastBar()
	end)
	generalGroup:AddChild(matchParentWidth)

	local width = AceGUI:Create("Slider")
	width:SetRelativeWidth(0.33)
	width:SetLabel("Width")
	width:SetSliderValues(50, 600, 1)
	width:SetValue(options.width or 270)
	width:SetCallback("OnValueChanged", function(_, _, value)
		options.width = value
		RefreshCastBar()
	end)
	generalGroup:AddChild(width)

	local height = AceGUI:Create("Slider")
	height:SetRelativeWidth(0.33)
	height:SetLabel("Height")
	height:SetSliderValues(8, 80, 1)
	height:SetValue(options.height or 24)
	height:SetCallback("OnValueChanged", function(_, _, value)
		options.height = value
		RefreshCastBar()
	end)
	generalGroup:AddChild(height)

	local fontSize = AceGUI:Create("Slider")
	fontSize:SetRelativeWidth(0.33)
	fontSize:SetLabel("Font Size")
	fontSize:SetSliderValues(6, 32, 1)
	fontSize:SetValue(options.fontSize or 12)
	fontSize:SetCallback("OnValueChanged", function(_, _, value)
		options.fontSize = value
		RefreshCastBar()
	end)
	generalGroup:AddChild(fontSize)

	local texture = AceGUI:Create("LSM30_Statusbar")
	texture:SetRelativeWidth(0.5)
	texture:SetLabel("Texture")
	texture:SetList(LSM:HashTable("statusbar"))
	texture:SetValue(options.texture)
	texture:SetCallback("OnValueChanged", function(self, _, value)
		options.texture = value
		self:SetValue(value)
		RefreshCastBar()
	end)
	generalGroup:AddChild(texture)

	local font = AceGUI:Create("LSM30_Font")
	font:SetRelativeWidth(0.25)
	font:SetLabel("Font")
	font:SetList(LSM:HashTable("font"))
	font:SetValue(options.font)
	font:SetCallback("OnValueChanged", function(self, _, value)
		options.font = value
		self:SetValue(value)
		RefreshCastBar()
	end)
	generalGroup:AddChild(font)

	local fontOutline = AceGUI:Create("Dropdown")
	fontOutline:SetRelativeWidth(0.25)
	fontOutline:SetLabel("Font Outline")
	fontOutline:SetList(FONT_OUTLINES)
	fontOutline:SetValue(options.fontOutline or "")
	fontOutline:SetCallback("OnValueChanged", function(_, _, value)
		options.fontOutline = value
		RefreshCastBar()
	end)
	generalGroup:AddChild(fontOutline)

	local colorGroup = AceGUI:Create("InlineGroup")
	colorGroup:SetTitle("Colors")
	colorGroup:SetFullWidth(true)
	colorGroup:SetLayout("flow")
	scrollFrame:AddChild(colorGroup)

	local fillColor = AceGUI:Create("ColorPicker")
	fillColor:SetRelativeWidth(0.25)
	fillColor:SetLabel("Foreground Color")
	fillColor:SetHasAlpha(true)
	fillColor:SetColor(options.fgColor.r, options.fgColor.g, options.fgColor.b, options.fgColor.a)
	fillColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
		options.fgColor = { r = r, g = g, b = b, a = a }
		RefreshCastBar()
	end)
	colorGroup:AddChild(fillColor)

	local bgColor = AceGUI:Create("ColorPicker")
	bgColor:SetRelativeWidth(0.25)
	bgColor:SetLabel("Background Color")
	bgColor:SetHasAlpha(true)
	bgColor:SetColor(options.bgColor.r, options.bgColor.g, options.bgColor.b, options.bgColor.a)
	bgColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
		options.bgColor = { r = r, g = g, b = b, a = a }
		RefreshCastBar()
	end)
	colorGroup:AddChild(bgColor)

	local interruptColor = AceGUI:Create("ColorPicker")
	interruptColor:SetRelativeWidth(0.25)
	interruptColor:SetLabel("Interrupt Color")
	interruptColor:SetHasAlpha(true)
	interruptColor:SetColor(options.interruptColor.r, options.interruptColor.g, options.interruptColor.b, options.interruptColor.a)
	interruptColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
		options.interruptColor = { r = r, g = g, b = b, a = a }
		RefreshCastBar()
	end)
	colorGroup:AddChild(interruptColor)

	local borderColor = AceGUI:Create("ColorPicker")
	borderColor:SetRelativeWidth(0.25)
	borderColor:SetLabel("Border Color")
	borderColor:SetHasAlpha(true)
	borderColor:SetColor(options.borderColor.r, options.borderColor.g, options.borderColor.b, options.borderColor.a)
	borderColor:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
		options.borderColor = { r = r, g = g, b = b, a = a }
		RefreshCastBar()
	end)
	colorGroup:AddChild(borderColor)

	local anchorsGroup = AceGUI:Create("InlineGroup")
	anchorsGroup:SetTitle("Anchors")
	anchorsGroup:SetFullWidth(true)
	anchorsGroup:SetLayout("flow")
	scrollFrame:AddChild(anchorsGroup)

	AddHeader(anchorsGroup, "Supports frame names like `UIParent` and addon anchors like `ANCHOR:1`.")
	AddAnchorControls(anchorsGroup, "Cast Bar Anchor", options.anchors, RefreshCastBar)
	AddHeader(anchorsGroup, "Spell name and duration are always anchored to the cast bar.")
	AddCastBarTextAnchorControls(anchorsGroup, "Spell Name Anchor", options.spellName, RefreshCastBar)
	AddCastBarTextAnchorControls(anchorsGroup, "Cast Duration Anchor", options.castDuration, RefreshCastBar)
end

SCM.MainTabs.CastBar.callback = CastBar
