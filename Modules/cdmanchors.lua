local SCM = select(2, ...)

local LibCustomGlow = LibStub("LibCustomGlow-1.0")
local Cache = SCM.Cache

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

local function ApplyManagedAnchorPoint(child)
	local anchorFrame = child.SCMAnchorFrame
	local anchorData = child.SCMAnchorData
	if not anchorFrame or not anchorData then
		return
	end

	anchorFrame.ClearAllPoints(child)
	anchorFrame.SetPoint(
		child,
		anchorData[1],
		anchorData[2],
		anchorData[3],
		SCM:PixelPerfect(anchorData[4]),
		SCM:PixelPerfect(anchorData[5])
	)
end

local function OnManagedAnchorChildSetSize(child)
	local anchorFrame = child.SCMAnchorFrame
	if anchorFrame then
		anchorFrame.SetSize(child, SCM:PixelPerfect(child.width), SCM:PixelPerfect(child.height))
	end
end

local function OnManagedAnchorChildSetWidth(child)
	local anchorFrame = child.SCMAnchorFrame
	if anchorFrame then
		anchorFrame.SetWidth(child, SCM:PixelPerfect(child.width))
	end
end

local function OnManagedAnchorChildSetHeight(child)
	local anchorFrame = child.SCMAnchorFrame
	if anchorFrame then
		anchorFrame.SetHeight(child, SCM:PixelPerfect(child.height))
	end
end

function SCM:UpdateManagedAnchorChild(child, groupAnchor, startPoint, offsetX, offsetY, width, height)
	child.width = width
	child.height = height
	child.SCMAnchorFrame = groupAnchor
	child:SetScale(Cache.cachedViewerScale or 1)
	child:SetSize(self:PixelPerfect(width), self:PixelPerfect(height))

	if not child.SCMSizeHook and not child.SCMCustom then
		child.SCMSizeHook = true
		hooksecurefunc(child, "SetSize", OnManagedAnchorChildSetSize)
		hooksecurefunc(child, "SetWidth", OnManagedAnchorChildSetWidth)
		hooksecurefunc(child, "SetHeight", OnManagedAnchorChildSetHeight)
	end

	if not child.SCMPointHook and not child.SCMCustom then
		child.SCMPointHook = true
		hooksecurefunc(child, "SetPoint", ApplyManagedAnchorPoint)
		hooksecurefunc(child, "ClearAllPoints", ApplyManagedAnchorPoint)
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

local function OnAnchorDebugTextureShow(self)
	local anchorFrame = self:GetParent()
	if not anchorFrame then
		return
	end

	anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
	LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
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
		anchorFrame:SetScale(Cache.cachedViewerScale or 1)

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
		local anchorID = target:match("ANCHOR:(%d+)")
		target = anchorID and self:GetAnchor(tonumber(anchorID)) or _G[target] or SCM[target]

		if anchorID and target then
			anchorFrame:SetScale(target:GetEffectiveScale())
		end
	end

	target = target or UIParent

	local pivot = (PIVOT_MAP[growDir] and PIVOT_MAP[growDir][point]) or point

	local xOffsetMultiplier = 0
	if growDir == "LEFT" then
		xOffsetMultiplier = (point == "TOPLEFT" and 1) or ((point == "TOP" or point == "BOTTOM" or point == "CENTER") and 0.5) or 0
	elseif growDir == "RIGHT" then
		xOffsetMultiplier = (point == "TOPRIGHT" and -1) or ((point == "TOP" or point == "BOTTOM" or point == "CENTER") and -0.5) or 0
	end

	if resetSize then
		anchorFrame:SetSize(SCM:PixelPerfect(iconSize), SCM:PixelPerfect(iconSize))
	else
		anchorFrame:SetSize(SCM:PixelPerfect(max(anchorFrame:GetWidth(), iconSize)), SCM:PixelPerfect(max(anchorFrame:GetHeight(), iconSize)))
	end
	anchorFrame:SetScale(Cache.cachedViewerScale or 1)
	anchorFrame:ClearAllPoints()
	anchorFrame:SetPoint(pivot, target, relativePoint, xOffset + ((iconSize or 0) * xOffsetMultiplier), yOffset)
	anchorFrame:Show()

	if self.OptionsFrame ~= nil and self.OptionsFrame:IsShown() and not anchorFrame.isGlowActive and self.db.global.options.showAnchorHighlight then
		anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
		LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
		LibCustomGlow.PixelGlow_Start(anchorFrame, nil, nil, nil, nil, nil, nil, nil, nil, "SCM")
	end

	return anchorFrame
end
