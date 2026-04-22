local _, SCM = ...

local Utils = SCM.Utils
local GLOBAL_GROUP_OFFSET = 100
local GLOBAL_BUFF_BAR_OFFSET = 200
local FIRST_GLOBAL_GROUP = GLOBAL_GROUP_OFFSET + 1
local FIRST_BUFF_BAR_GROUP = GLOBAL_BUFF_BAR_OFFSET + 1
local CHILD_SCM_RESET_FIELDS = {
	"SCMConfig",
	"SCMConfigID",
	"SCMCooldownID",
	"SCMSpellID",
	"SCMLinkedSpellID",
	"SCMOrder",
	"SCMGroup",
	"SCMGlobal",
	"SCMBuffBar",
	"SCMBuffOptions",
	"SCMChanged",
	"SCMCustom",
	"SCMIconType",
	"SCMIconTexture",
	"SCMGlowWhileActive",
	"SCMPandemic",
	"SCMRowConfig",
	"SCMShouldBeVisible",
	"SCMHidden",
	"SCMGlow",
	"SCMActiveGlow",
	"SCMAnchorFrame",
	"SCMAnchorData",
	"SCMWidth",
	"SCMHeight",
	"SCMBaseStartPoint",
	"SCMBaseOffsetX",
	"SCMBaseOffsetY",
	"SCMLayoutApplied",
}

local function CreateDisabledTooltipOverlay(widget)
	if not widget or not widget.frame then
		return
	end

	local frame = widget.frame
	local overlay = frame.SCMDisabledTooltipOverlay
	if not overlay then
		overlay = CreateFrame("Frame", nil, frame)
		overlay:SetAllPoints(frame)
		overlay:EnableMouse(true)
		overlay:Hide()
		overlay:SetScript("OnEnter", function(self)
			local ownerWidget = self.ownerWidget
			if not ownerWidget or not ownerWidget.disabled then
				return
			end

			local tooltip = ownerWidget._scmDisabledTooltip
			if type(tooltip) == "function" then
				tooltip = tooltip(ownerWidget)
			end

			if not tooltip or tooltip == "" then
				return
			end

			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tooltip, 1, 0.82, 0, 1, true)
			GameTooltip:Show()
		end)
		overlay:SetScript("OnLeave", function(self)
			if GameTooltip:IsOwned(self) then
				GameTooltip:Hide()
			end
		end)
		overlay:SetScript("OnHide", function(self)
			if GameTooltip:IsOwned(self) then
				GameTooltip:Hide()
			end
		end)
		frame.SCMDisabledTooltipOverlay = overlay
	end

	overlay.ownerWidget = widget
	return overlay
end

function Utils.RefreshDisabledTooltip(widget)
	local overlay = CreateDisabledTooltipOverlay(widget)
	if not overlay then
		return
	end

	local tooltip = widget._scmDisabledTooltip
	if widget.disabled and tooltip and tooltip ~= "" then
		overlay:Show()
		return
	end

	overlay:Hide()
	if GameTooltip:IsOwned(overlay) then
		GameTooltip:Hide()
	end
end

function Utils.SetDisabledTooltip(widget, tooltip)
	if not widget or not widget.frame then
		return
	end

	if not widget._scmDisabledTooltipHooked then
		widget._scmDisabledTooltipHooked = true

		local originalOnAcquire = widget.OnAcquire
		widget.OnAcquire = function(self, ...)
			if originalOnAcquire then
				originalOnAcquire(self, ...)
			end

			self._scmDisabledTooltip = nil
			if self.frame and self.frame.SCMDisabledTooltipOverlay then
				self.frame.SCMDisabledTooltipOverlay:Hide()
			end
		end

		local originalSetDisabled = widget.SetDisabled
		widget.SetDisabled = function(self, disabled)
			originalSetDisabled(self, disabled)
			Utils.RefreshDisabledTooltip(self)
		end
	end

	widget._scmDisabledTooltip = tooltip
	Utils.RefreshDisabledTooltip(widget)
end

function Utils.ResetChildSCMState(child)
	if not child then
		return
	end

	if child.SCMHideTimer then
		child.SCMHideTimer:Cancel()
		child.SCMHideTimer = nil
	end

	if child.SCMGlow then
		SCM:StopCustomGlow(child)
	end

	if child.Icon then
		child.Icon.SCMDesaturated = nil
	end

	for index = 1, #CHILD_SCM_RESET_FIELDS do
		child[CHILD_SCM_RESET_FIELDS[index]] = nil
	end
end

function Utils.ToGlobalGroup(index)
	return GLOBAL_GROUP_OFFSET + (index or 1)
end

function Utils.ToBuffBarGroup(index)
	return GLOBAL_BUFF_BAR_OFFSET + (index or 1)
end

function Utils.IsGlobalGroup(group)
	return type(group) == "number" and group >= FIRST_GLOBAL_GROUP and group < FIRST_BUFF_BAR_GROUP
end

function Utils.IsBuffBarGroup(group)
	return type(group) == "number" and group >= FIRST_BUFF_BAR_GROUP
end

function Utils.ParseAnchorString(anchorRef)
	if type(anchorRef) ~= "string" then
		return
	end

	if anchorRef:sub(1, 7) ~= "ANCHOR:" then
		return
	end

	local anchorType, anchorID = anchorRef:match("^ANCHOR:([%a]+):(%d+)$")
	if anchorType and anchorID then
		anchorID = tonumber(anchorID)
		if not anchorID or anchorID <= 0 then
			return
		end

		anchorType = string.upper(anchorType)
		if anchorType == "I" then
			return anchorID
		elseif anchorType == "G" then
			return Utils.ToGlobalGroup(anchorID)
		elseif anchorType == "BB" then
			return Utils.ToBuffBarGroup(anchorID)
		end

		return
	end

	anchorID = anchorRef:match("^ANCHOR:(%d+)$")
	anchorID = anchorID and tonumber(anchorID) or nil
	if not anchorID or anchorID <= 0 or anchorID == GLOBAL_GROUP_OFFSET or anchorID == GLOBAL_BUFF_BAR_OFFSET then
		return
	end

	return anchorID
end

function Utils.GetAnchorFrame(anchorRef)
	if type(anchorRef) == "table" then
		return anchorRef
	end

	if type(anchorRef) ~= "string" or anchorRef == "" or anchorRef == "NONE" then
		return
	end

	if anchorRef:sub(1, 7) ~= "ANCHOR:" then
		return _G[anchorRef] or SCM[anchorRef]
	end

	local anchorGroup = Utils.ParseAnchorString(anchorRef)
	if anchorGroup then
		return SCM:GetAnchor(anchorGroup)
	end

	return
end

function Utils.GetPairedSource(sourceIndex)
	if sourceIndex == Enum.CooldownViewerCategory.TrackedBuff or sourceIndex == Enum.CooldownViewerCategory.TrackedBar then
		return
	end

	return SCM.Constants.SourcePairs[sourceIndex]
end

function Utils.NormalizeBuffBarGroup(group)
	group = tonumber(group)
	if not group or group <= 0 or group == GLOBAL_GROUP_OFFSET or group == GLOBAL_BUFF_BAR_OFFSET then
		return
	end

	if group >= FIRST_BUFF_BAR_GROUP then
		return group
	end

	if group >= FIRST_GLOBAL_GROUP then
		return Utils.ToBuffBarGroup(group - GLOBAL_GROUP_OFFSET)
	end

	return Utils.ToBuffBarGroup(group)
end

function Utils.GetAnchorConfigForGroup(config, group, globalAnchorConfig, buffBarAnchorConfig)
	if config and config.anchorConfig and config.anchorConfig[group] then
		return config.anchorConfig[group]
	end

	if Utils.IsGlobalGroup(group) then
		return globalAnchorConfig and globalAnchorConfig[group - GLOBAL_GROUP_OFFSET]
	end

	if Utils.IsBuffBarGroup(group) then
		return buffBarAnchorConfig and buffBarAnchorConfig[group - GLOBAL_BUFF_BAR_OFFSET]
	end
end

function Utils.SortBySCMOrder(a, b)
	return (a.SCMOrder or 0) < (b.SCMOrder or 0)
end

function Utils.AddChildToGroup(validChildren, group, child, isGlobal)
	if isGlobal then
		group = Utils.ToGlobalGroup(group)
		child.SCMGlobal = true
	end

	local groupChildren = GetOrCreateTableEntry(validChildren, group)
	groupChildren[#groupChildren + 1] = child
	return group
end

function Utils.GetIconType(config)
	if not config or not (type(config) == "table") then return end
	return config.iconType or (config.spellID and "spell") or "item"
end
