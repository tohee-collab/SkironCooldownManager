local SCM = select(2, ...)

local Cooldowns = SCM.Cooldowns
local Icons = SCM.Icons
local Cache = SCM.Cache

local function OnBuffCooldownSet(self)
	local parent = (self.SCMConfig and self) or self:GetParent()
	if not parent or not parent.SCMConfig then
		return
	end

	parent.SCMAuraInstanceID = parent.SCMAuraInstanceID or parent.auraInstanceID

	if not parent.SCMHidden or parent.SCMConfig.alwaysShow then
		Icons.UpdateChildDesaturation(parent, false)
		Icons.UpdateChildGlow(parent, false)
	elseif parent.SCMHidden then
		Icons.ShowChild(parent)
		SCM:ApplyAnchorGroupCDManagerConfig(parent.SCMGroup)
	end
end

local function OnBuffCooldownEnd(self)
	local parent = (self.SCMConfig and self) or self:GetParent()
	if not parent or not parent.SCMConfig then
		return
	end

	if parent.SCMAuraInstanceID then
		if not C_UnitAuras.GetAuraDataByAuraInstanceID("player", parent.SCMAuraInstanceID) then
			parent.SCMAuraInstanceID = nil
		else
			return
		end
	end

	Icons.UpdateChildGlow(parent, true)

	if parent.SCMConfig.alwaysShow then
		Icons.UpdateChildDesaturation(parent, true)
		return
	end

	--local options = parent.SCMBuffOptions
	if not parent.SCMHidden then
		SCM:ApplyAnchorGroupCDManagerConfig(parent.SCMGroup)
	end
end

local function OnBuffTriggerPandemicAlert(self)
	local options = self.SCMBuffOptions
	if options and options.pandemicGlowOption ~= "keepPandemicGlow" and not self.SCMPandemic then
		self.SCMPandemic = true
	end
end

local function OnBuffShowPandemicStateFrame(self)
	if not self.PandemicIcon or not self.PandemicIcon:IsVisible() then
		return
	end

	local options = self.SCMBuffOptions
	if not options or options.pandemicGlowOption == "keepPandemicGlow" then
		return
	end

	self.PandemicIcon:SetAlpha(0)

	if options.pandemicGlowOption == "replacePandemicGlow" then
		SCM:StartCustomGlow(self.Icon)
	end
end

local function OnBuffHidePandemicStateFrame(self)
	local options = self.SCMBuffOptions
	if not options then
		return
	end

	if self.SCMPandemic and options.pandemicGlowOption == "replacePandemicGlow" then
		SCM:StopCustomGlow(self.Icon)
		self.SCMPandemic = nil
	end
end

function Cooldowns.SetupBuffIconHooks(child, options)
	if child.SCMShowHook then
		return
	end

	Icons.SetupIconHooks(child)
	child.SCMBuffOptions = options

	-- Cooldowns
	hooksecurefunc(child, "OnAuraInstanceInfoSet", OnBuffCooldownSet)
	hooksecurefunc(child, "OnAuraInstanceInfoCleared", OnBuffCooldownEnd)
	--hooksecurefunc(child.Cooldown, "SetCooldown", OnBuffCooldownSet)
	--hooksecurefunc(child.Cooldown, "Clear", OnBuffCooldownEnd)
	--child.Cooldown:HookScript("OnCooldownDone", OnBuffCooldownEnd)

	-- Pandmic Alerts
	hooksecurefunc(child, "TriggerPandemicAlert", OnBuffTriggerPandemicAlert)
	hooksecurefunc(child, "ShowPandemicStateFrame", OnBuffShowPandemicStateFrame)
	hooksecurefunc(child, "HidePandemicStateFrame", OnBuffHidePandemicStateFrame)
end

function Cooldowns.IsChildOnCooldown(child)
	if not child or not child.Cooldown then
		return
	end

	local spellCooldownInfo = C_Spell.GetSpellCooldown(child.SCMSpellID)
	if spellCooldownInfo and spellCooldownInfo.isOnGCD then
		return
	end

	local hasCooldown = child.Cooldown:IsShown()
	return hasCooldown
end

function Cooldowns.SetNormalCooldown(self, parent)
	local cooldownData = SCM.defaultCooldownViewerConfig.cooldownIDs[parent.SCMCooldownID]
	self.SCMSettingRegularSpellCooldown = true

	local durationObject
	local desaturate = false

	if cooldownData.charges then
		local spellCharges = C_Spell.GetSpellCharges(parent.SCMSpellID)
		if spellCharges and spellCharges.isActive then
			durationObject = C_Spell.GetSpellChargeDuration(parent.SCMSpellID, true)
		end
	end

	if not durationObject then
		desaturate = true
		durationObject = C_Spell.GetSpellCooldownDuration(parent.SCMSpellID, true)
	end

	if durationObject then
		parent.Icon.SCMDesaturated = desaturate
		parent.Icon:SetDesaturated(desaturate)
		self:SetCooldownFromDurationObject(durationObject)
	else
		parent.Icon.SCMDesaturated = nil
		parent.Icon:SetDesaturated(false)
		self:Clear()
	end

	self.SCMSettingRegularSpellCooldown = nil
end

function Cooldowns.OverrideRegularAuraCooldown(self, parent, options)
	if not options.disableRegularIconActiveSwipe or not parent.SCMSpellID or not self:GetUseAuraDisplayTime() or parent.SCMConfig.forceActiveSwipe then
		parent.Icon.SCMDesaturated = nil
		return
	end

	Cooldowns.SetNormalCooldown(self, parent)
end

local function SetRegularChildCooldown(child, cooldownInfo)
	local cooldownFrame = child.Cooldown
	if not (cooldownFrame and child.Icon) then
		return
	end

	Cooldowns.SetNormalCooldown(cooldownFrame, child)
end

local function OverwriteViewerChildCooldown(viewer, spellID, cooldownInfo)
	local children = Cache.cachedViewerChildren[viewer]
	if not children then
		children = { viewer:GetChildren() }
		Cache.cachedViewerChildren[viewer] = children
	end

	for i = 1, #children do
		local child = children[i]
		if child.SCMConfig and not child.SCMBuffBar and not child.SCMConfig.forceActiveSwipe and child.SCMSpellID == spellID then
			SetRegularChildCooldown(child, cooldownInfo)
		end
	end
end

function Cooldowns.OverwriteRegularChildCooldownBySpellID(spellID, overrideSpellID, cooldownInfo)
	OverwriteViewerChildCooldown(EssentialCooldownViewer, spellID, cooldownInfo)
	OverwriteViewerChildCooldown(UtilityCooldownViewer, spellID, cooldownInfo)
end

local function OnRegularCooldownChanged(self)
	local parent = self:GetParent()
	if not (parent and parent.SCMConfig) or self.SCMSettingRegularSpellCooldown or self.SCMClearingGCD then
		return
	end

	local options = SCM.db.profile.options
	if options.disableRegularIconActiveSwipe and not parent.SCMConfig.forceActiveSwipe and self:GetUseAuraDisplayTime() then
		Cooldowns.OverrideRegularAuraCooldown(self, parent, options)
	elseif options.disableGCD then
		Cooldowns.SetNormalCooldown(self, parent)
	end

	local config = parent.SCMConfig
	if config.hideWhenNotOnCooldown then
		local shouldShow = Cooldowns.IsChildOnCooldown(parent) and true or false
		if parent.SCMShouldBeVisible ~= shouldShow then
			local viewer = parent.viewerFrame
			if viewer then
				if viewer == EssentialCooldownViewer then
					SCM:ApplyEssentialCDManagerConfig()
				elseif viewer == UtilityCooldownViewer then
					SCM:ApplyUtilityCDManagerConfig()
				end
			else
				SCM:ApplyAllCDManagerConfigs()
			end
		end
	end

	Icons.UpdateChildGlow(parent, not self:GetUseAuraDisplayTime())
end

function Cooldowns.SetupCooldownHooks(child)
	if child.SCMRegularCooldownHook or not child.Cooldown then
		return
	end

	hooksecurefunc(child.Cooldown, "SetCooldown", OnRegularCooldownChanged)
	hooksecurefunc(child.Cooldown, "Clear", OnRegularCooldownChanged)
	child.Cooldown:HookScript("OnCooldownDone", function(self, ...)
		local parent = self:GetParent()
		parent.Icon.SCMDesaturated = nil
		OnRegularCooldownChanged(self)
	end)
	child.SCMRegularCooldownHook = true
end

function SCM:UpdateCooldownInfo(isFirstLoad, dataProvider)
	if InCombatLockdown() then
		return
	end

	self.defaultCooldownViewerConfig = {
		cooldownIDs = {},
		spellIDs = {},
	}
	self.currentCooldownViewerConfig = {}

	local displayData = dataProvider and dataProvider.displayData.cooldownInfoByID
	for _, cooldownCategory in pairs(CooldownViewerSettingsDataProvider_GetCategories()) do
		self.defaultCooldownViewerConfig[cooldownCategory] = {
			spellIDs = {},
			cooldownIDs = {},
		}

		local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cooldownCategory, true)
		local order = 0
		for _, cooldownID in ipairs(cooldownIDs) do
			local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
			if info then
				local data = displayData[cooldownID]
				if data then
					local spellID = data.spellID
					self.defaultCooldownViewerConfig[cooldownCategory][data.cooldownID] = data
					self.defaultCooldownViewerConfig[cooldownCategory].spellIDs[spellID] = data
					self.defaultCooldownViewerConfig[cooldownCategory].cooldownIDs[data.cooldownID] = data
					self.defaultCooldownViewerConfig.cooldownIDs[data.cooldownID] = data

					self.defaultCooldownViewerConfig.spellIDs[spellID] = data
					for _, linkedSpellID in ipairs(data.linkedSpellIDs or {}) do
						self.defaultCooldownViewerConfig[cooldownCategory].spellIDs[linkedSpellID] = data
						self.defaultCooldownViewerConfig.spellIDs[linkedSpellID] = data
					end
					if data and data.category >= 0 and data.category <= 2 then
						order = order + 1
						self.currentCooldownViewerConfig[spellID] = self.currentCooldownViewerConfig[spellID] or { source = {}, anchorGroup = {} }
						self.currentCooldownViewerConfig[spellID].source[data.category] = data.category + 1
						self.currentCooldownViewerConfig[spellID].anchorGroup[data.category + 1] = {
							order = order,
						}
					end
				end
			end
		end
	end
end
