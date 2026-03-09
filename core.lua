local addonName, SCM = ...

local function OnEssentialCooldownViewerLayout()
	SCM:ApplyEssentialCDManagerConfig()
end

local function OnUtilityCooldownViewerLayout()
	SCM:ApplyUtilityCDManagerConfig()
end

local function OnBuffCooldownViewerLayout()
	SCM:ApplyBuffIconCDManagerConfig()
end

local function OnCooldownViewerSettingsRefreshLayout(self)
	SCM:ClearChildrenCache()
	SCM:UpdateCooldownInfo(true, self:GetDataProvider())
	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()
end

local pendingCustomGlowChildren = {}

local function StartPendingCustomGlows()
	for child in pairs(pendingCustomGlowChildren) do
		pendingCustomGlowChildren[child] = nil
		if child and child.SCMActiveGlow then
			SCM:StartCustomGlow(child)
		end
	end
end

local function OnSpellAlertManagerShowAlert(_, child)
	local options = SCM.db.global.options
	if not child.SCMConfig or not options.useCustomGlow or child.SCMActiveGlow then
		return
	end

	child.SCMActiveGlow = true
	child.SpellActivationAlert:Hide()
	pendingCustomGlowChildren[child] = true
	RunNextFrame(StartPendingCustomGlows)
end

local function OnSpellAlertManagerHideAlert(_, child)
	if child.SCMConfig and child.SCMActiveGlow then
		child.SCMActiveGlow = nil
		SCM:StopCustomGlow(child)
	end
end

function SCM:SetHooks()
	hooksecurefunc(EssentialCooldownViewer, "Layout", OnEssentialCooldownViewerLayout)
	hooksecurefunc(UtilityCooldownViewer, "Layout", OnUtilityCooldownViewerLayout)
	hooksecurefunc(BuffIconCooldownViewer, "Layout", OnBuffCooldownViewerLayout)
	hooksecurefunc(CooldownViewerSettings, "RefreshLayout", OnCooldownViewerSettingsRefreshLayout)

	if ActionButtonSpellAlertManager then
		hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", OnSpellAlertManagerShowAlert)
		hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", OnSpellAlertManagerHideAlert)
	end
end

function SCM:CreateAllCustomIcons()
	for _, config in pairs(self.customConfig) do
		SCM.CustomIcons.CreateIcons(config)
	end

	for _, config in pairs(self.globalCustomConfig) do
		SCM.CustomIcons.CreateIcons(config, true)
	end
end

function SCM:PLAYER_ENTERING_WORLD(isInitialLogin, isReload)
	if isInitialLogin or isReload then
		SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
		SCM:UpdateDB()

		SCM:CreateAllCustomIcons()
		SCM:ApplyAllCDManagerConfigs()
		SCM:SetHooks()
	elseif self.isInInstance ~= IsInInstance() then
		SCM:ApplyAllCDManagerConfigs()
	end

	self.isInInstance = IsInInstance()
end

function SCM:BAG_UPDATE_DELAYED()
	--SCM:ApplyAllCDManagerConfigs()
--	SCM.CustomIcons.ProcessIcons()
end

function SCM:BAG_UPDATE_COOLDOWN()
	SCM:ApplyAnchorGroupByIconTypes(false, "item", "slot")
end

function SCM:SPELL_UPDATE_COOLDOWN(spellID)
	SCM:ApplyAnchorGroupBySpellID(spellID)
end

function SCM:PLAYER_EQUIPMENT_CHANGED()
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:PLAYER_REGEN_ENABLED()
	if not self.appliedOptions then
		self:ApplyOptions()
	end

	SCM:ApplyAllCDManagerConfigs()
end

function SCM:PLAYER_REGEN_DISABLED() end

function SCM:EDIT_MODE_LAYOUTS_UPDATED()
	SCM:ApplyOptions()
end

local function RefreshCooldownViewerData()
	SCM:ClearViewerChildrenCache()
	SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()
end

local function RefreshPixelPerfectLayout()
	SCM:InvalidatePixelPerfectCache()
	SCM:ApplyAllCDManagerConfigs()
end

function SCM:TRAIT_CONFIG_UPDATED()
	C_Timer.After(0.2, RefreshCooldownViewerData)
end

function SCM:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
	C_Timer.After(0.2, RefreshCooldownViewerData)
end

function SCM:UI_SCALE_CHANGED()
	RefreshPixelPerfectLayout()
end

function SCM:DISPLAY_SIZE_CHANGED()
	RefreshPixelPerfectLayout()
end

function SCM:CVAR_UPDATE(cvarName)
	if cvarName == "uiScale" then
		RefreshPixelPerfectLayout()
	end
end

local function OnProfileChanged(_, _, _, skipReset)
	-- Hopefully players won't change profiles that much that we reach the frame limit :)
	if not skipReset then
		SCM.DB:ResetData()
	end

	SCM:UpdateCooldownInfo(true, CooldownViewerSettings:GetDataProvider())
	SCM:UpdateDB()
	SCM:ApplyAllCDManagerConfigs()

	if SCM.OptionsFrame and SCM.OptionsFrame:IsShown() and SCM.db.global.options.showAnchorHighlight then
		for _, anchorFrame in pairs(SCM.anchorFrames) do
			anchorFrame.debugTexture:Show()
			anchorFrame.debugText:Show()
		end
	end
end

function SCM:LoadNewProfile()
	OnProfileChanged(nil, nil, nil, true)
end

local function OnEventFrameEvent(_, event, ...)
	if SCM[event] then
		SCM[event](SCM, ...)
	end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	SCM.db = LibStub("AceDB-3.0"):New(addonName .. "DB", SCM.DefaultDB, true)
	SCM.db.RegisterCallback(SCM, "OnProfileChanged", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileCopied", OnProfileChanged)
	SCM.db.RegisterCallback(SCM, "OnProfileReset", OnProfileChanged)

	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
	eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
	eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
	eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	eventFrame:RegisterEvent("UI_SCALE_CHANGED")
	eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
	eventFrame:RegisterEvent("CVAR_UPDATE")
	eventFrame:SetScript("OnEvent", OnEventFrameEvent)

	SCM:GetAnchor(1)
end)

function SCM:GetConfigTable(iconType, isGlobal)
	if iconType == "spell" then
		return isGlobal and self.globalCustomConfig.spellConfig or self.customConfig.spellConfig
	end

	if iconType == "slot" then
		return isGlobal and self.globalCustomConfig.slotConfig or self.customConfig.slotConfig
	end

	return isGlobal and self.globalCustomConfig.itemConfig or self.customConfig.itemConfig
end

function SCM:GetConfigTableByID(configID, iconType, isGlobal)
	local configTable = self:GetConfigTable(iconType, isGlobal)
	return configTable and configTable[configID]
end
