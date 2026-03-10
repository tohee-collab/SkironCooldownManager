local _, SCM = ...

SCM.Utils = SCM.Utils or {}

local Utils = SCM.Utils
local GLOBAL_GROUP_OFFSET = 100

local function EnsureDisabledTooltipOverlay(widget)
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
	local overlay = EnsureDisabledTooltipOverlay(widget)
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

function Utils.ToGlobalGroup(index)
	return GLOBAL_GROUP_OFFSET + (index or 1)
end

function Utils.GetAnchorConfigForGroup(config, group, globalAnchorConfig)
	if config and config.anchorConfig and config.anchorConfig[group] then
		return config.anchorConfig[group]
	end

	if group < GLOBAL_GROUP_OFFSET then
		return
	end

	if not globalAnchorConfig then
		return
	end

	return globalAnchorConfig[group - GLOBAL_GROUP_OFFSET]
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
