local addonName, SCM = ...

local AceGUI = LibStub("AceGUI-3.0")
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
local LibCustomGlow = LibStub("LibCustomGlow-1.0")

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
	tinsert(anchorTabsTbl, { value = nextIndex, text = "Anchor " .. nextIndex })
	SCM:ApplyAllCDManagerConfigs()
	return nextIndex
end

function SCM:RemoveGlobalAnchor(anchorIndex, anchorTabsTbl)
	if self.db.global.globalAnchorConfig[anchorIndex] then
		tremove(self.db.global.globalAnchorConfig, anchorIndex)
	end

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
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:AddAnchor(anchorTabsTbl, frame)
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

	SCM:ApplyAllCDManagerConfigs()

	SCM:ApplyAllCDManagerConfigs()

	return nextIndex
end

function SCM:RemoveAnchor(anchorIndex, anchorTabsTbl, frame)
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
	}

	self.CustomIcons.CreateIcons(configTable, isGlobal)

	return uniqueID
end

function SCM:RemoveCustomIcon(id, isGlobal, iconType)
	local configTable = SCM:GetConfigTable(iconType, isGlobal)
	if configTable and configTable[id] then
		local config = configTable[id]
		configTable[id] = nil

		local customFrames = SCM.CustomIcons.GetCustomIconFrames(config)
		if customFrames and customFrames[id] then
			SCM.SetChildVisibilityState(customFrames[id], false, true)
		end
	end
end

function SCM:AddSpellToConfig(anchorGroup, order, info, displayData, sourceIndex)
	if not self.spellConfig[displayData.spellID] then
		self.spellConfig[displayData.spellID] = {
			source = {
				[sourceIndex] = anchorGroup,
			},
			anchorGroup = {
				[anchorGroup] = {
					order = order,
				},
			},
		}
	else
		self.spellConfig[displayData.spellID].source[sourceIndex] = anchorGroup
		self.spellConfig[displayData.spellID].anchorGroup[anchorGroup] = {
			order = order,
		}
	end
end

function SCM:RemoveSpellFromConfig(anchorIndex, data)
	if self.spellConfig[data.spellID] then
		local spellConfig = self.spellConfig[data.spellID]

		for category, anchorGroup in pairs(spellConfig.source) do
			if anchorGroup == anchorIndex then
				spellConfig.source[category] = nil
			end
		end

		spellConfig.anchorGroup[anchorIndex] = nil

		if not next(spellConfig.anchorGroup) then
			self.spellConfig[data.spellID] = nil
		end
	end
end

function SCM:IsSpellInData(spellID, source)
	return self.spellConfig[spellID] and (self.spellConfig[spellID].source[source] or (self.Constants.SourcePairs[source] and self.spellConfig[spellID].source[self.Constants.SourcePairs[source]]))
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

function SCM:ApplyOptions()
	if InCombatLockdown() or self.appliedOptions then
		return
	end
	self.appliedOptions = true

	local options = self.db.global.options
	self:SetHideWhenInactive(options.hideBuffsWhenInactive)
end

local function OpenOptions()
	local options = SCM.db.global.options
	SCM.isOptionsOpen = true

	SCM:StopAllGlows()
	SCM:ApplyAllCDManagerConfigs()

	local frame = AceGUI:Create("SCMFrame")
	frame:SetTitle(addonName)
	frame:SetLayout("flow")
	SCM.OptionsFrame = frame

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
	end)

	if SCM.db.global.options.showAnchorHighlight then
		for _, anchorFrame in pairs(SCM.anchorFrames) do
			anchorFrame.debugTexture:Show()
			anchorFrame.debugText:Show()
		end
	end

	frame:SetHeight(800)
end

SLASH_SCM1 = "/scm"
local function handler(msg, editBox)
	if msg == "debug" then
		SCM.db.global.options.debug = not SCM.db.global.options.debug
	else
		if not SCM.OptionsFrame or not SCM.OptionsFrame:IsShown() then
			OpenOptions()
		else
			SCM.OptionsFrame:Release()
			SCM.OptionsFrame = nil
		end
	end
end
SlashCmdList["SCM"] = handler

function SCM:ToggleOptions()
	handler()
end
