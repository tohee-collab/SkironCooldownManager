local SCM = select(2, ...)
local LSM = LibStub("LibSharedMedia-3.0")

local originalCooldownFont

local function ApplyChargeAndApplicationStyle(child, options, fontPath)
	if child.ChargeCount and child.ChargeCount.Current and (not child.SCMIconType or child.SCMIconType == "spell") then
		if fontPath then
			child.ChargeCount.Current:SetFont(fontPath, options.chargeFontSize, "OUTLINE")
		end

		child.ChargeCount.Current:ClearAllPoints()
		child.ChargeCount.Current:SetPoint(options.chargePoint, child.Icon, options.chargeRelativePoint, options.chargeXOffset, options.chargeYOffset)
	end

	if child.Applications and child.Applications.Applications then
		if fontPath then
			child.Applications.Applications:SetFont(fontPath, options.chargeFontSize, "OUTLINE")
		end

		child.Applications.Applications:ClearAllPoints()
		child.Applications.Applications:SetPoint(options.chargePoint, child.Icon, options.chargeRelativePoint, options.chargeXOffset, options.chargeYOffset)
	end
end

local function ApplyCooldownStyle(child, options)
	if child.GetCooldownFrame then
		local cooldownFrame = child:GetCooldownFrame()
		cooldownFrame:ClearAllPoints()
		cooldownFrame:SetAllPoints(child.Icon)
		cooldownFrame:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")

		if options.changeCooldownFont then
			local fontPath = LSM:Fetch("font", options.cooldownFont)
			local cooldownFontString = cooldownFrame:GetRegions()
			if cooldownFontString and cooldownFontString.SetFont then
				if not originalCooldownFont then
					originalCooldownFont = { cooldownFontString:GetFont() }
				end
				if options.enableCustomCooldownFont then
					cooldownFontString:SetFont(fontPath, options.cooldownFontSize, "OUTLINE")
				elseif originalCooldownFont then
					cooldownFontString:SetFont(unpack(originalCooldownFont))
				end
			end
		end

		hooksecurefunc(cooldownFrame, "SetCooldown", function(self)
			if options.recolorActiveSwipe then
				self:SetSwipeColor(0, 0, 0, 0.8)

				if self:GetUseAuraDisplayTime() then
					self:SetSwipeColor(unpack(options.activeSwipeColor))
				end
			end
		end)

		hooksecurefunc(cooldownFrame, "Clear", function(self)
			if options.recolorActiveSwipe then
				self:SetSwipeColor(0, 0, 0, 0.8)
			end
		end)
	end
end

function SCM:SkinChild(child, childConfig)
	if C_AddOns.IsAddOnLoaded("ElvUI") and ElvUI[1].private.skins.blizzard.cooldownManager then
		return
	end

	local options = self.db.global.options
	if not options.enableSkinning then
		return
	end

	local borderSize = SCM:PixelPerfect() * options.borderSize
	local borderColor = options.borderColor

	if child.SCMSkinned and self.OptionsFrame ~= nil and self.OptionsFrame:IsShown() then
		if borderSize == 0 then
			child.customBorder:Hide()
		else
			child.customBorder:Show()
			child.customBorder.backdropInfo.edgeSize = borderSize
			child.customBorder:ApplyBackdrop()

			child.customBorder:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
		end

		child.Icon:ClearAllPoints()
		child.Icon:SetPoint("TOPLEFT", child, "TOPLEFT", borderSize, -borderSize)
		child.Icon:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize)
		child.Icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)

		local fontPath = LSM:Fetch("font", options.chargeFont)
		ApplyChargeAndApplicationStyle(child, options, fontPath)
	elseif not child.SCMSkinned then
		child.SCMSkinned = true

		child.Icon:ClearAllPoints()
		child.Icon:SetPoint("TOPLEFT", child, "TOPLEFT", borderSize, -borderSize)
		child.Icon:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize)
		child.Icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)

		if not child.customBorder then
			child.customBorder = CreateFrame("Frame", nil, child, "BackdropTemplate")
			child.customBorder:SetFrameLevel(child:GetFrameLevel() + 1)
			child.customBorder:SetAllPoints(child)
			child.customBorder:SetBackdrop({
				edgeFile = "Interface\\Buttons\\WHITE8x8",
				edgeSize = borderSize,
			})
			child.customBorder:SetBackdropBorderColor(0, 0, 0, 1)
		else
			child.customBorder:SetAlpha(1)
			child.customBorder:Show()
		end

		local textureRegion
		for _, region in ipairs({ child:GetRegions() }) do
			if region.GetMaskTexture and region:GetMaskTexture(1) then
				region:RemoveMaskTexture(region:GetMaskTexture(1))
			elseif region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
				textureRegion = region
				region:Hide()
			end
		end

		if childConfig and childConfig.customIcon and textureRegion then
			child.Icon:SetTexture(childConfig.customIcon)

			if not child.SCMIconTextureHook then
				child.SCMIconTextureHook = true
				hooksecurefunc(child.Icon, "SetTexture", function(self)
					local config = self:GetParent().SCMConfig
					if config and config.customIcon then
						textureRegion.SetTexture(self, config.customIcon)
					end
				end)
			end
		end

		if child.DebuffBorder then
			child.DebuffBorder:SetAlpha(0)
		end

		local fontPath = LSM:Fetch("font", options.chargeFont)
		ApplyChargeAndApplicationStyle(child, options, fontPath)
		ApplyCooldownStyle(child, options)
	end
	for _, customSkin in ipairs(SCM.Skins) do
		pcall(customSkin, child)
	end
end
