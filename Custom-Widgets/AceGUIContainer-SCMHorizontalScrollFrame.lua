--[[-----------------------------------------------------------------------------
ScrollFrame Container
Plain container that scrolls its content and doesn't grow in height.
-------------------------------------------------------------------------------]]

local Type, Version = "SCMHorizontalScrollFrame", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

-- Lua APIs
local pairs, assert, type = pairs, assert, type
local min, max, floor = math.min, math.max, math.floor

-- WoW APIs
local CreateFrame, UIParent = CreateFrame, UIParent

--[[-----------------------------------------------------------------------------
Support functions
-------------------------------------------------------------------------------]]
local function GetCursorScaled(controller)
	local x, y = GetCursorPosition()
	local scale = controller:GetEffectiveScale()
	return x / scale, y / scale
end

local function UpdateMarkerPosition(frame, cursorX, marker)
	local left = frame:GetLeft()
	local right = frame:GetRight()
	local centerX = (left + right) / 2
	marker:ClearAllPoints()

	if cursorX < centerX then
		marker:SetPoint("CENTER", frame, "LEFT", -3, 0)
		return false -- before
	else
		marker:SetPoint("CENTER", frame, "RIGHT", 3, 0)
		return true -- after
	end
end

local function FindBestTarget(scrollView, cursorX, draggedFrame)
	local best
	scrollView:ForEachFrame(function(frame)
		if frame:IsShown() and cursorX >= frame:GetLeft() and cursorX <= frame:GetRight() and not (frame == draggedFrame) and not frame.data.isAddButton then
			best = frame
		end
	end)
	return best
end

--[[-----------------------------------------------------------------------------
Scripts
-------------------------------------------------------------------------------]]
local function Controller_OnUpdate(self)
	if not self.draggedFrame then
		return
	end

	local cursorX = GetCursorScaled(self)
	local target = FindBestTarget(self.scrollView, cursorX, self.draggedFrame)
	self.reorderTarget = target
	self.marker:SetShown(target ~= nil)
	if target then
		local after = UpdateMarkerPosition(target, cursorX, self.marker)
		if after then
			if target.data.dataIndex < self.draggedFrame.data.dataIndex then
				self.reorderOffset = 1
			else
				self.reorderOffset = 0
			end
		else
			if target.data.dataIndex < self.draggedFrame.data.dataIndex then
				self.reorderOffset = 0
			else
				self.reorderOffset = -1
			end
		end
	else
		self.reorderOffset = -1
	end
end

local function Button_OnDragStart(self)
	self:StartMoving()
	self:SetAlpha(0)

	local controller = self.controller
	controller.draggedFrame = self
	controller.draggedIndex = self.data.dataIndex
	controller.reorderTarget = self
	controller.marker:Show()

	controller:Show()
	controller.Icon:SetTexture(self.data.texture)
	controller:ClearAllPoints()
	controller:SetPoint("CENTER", self, "CENTER")
	controller:SetScript("OnUpdate", Controller_OnUpdate)
end

local function Button_OnDragStop(self)
	self:StopMovingOrSizing()
	self:SetAlpha(1)

	local controller = self.controller
	local dataProvider = self.dataProvider

	local source = controller.draggedFrame
	local sourceIndex = controller.draggedIndex
	local target = controller.reorderTarget
	local offfset = controller.reorderOffset

	controller.draggedFrame = nil
	controller.draggedIndex = nil
	controller.reorderTarget = nil
	controller.reorderOffset = 0
	controller.marker:Hide()
	controller:SetScript("OnUpdate", nil)
	controller:Hide()

	if source and target then
		local targetIndex = target.data.dataIndex + offfset
		if sourceIndex == targetIndex then
			self.scrollBox:Layout()
			return
		end

		targetIndex = math.max(1, math.min(dataProvider:GetSize(), targetIndex))

		if source.data and dataProvider:FindIndex(source.data) then
			--source.data.dataIndex = targetIndex
			--dataProvider:Sort()
			local sortComparator = dataProvider.sortComparator
			dataProvider:ClearSortComparator()
			dataProvider:MoveElementDataToIndex(source.data, targetIndex)

			for i, entry in ipairs(dataProvider:GetCollection()) do
				if not entry.isAddButton then
					entry.dataIndex = i
				end
			end

			dataProvider:SetSortComparator(sortComparator)
			self.obj:Fire("OnDragStop", dataProvider:GetCollection())
		end
	end

	self.scrollBox:Layout()
end

local function Button_OnClick(self, button, down)
	if down then
		self.obj:Fire("OnGroupSelected", self, button)
	end
end

--[[-----------------------------------------------------------------------------
Methods
-------------------------------------------------------------------------------]]
local methods = {
	["OnAcquire"] = function(self)
		self.dataProvider:Flush()
	end,

	["OnRelease"] = function(self)
		self.dataProvider:Flush()
	end,

	["SetScroll"] = function(self, value) end,

	["MoveScroll"] = function(self, value) end,

	["FixScroll"] = function(self) end,

	["LayoutFinished"] = function(self, width, height) end,

	["SetStatusTable"] = function(self, status) end,

	["OnWidthSet"] = function(self, width)
		self.frame:SetWidth(width)
	end,

	["OnHeightSet"] = function(self, height)
		self.frame:SetHeight(height)
	end,

	["AddSpellBySpellID"] = function(self, info, dataIndex, isBuffIcon)
		if not dataIndex then
			local highestIndex = 0
			for _, data in self.dataProvider:Enumerate() do
				if data.dataIndex > highestIndex and data.dataIndex < 100 then
					highestIndex = data.dataIndex
				end
			end
			self.dataProvider.highestIndex = highestIndex
			dataIndex = highestIndex + 1
		end

		self.dataProvider:Insert({
			dataIndex = dataIndex,
			texture = C_Spell.GetSpellTexture(info.spellID),
			spellID = info.spellID,
			isKnown = info.isKnown,
			isDisabled = info.isDisabled or (info.category and info.category < 0),
			isBuffIcon = isBuffIcon or info.category >= 2,
			cooldownID = info.cooldownID,
		})

		return dataIndex
	end,

	["AddSpellByCooldownID"] = function(self, cooldownID)
		--self.dataProvider:Insert()
	end,

	["AddAddButton"] = function(self)
		self.dataProvider:Insert({ dataIndex = 100, isAddButton = true })
	end,

	["RemoveButton"] = function(self, data)
		self.dataProvider:Remove(data)

		local highestIndex = 0
		for _, data in self.dataProvider:Enumerate() do
			if data.dataIndex > highestIndex and data.dataIndex < 100 then
				highestIndex = data.dataIndex
			end
		end
		self.dataProvider.highestIndex = highestIndex
	end,

	["SetSortComparator"] = function(self, sortComparator, skipSort)
		self.dataProvider:SetSortComparator(sortComparator, skipSort)
	end,

	["InitButton"] = function(self, button, data)
		button.controller = self.controller
		button.scrollBox = self.scrollBox
		button.dataProvider = self.dataProvider
		button.obj = self

		button:SetSize(45, 45)
		button.dataIndex = data.dataIndex
		button.data = data
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetScript("OnClick", Button_OnClick)

		if data.isAddButton then
			button.Icon:SetAtlas("cdm-empty")
			button:SetMovable(false)
		else
			button.Icon:SetTexture(data.texture)
			button.Icon:SetDesaturated(not data.isKnown)
			if data.isDisabled then
				button.Icon:SetVertexColor(1, 0, 0, 1)
			end
			button:RegisterForDrag("LeftButton")
			button:SetMovable(true)
			button:SetScript("OnDragStart", Button_OnDragStart)
			button:SetScript("OnDragStop", Button_OnDragStop)
		end
	end,
}
--[[-----------------------------------------------------------------------------
Constructor
-------------------------------------------------------------------------------]]
local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetHeight(50)
	frame:SetWidth(300)
	frame:SetFrameStrata("BACKGROUND")

	local dataProvider = CreateDataProvider()
	local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	scrollBox:SetAllPoints(frame)

	local name = (Type .. "%dScrollBar"):format(AceGUI:GetNextWidgetNum(Type))
	local scrollbar = CreateFrame("EventFrame", name, frame, "WowTrimHorizontalScrollBar")
	scrollbar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT")
	scrollbar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT")

	local scrollbg = scrollBox:CreateTexture(nil, "BACKGROUND")
	scrollbg:SetAllPoints(scrollBox)
	scrollbg:SetColorTexture(0, 0, 0, 0.4)

	local scrollView = CreateScrollBoxListLinearView(10, 5, 5, 5, 5)
	scrollView:SetHorizontal(true)
	scrollView:SetElementExtent(45)

	local controller = CreateFrame("Button", nil, UIParent, "PermokScrollIconTemplate")
	--controller:SetAllPoints(frame)
	controller:SetSize(40, 40)
	controller:SetFrameStrata("TOOLTIP")
	controller:Hide()
	controller.scrollView = scrollView

	local markerFrame = CreateFrame("Frame", nil, scrollBox)
	markerFrame:SetSize(2, 45)
	markerFrame:Hide()

	local marker = markerFrame:CreateTexture(nil, "OVERLAY")
	marker:SetAllPoints()
	marker:SetColorTexture(1, 1, 1, 0.8)
	controller.marker = markerFrame

	scrollView:SetElementInitializer("PermokScrollIconTemplate", function(button, data)
		frame.obj:InitButton(button, data)
	end)

	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollbar, scrollView)
	scrollView:SetDataProvider(dataProvider)

	local widget = {
		localstatus = { scrollvalue = 0 },
		scrollbar = scrollbar,
		scrollView = scrollView,
		scrollBox = scrollBox,
		controller = controller,
		dataProvider = dataProvider,
		frame = frame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	frame.obj, scrollbar.obj = widget, widget

	--- DON'T YELL AT ME I KNOW THAT IT SHOULD BE CONTAINER
	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
