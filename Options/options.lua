local addonName, SCM = ...

local AceGUI = LibStub("AceGUI-3.0")
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
local LibCustomGlow = LibStub("LibCustomGlow-1.0")
local Utils = SCM.Utils
local ToGlobalGroup = Utils.ToGlobalGroup
local ToBuffBarGroup = Utils.ToBuffBarGroup
local NormalizeBuffBarGroup = Utils.NormalizeBuffBarGroup

StaticPopupDialogs["SCM_FORCE_RELOAD_POPUP"] = {
	text = "This requires a UI reload. Reload now?",
	button1 = RELOADUI,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(_, data)
		data.options[data.key] = data.value
		C_UI.Reload()
	end,
	OnCancel = function(_, data)
		if data.checkbox and data.key then
			data.checkbox:SetValue(data.options[data.key])
		end
	end,
}

function SCM.ShowReloadPopup(data)
	StaticPopup_Show("SCM_FORCE_RELOAD_POPUP", nil, nil, data)
end

function SCM.Encode(table)
	local serialized = C_EncodingUtil.SerializeCBOR(table)
	local compressed = C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
	local encoded = C_EncodingUtil.EncodeBase64(compressed)
	return encoded
end

function SCM.Decode(importString)
	local decoded = C_EncodingUtil.DecodeBase64(importString)
	local decompressed = C_EncodingUtil.DecompressString(decoded)
	local data = C_EncodingUtil.DeserializeCBOR(decompressed)

	return data
end

function SCM:AddGlobalAnchor(anchorTabsTbl)
	local anchorConfig = self.db.global.globalAnchorConfig
	local nextIndex = #anchorConfig + 1
	anchorConfig[nextIndex] = {
		anchor = { "CENTER", "UIParent", "CENTER", 0, 0 },
		rowConfig = {
			[1] = {
				size = 40,
				limit = 8,
			},
		},
	}
	self:InvalidateAnchorLinks()
	tinsert(anchorTabsTbl, { value = nextIndex, text = "Anchor " .. nextIndex })
	SCM:ApplyAllCDManagerConfigs()
	return nextIndex
end

function SCM:AddBuffBarAnchor(anchorTabsTbl)
	local anchorConfig = self.buffBarsAnchorConfig
	local nextIndex = #anchorConfig + 1
	anchorConfig[nextIndex] = {
		anchor = { "CENTER", "UIParent", "CENTER", 0, 0 },
		rowConfig = {
			[1] = {
				iconWidth = 150,
				iconHeight = 40,
				limit = 8,
			},
		},
	}
	self:InvalidateAnchorLinks()
	tinsert(anchorTabsTbl, { value = nextIndex, text = "Anchor " .. nextIndex })
	SCM:ApplyBuffBarCDManagerConfig()
	return nextIndex
end

function SCM:RemoveGlobalAnchor(anchorIndex, anchorTabsTbl)
	if self.db.global.globalAnchorConfig[anchorIndex] then
		tremove(self.db.global.globalAnchorConfig, anchorIndex)
	end

	local globalAnchorIndex = ToGlobalGroup(#anchorTabsTbl)
	self.anchorFrames[globalAnchorIndex]:Hide()
	self.anchorFrames[globalAnchorIndex] = nil

	for _, globalConfig in pairs({
		self.db.global.globalCustomConfig.spellConfig,
		self.db.global.globalCustomConfig.itemConfig,
		self.db.global.globalCustomConfig.slotConfig,
		self.db.global.globalCustomConfig.timerConfig,
	}) do
		for id, config in pairs(globalConfig) do
			if config.anchorGroup == anchorIndex then
				globalConfig[id] = nil
			elseif config.anchorGroup and config.anchorGroup > anchorIndex then
				config.anchorGroup = config.anchorGroup - 1
			end
		end
	end

	for i = #anchorTabsTbl, 1, -1 do
		if anchorTabsTbl[i].value == anchorIndex then
			tremove(anchorTabsTbl, i)
		end
	end
	for i, tab in ipairs(anchorTabsTbl) do
		tab.value = i
		tab.text = "Anchor " .. i
	end

	self:InvalidateAnchorLinks()
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:RemoveBuffBarAnchor(anchorIndex, anchorTabsTbl)
	if self.buffBarsAnchorConfig[anchorIndex] then
		tremove(self.buffBarsAnchorConfig, anchorIndex)
	end

	local removedGroup = ToBuffBarGroup(anchorIndex)
	local buffBarAnchorFrame = self.anchorFrames[ToBuffBarGroup(#anchorTabsTbl)]
	if buffBarAnchorFrame then
		buffBarAnchorFrame:Hide()
		self.anchorFrames[ToBuffBarGroup(#anchorTabsTbl)] = nil
	end

	for configID, config in pairs(self.spellConfig) do
		local trackedBarGroup = config.source and config.source[Enum.CooldownViewerCategory.TrackedBar]
		if trackedBarGroup == removedGroup then
			config.source[Enum.CooldownViewerCategory.TrackedBar] = nil
			config.anchorGroup[removedGroup] = nil

			if not next(config.anchorGroup) then
				self.spellConfig[configID] = nil
			end
		elseif trackedBarGroup and Utils.IsBuffBarGroup(trackedBarGroup) and trackedBarGroup > removedGroup then
			local newGroup = trackedBarGroup - 1
			config.source[Enum.CooldownViewerCategory.TrackedBar] = newGroup
			config.anchorGroup[newGroup] = config.anchorGroup[trackedBarGroup]
			config.anchorGroup[trackedBarGroup] = nil
		end
	end

	for i = #anchorTabsTbl, 1, -1 do
		if anchorTabsTbl[i].value == anchorIndex then
			tremove(anchorTabsTbl, i)
		end
	end
	for i, tab in ipairs(anchorTabsTbl) do
		tab.value = i
		tab.text = "Anchor " .. i
	end

	self:InvalidateAnchorLinks()
	SCM:ApplyBuffBarCDManagerConfig()
end

function SCM:AddAnchor(anchorTabsTbl)
	local nextIndex = #SCM.anchorConfig + 1
	self.anchorConfig[nextIndex] = {
		anchor = { "CENTER", "UIParent", "CENTER", 0, 0 },
		rowConfig = {
			[1] = {
				size = 40,
				limit = 8,
			},
		},
	}

	tinsert(anchorTabsTbl, { value = nextIndex, text = "Anchor " .. nextIndex })
	table.sort(anchorTabsTbl, function(a, b)
		return a.value < b.value
	end)

	self:InvalidateAnchorLinks()
	SCM:ApplyAllCDManagerConfigs()

	return nextIndex
end

function SCM:RemoveAnchor(anchorIndex, anchorTabsTbl)
	if self.anchorConfig[anchorIndex] then
		tremove(self.anchorConfig, anchorIndex)
	end

	local removedIndex
	for i, tab in ipairs(anchorTabsTbl) do
		if tab.value == anchorIndex then
			removedIndex = i
			tremove(anchorTabsTbl, i)
			break
		end
	end

	for i = removedIndex, #anchorTabsTbl do
		anchorTabsTbl[i].value = i
		anchorTabsTbl[i].text = "Anchor " .. i
	end

	self.anchorFrames[#self.anchorFrames]:Hide()
	self.anchorFrames[#self.anchorFrames] = nil

	for spellID, config in pairs(self.spellConfig) do
		for sourceIndex, anchorGroup in pairs(config.source) do
			if anchorGroup == anchorIndex then
				config.source[sourceIndex] = nil

				if not next(config.source) then
					self.spellConfig[spellID] = nil
				end
			elseif anchorGroup > anchorIndex then
				config.source[sourceIndex] = anchorGroup - 1
				config.anchorGroup[anchorGroup - 1] = config.anchorGroup[anchorGroup]
				config.anchorGroup[anchorGroup] = nil
			end
		end
	end

	self:InvalidateAnchorLinks()
	SCM:ApplyAllCDManagerConfigs()

	return removedIndex
end

function SCM:AddRow(anchorIndex)
	local nextIndex = #SCM.anchorConfig[anchorIndex].rowConfig + 1
	self.anchorConfig[anchorIndex].rowConfig[nextIndex] = {
		size = 40,
		limit = 8,
	}

	return nextIndex
end

function SCM:RemoveRow(anchorIndex, rowIndex)
	if self.anchorConfig[anchorIndex].rowConfig[rowIndex] then
		tremove(self.anchorConfig[anchorIndex].rowConfig, rowIndex)
	end
end

function SCM:AddSpellToConfig(anchorGroup, order, info, displayData, sourceIndex)
	local spellID = displayData.spellID
	if displayData.linkedSpellIDs and #displayData.linkedSpellIDs == 1 then
		spellID = displayData.linkedSpellIDs[1]
	end

	local effectiveAnchorGroup = anchorGroup
	if sourceIndex == Enum.CooldownViewerCategory.TrackedBar then
		effectiveAnchorGroup = NormalizeBuffBarGroup(anchorGroup)
		if not effectiveAnchorGroup then
			return
		end
	end

	local cooldownID = displayData.cooldownID or info.cooldownID
	local configID = self:GetCooldownConfigKey(cooldownID)
	if not configID then
		return
	end

	if not self.spellConfig[configID] then
		self.spellConfig[configID] = {
			spellID = spellID,
			cooldownID = cooldownID,
			source = {
				[sourceIndex] = effectiveAnchorGroup,
			},
			anchorGroup = {
				[effectiveAnchorGroup] = {
					order = order,
				},
			},
		}
	else
		self.spellConfig[configID].spellID = spellID
		self.spellConfig[configID].cooldownID = cooldownID or self.spellConfig[configID].cooldownID
		self.spellConfig[configID].source[sourceIndex] = effectiveAnchorGroup
		self.spellConfig[configID].anchorGroup[effectiveAnchorGroup] = {
			order = order,
		}
	end
end

function SCM:RemoveSpellFromConfig(anchorIndex, data)
	local configID = data.id or self:GetCooldownConfigKey(data.cooldownID)
	local spellConfig = configID and self.spellConfig[configID]
	if spellConfig then

		for category, anchorGroup in pairs(spellConfig.source) do
			if anchorGroup == anchorIndex then
				spellConfig.source[category] = nil
			end
		end

		spellConfig.anchorGroup[anchorIndex] = nil

		if not next(spellConfig.anchorGroup) then
			self.spellConfig[configID] = nil
		end
	end
end

function SCM:IsSpellInData(cooldownID, source)
	local configID = self:GetCooldownConfigKey(cooldownID)
	local spellConfig = configID and self.spellConfig[configID]
	local pairedSource = Utils.GetPairedSource(source)
	return spellConfig and (spellConfig.source[source] or (pairedSource and spellConfig.source[pairedSource]))
end

function SCM:AddTab(tab)
	if not self.MainTabs[tab.value] and tab.callback then
		self.MainTabs[tab.value] = tab
	end

	if self.OptionsFrame and self.OptionsFrame:IsShown() then
		self.OptionsFrame:DoLayout()
	end
end

function SCM:GetHideWhenInactive()
	LibEditModeOverride:LoadLayouts()
	return LibEditModeOverride:GetFrameSetting(BuffIconCooldownViewer, Enum.EditModeCooldownViewerSetting.HideWhenInactive)
end

function SCM:SetHideWhenInactive(value)
	LibEditModeOverride:LoadLayouts()

	if LibEditModeOverride:CanEditActiveLayout() then
		local currentSetting = LibEditModeOverride:GetFrameSetting(BuffIconCooldownViewer, Enum.EditModeCooldownViewerSetting.HideWhenInactive)
		if (value and currentSetting == 1) or (not value and currentSetting == 0) then
			LibEditModeOverride:SetFrameSetting(BuffIconCooldownViewer, Enum.EditModeCooldownViewerSetting.HideWhenInactive, value and 0 or 1)
			LibEditModeOverride:SaveOnly()
			LibEditModeOverride:ApplyChanges()
		end
	end
end

function SCM:ApplyHideWhileMountedSettings(value)
	if value then
		RegisterAttributeDriver(EssentialCooldownViewer, "state-visibility", "[combat]show;[mounted][stance:3]hide;show")
		RegisterAttributeDriver(UtilityCooldownViewer, "state-visibility", "[combat]show;[mounted][stance:3]hide;show")
		RegisterAttributeDriver(BuffIconCooldownViewer, "state-visibility", "[combat]show;[mounted][stance:3]hide;show")
	else
		UnregisterAttributeDriver(EssentialCooldownViewer, "state-visibility")
		UnregisterAttributeDriver(UtilityCooldownViewer, "state-visibility")
		UnregisterAttributeDriver(BuffIconCooldownViewer, "state-visibility")
	end

	self:ApplyResourceBarHideWhileMountedSettings(value)
end

function SCM:ApplyOptions()
	if InCombatLockdown() or self.appliedOptions then
		return
	end
	self.appliedOptions = true

	local options = self.db.profile.options
	self:SetHideWhenInactive(options.hideBuffsWhenInactive)
	self:ApplyHideWhileMountedSettings(options.hideWhileMounted)
end

local function OpenOptions()
	local options = SCM.db.profile.options
	SCM.isOptionsOpen = true

	SCM:StopAllGlows()
	SCM:ApplyAllCDManagerConfigs()

	local frame = AceGUI:Create("SCMFrame")
	frame:SetTitle(addonName)
	frame:SetLayout("flow")
	SCM.OptionsFrame = frame

	frame:SetHeight(1000)
	frame:SetWidth(800)

	local tabsTbl = {}
	for _, tab in pairs(SCM.MainTabs) do
		tinsert(tabsTbl, tab)
	end
	table.sort(tabsTbl, function(a, b)
		return a.order < b.order
	end)

	local tabs = AceGUI:Create("SCMTabGroup")
	tabs:SetTabs(tabsTbl)
	tabs:SetWidth(frame.frame:GetWidth() - 30)
	tabs:SetFullHeight(true)
	tabs:SetLayout("fill")
	tabs:SetCallback("OnGroupSelected", function(self, event, group)
		self:ReleaseChildren()

		if group ~= "CDM" and options.showAnchorHighlight then
			for _, anchorFrame in pairs(SCM.anchorFrames) do
				anchorFrame.isGlowActive = false
				LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
				LibCustomGlow.PixelGlow_Start(anchorFrame, nil, nil, nil, nil, nil, nil, nil, nil, "SCM")
				anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
			end
		end

		if SCM.MainTabs[group] then
			SCM.MainTabs[group].callback(self, frame, group)
		end
	end)
	tabs:SelectTab("General")
	frame:AddChild(tabs)
	frame:SetCallback("OnClose", function()
		SCM.OptionsFrame = nil
		SCM.isOptionsOpen = nil
		for _, anchorFrame in pairs(SCM.anchorFrames) do
			anchorFrame.debugTexture:Hide()
			anchorFrame.debugText:Hide()
		end
		SCM:ApplyAllCDManagerConfigs()
		RunNextFrame(function()
			SCM:RestoreBlizzardGlows()
		end)
	end)

	if SCM.db.profile.options.showAnchorHighlight then
		for _, anchorFrame in pairs(SCM.anchorFrames) do
			anchorFrame.debugTexture:Show()
			anchorFrame.debugText:Show()
		end
	end
end

SLASH_SCM1 = "/scm"
local function HandleMessage(msg, editBox)
	if msg == "debug" then
		local options = SCM.db.profile.options
		options.debug = not options.debug
	else
		if not SCM.OptionsFrame or not SCM.OptionsFrame:IsShown() then
			OpenOptions()
		else
			SCM.OptionsFrame:Release()
			SCM.OptionsFrame = nil
		end
	end
end
SlashCmdList["SCM"] = HandleMessage

function SCM:ToggleOptions()
	HandleMessage()
end
