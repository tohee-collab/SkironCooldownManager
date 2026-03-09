local addonName, SCM = ...
local AceGUI = LibStub("AceGUI-3.0")
local LibCustomGlow = LibStub("LibCustomGlow-1.0")

local colorKnown = "ffffff"
local colorUnknown = "808080"
local colorDisabled = "ff0000"

SCM.MainTabs.CDM = { value = "CDM", text = "Cooldown Manager", order = 2, subgroups = {} }
SCM.CustomEntries = {}

local iconTypeTabs = {
	all = {
		{ value = "general", text = "General" },
		{ value = "load", text = "Load Conditions" },
		--{ value = "load", text = "Load Conditions"},
	},
	spell = {},
	item = {},
	slot = {
		-- { value = "filter", text = "Filter" },
	},
}
for iconType, options in pairs(iconTypeTabs) do
	if iconType ~= "all" then
		for i = #iconTypeTabs.all, 1, -1 do
			tinsert(options, 1, iconTypeTabs.all[i])
		end
	end
end

local function SortByIndex(a, b)
	return a.dataIndex < b.dataIndex
end

local function ShowNumericInputPopup(key, title, callback)
	StaticPopupDialogs[key] = StaticPopupDialogs[key]
		or {
			text = title,
			button1 = ACCEPT,
			button2 = CANCEL,
			hasEditBox = true,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnAccept = function(self)
				local id = tonumber(self.EditBox:GetText() or "")
				if id and id > 0 then
					callback(id)
				end
			end,
		}
	StaticPopup_Show(key)
end

local function GetSlotTexture(slotID)
	return GetInventoryItemTexture("player", slotID) or 134400
end

local function ApplyAnchorGroupUpdate(anchorIndex, isGlobal)
	SCM:ApplyAnchorGroupCDManagerConfig(anchorIndex, isGlobal)
end

local function BuildSpellIconData(spellID)
	local texture = C_Spell.GetSpellTexture(spellID)
	if not texture then
		return
	end

	return {
		texture = texture,
		spellID = spellID,
	}
end

local function BuildItemIconData(itemID)
	local texture = C_Item.GetItemIconByID(itemID)
	if not texture then
		return
	end

	return {
		texture = texture,
		spellID = 0,
		itemID = itemID,
	}
end

local function BuildSlotIconData(slotID)
	if slotID < 1 or slotID > 19 then
		return
	end

	return {
		texture = GetSlotTexture(slotID),
		spellID = 0,
		slotID = slotID,
	}
end

local customButtonConfigs = {
	{
		text = "Spell CD",
		popupKey = "SCM_CUSTOM_SPELL_ID",
		popupTitle = "Enter Spell ID",
		iconType = "spell",
		buildIconData = BuildSpellIconData,
	},
	{
		text = "Item CD",
		popupKey = "SCM_CUSTOM_ITEM_ID",
		popupTitle = "Enter Item ID",
		iconType = "item",
		buildIconData = BuildItemIconData,
	},
	{
		text = "Slot CD",
		popupKey = "SCM_SPEC_SLOT_ID",
		popupTitle = "Enter Slot ID",
		iconType = "slot",
		buildIconData = BuildSlotIconData,
	},
	{
		text = "Cast",
		popupKey = "SCM_CAST_SPELL_ID",
		popupTitle = "Enter Spell ID",
		iconType = "cast",
		buildIconData = BuildSpellIconData,
	},
}

local function CreateCustomIconButton(rootDescription, scrollFrame, anchorIndex, isGlobal, buttonConfig)
	rootDescription:CreateButton(buttonConfig.text, function()
		ShowNumericInputPopup(buttonConfig.popupKey, buttonConfig.popupTitle, function(configID)
			local iconData = buttonConfig.buildIconData(configID)
			if not iconData then
				return
			end

			local uniqueID = SCM:GetUniqueID(configID, buttonConfig.iconType, isGlobal)
			iconData.iconType = buttonConfig.iconType
			iconData.id = uniqueID
			iconData.isCustom = true

			local order = scrollFrame:AddCustomIcon(iconData)
			SCM:AddCustomIcon(anchorIndex, buttonConfig.iconType, configID, order, uniqueID, isGlobal)
			ApplyAnchorGroupUpdate(anchorIndex, isGlobal)
		end)
	end)
end

local function CreateCustomIconButtons(rootDescription, scrollFrame, anchorIndex, isGlobal, buttonConfigs)
	for _, buttonConfig in ipairs(buttonConfigs) do
		CreateCustomIconButton(rootDescription, scrollFrame, anchorIndex, isGlobal, buttonConfig)
	end
end

local function CreateAddSpellDropdown(owner, rootDescription, scrollFrame, anchorIndex, isGlobal)
	rootDescription:CreateTitle("Add Icon")

	if isGlobal then
		if SCM.db.global.options.enableCustomIcons then
			CreateCustomIconButtons(rootDescription, scrollFrame, anchorIndex, true, customButtonConfigs)
		end
		return
	end

	local dataProvider = CooldownViewerSettings:GetDataProvider()
	local cooldownInfoByID = dataProvider and dataProvider.displayData.cooldownInfoByID
	--local cooldownDefaultsByID = dataProvider and dataProvider.displayData.cooldownDefaultsByID

	local essentialButton = rootDescription:CreateButton("Essential")
	local utilityButton = rootDescription:CreateButton("Utility")
	local buffButton = rootDescription:CreateButton("Buff")

	local function GetSortRank(info, data)
		if data.category < 0 then
			return 3
		end
		if info.isKnown then
			return 1
		end
		return 2
	end

	local function SortSpells(a, b)
		local rankA = GetSortRank(a.info, a.data)
		local rankB = GetSortRank(b.info, b.data)

		if rankA ~= rankB then
			return rankA < rankB
		end
		return C_Spell.GetSpellName(a.info.spellID) < C_Spell.GetSpellName(b.info.spellID)
	end

	local function ProcessAndCreateButtons(parentButton, items, isBuffIcon)
		table.sort(items, SortSpells)

		for _, item in ipairs(items) do
			local data = item.data
			local cooldownID = item.cooldownID
			local info = item.info
			info.cooldownID = item.cooldownID
			info.isDisabled = data.category < 0

			local activeColor = (data.category < 0 and colorDisabled) or (info.isKnown and colorKnown) or colorUnknown
			parentButton:CreateButton(string.format("|T%d:0|t |cff%s%s (%d)|r", C_Spell.GetSpellTexture(info.spellID), activeColor, C_Spell.GetSpellName(info.spellID), cooldownID), function(info)
				local dataIndex = scrollFrame:AddSpellBySpellID(info)
				SCM:AddSpellToConfig(anchorIndex, dataIndex, info, data, item.targetCategory, isBuffIcon)
				SCM:ApplyAllCDManagerConfigs()
			end, info)
		end
	end

	local essentialItems = {}
	local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(0, true)
	for _, cooldownID in ipairs(cooldownIDs) do
		local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
		local data = cooldownInfoByID[cooldownID]

		if info and data then
			if not SCM:IsSpellInData(data.spellID, data.category) and not scrollFrame.dataProvider:FindByPredicate(function(data)
				return data.spellID == info.spellID
			end) then
				table.insert(essentialItems, { info = info, data = data, cooldownID = cooldownID, targetCategory = 0 })
			end
		end
	end

	essentialButton:SetGridMode(MenuConstants.VerticalGridDirection, floor(#essentialItems / 15) + 1)
	ProcessAndCreateButtons(essentialButton, essentialItems)

	local utilityItems = {}
	cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(1, true)
	for _, cooldownID in ipairs(cooldownIDs) do
		local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
		local data = cooldownInfoByID[cooldownID]

		if info and data then
			if not SCM:IsSpellInData(data.spellID, data.category) and not scrollFrame.dataProvider:FindByPredicate(function(data)
				return data.spellID == info.spellID
			end) then
				table.insert(utilityItems, { info = info, data = data, cooldownID = cooldownID, targetCategory = 1 })
			end
		end
	end

	utilityButton:SetGridMode(MenuConstants.VerticalGridDirection, floor(#utilityItems / 15) + 1)

	ProcessAndCreateButtons(utilityButton, utilityItems)

	local buffItems = {}

	cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(2, true)
	for _, cooldownID in ipairs(cooldownIDs) do
		local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
		local data = cooldownInfoByID[cooldownID]

		if info and data then
			if not SCM:IsSpellInData(data.spellID, data.category) and not scrollFrame.dataProvider:FindByPredicate(function(data)
				return data.spellID == info.spellID
			end) then
				table.insert(buffItems, { info = info, data = data, cooldownID = cooldownID, targetCategory = 2 })
			end
		end
	end

	cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(3, true)
	for _, cooldownID in ipairs(cooldownIDs) do
		local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
		local data = cooldownInfoByID[cooldownID]

		if info and data and data.category < 3 then
			if not SCM:IsSpellInData(data.spellID, data.category) and not scrollFrame.dataProvider:FindByPredicate(function(data)
				return data.spellID == info.spellID
			end) then
				table.insert(buffItems, { info = info, data = data, cooldownID = cooldownID, targetCategory = 3 })
			end
		end
	end

	buffButton:SetGridMode(MenuConstants.VerticalGridDirection, floor(#buffItems / 15) + 1)

	ProcessAndCreateButtons(buffButton, buffItems, true)

	if SCM.db.global.options.enableCustomIcons then
		rootDescription:CreateDivider()
		CreateCustomIconButtons(rootDescription, scrollFrame, anchorIndex, false, customButtonConfigs)

		for _, customEntry in pairs(SCM.CustomEntries) do
			customEntry(rootDescription, scrollFrame, anchorIndex)
		end
	end
end

local function SelectRow(self, data, anchorIndex, rowIndex, rowTabsTbl, isGlobal)
	self:ReleaseChildren()

	if not data.rowConfig[rowIndex] then
		return
	end

	local iconWidth = AceGUI:Create("Slider")
	iconWidth:SetRelativeWidth(0.33)
	iconWidth:SetSliderValues(10, 200, 0.1)
	iconWidth:SetLabel("Icon Width")
	iconWidth:SetValue(data.rowConfig[rowIndex].iconWidth or data.rowConfig[rowIndex].size)
	iconWidth:SetCallback("OnValueChanged", function(self, event, value)
		data.rowConfig[rowIndex].iconWidth = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	self:AddChild(iconWidth)

	local iconHeight = AceGUI:Create("Slider")
	iconHeight:SetRelativeWidth(0.33)
	iconHeight:SetSliderValues(10, 200, 0.1)
	iconHeight:SetLabel("Icon Height")
	iconHeight:SetValue(data.rowConfig[rowIndex].iconHeight or data.rowConfig[rowIndex].size)
	iconHeight:SetCallback("OnValueChanged", function(self, event, value)
		data.rowConfig[rowIndex].iconHeight = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	self:AddChild(iconHeight)

	local limit = AceGUI:Create("Slider")
	limit:SetRelativeWidth(0.33)
	limit:SetSliderValues(1, 20, 1)
	limit:SetLabel("Limit")
	limit:SetValue(data.rowConfig[rowIndex].limit)
	limit:SetCallback("OnValueChanged", function(self, event, value)
		data.rowConfig[rowIndex].limit = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	self:AddChild(limit)

	local buttonGroup = AceGUI:Create("SimpleGroup")
	buttonGroup:SetFullWidth(true)
	buttonGroup:SetLayout("flow")
	self:AddChild(buttonGroup)

	local addRowButton = AceGUI:Create("Button")
	addRowButton:SetText("Add Row")
	addRowButton:SetRelativeWidth(0.5)
	addRowButton:SetDisabled(#rowTabsTbl >= 9)
	addRowButton:SetCallback("OnClick", function()
		local nextIndex = isGlobal and (#data.rowConfig + 1) or SCM:AddRow(anchorIndex)
		if isGlobal then
			data.rowConfig[nextIndex] = { size = 40, limit = 8 }
		end

		tinsert(rowTabsTbl, { value = nextIndex, text = "Row " .. nextIndex })
		table.sort(rowTabsTbl, function(a, b)
			return a.value < b.value
		end)
		self:SetTabs(rowTabsTbl)
		self:SelectTab(nextIndex)
		SCM:ApplyAllCDManagerConfigs()
	end)
	buttonGroup:AddChild(addRowButton)

	local deleteRowButton = AceGUI:Create("Button")
	deleteRowButton:SetText("Delete Row")
	deleteRowButton:SetRelativeWidth(0.5)
	deleteRowButton:SetDisabled(rowIndex == 1)
	deleteRowButton:SetCallback("OnClick", function()
		if isGlobal then
			tremove(data.rowConfig, rowIndex)
		else
			SCM:RemoveRow(anchorIndex, rowIndex)
		end

		local removedIndex
		for i, tab in ipairs(rowTabsTbl) do
			if tab.value == rowIndex then
				removedIndex = i
				tremove(rowTabsTbl, i)
				break
			end
		end

		for i = removedIndex, #rowTabsTbl do
			rowTabsTbl[i].value = i
			rowTabsTbl[i].text = "Row " .. i
		end

		self:SetTabs(rowTabsTbl)
		self:SelectTab(#rowTabsTbl)
		SCM:ApplyAllCDManagerConfigs()
	end)
	buttonGroup:AddChild(deleteRowButton)
end

local function SelectAnchor(anchorWidget, frame, anchorIndex, anchorTabsTbl, isGlobal)
	anchorWidget:ReleaseChildren()

	SCM.activeAnchorSettings = anchorIndex
	local options = SCM.db.global.options

	if options.showAnchorHighlight then
		for group, anchorFrame in pairs(SCM.anchorFrames) do
			local activeGroup = isGlobal and (100 + anchorIndex) or anchorIndex
			if group == activeGroup then
				anchorFrame.isGlowActive = true
				LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
				LibCustomGlow.PixelGlow_Start(anchorFrame, { 0.34, 0.70, 0.91, 1 }, nil, nil, nil, nil, nil, nil, nil, "SCM")
				anchorFrame.debugText:SetTextColor(0.34, 0.70, 0.91, 1)
			else
				anchorFrame.isGlowActive = false
				LibCustomGlow.PixelGlow_Stop(anchorFrame, "SCM")
				LibCustomGlow.PixelGlow_Start(anchorFrame, nil, nil, nil, nil, nil, nil, nil, nil, "SCM")
				anchorFrame.debugText:SetTextColor(0.90, 0.62, 0, 1)
			end
		end
	end

	local data = isGlobal and SCM.db.global.globalAnchorConfig[anchorIndex] or SCM.anchorConfig[anchorIndex]
	if not data then
		return
	end

	local scrollFrame = AceGUI:Create("ScrollFrame")
	scrollFrame:SetLayout("flow")
	anchorWidget:AddChild(scrollFrame)

	local anchorOptions = AceGUI:Create("InlineGroup")
	anchorOptions:SetLayout("flow")
	anchorOptions:SetFullWidth(true)
	anchorOptions:SetHeight(250)
	anchorOptions:SetTitle("Anchor Options")
	scrollFrame:AddChild(anchorOptions)

	local buttonGroup = AceGUI:Create("SimpleGroup")
	buttonGroup:SetFullWidth(true)
	buttonGroup:SetLayout("flow")
	anchorOptions:AddChild(buttonGroup)

	local addAnchorButton = AceGUI:Create("Button")
	addAnchorButton:SetText("Add Anchor")
	addAnchorButton:SetRelativeWidth(0.5)
	addAnchorButton:SetDisabled(#anchorTabsTbl >= 15)
	addAnchorButton:SetCallback("OnClick", function()
		local nextIndex = isGlobal and SCM:AddGlobalAnchor(anchorTabsTbl) or SCM:AddAnchor(anchorTabsTbl, frame)
		anchorWidget:SetTabs(anchorTabsTbl)
		anchorWidget:SelectTab(nextIndex)
	end)
	buttonGroup:AddChild(addAnchorButton)

	local deleteAnchorButton = AceGUI:Create("Button")
	deleteAnchorButton:SetText("Delete Anchor")
	deleteAnchorButton:SetRelativeWidth(0.5)
	deleteAnchorButton:SetDisabled((not isGlobal and anchorIndex <= 3) or (isGlobal and anchorIndex == 1))
	deleteAnchorButton:SetCallback("OnClick", function()
		if isGlobal then
			SCM:RemoveGlobalAnchor(anchorIndex, anchorTabsTbl)
		else
			SCM:RemoveAnchor(anchorIndex, anchorTabsTbl)
		end
		anchorWidget:SetTabs(anchorTabsTbl)
		anchorWidget:SelectTab(#anchorTabsTbl)
	end)
	buttonGroup:AddChild(deleteAnchorButton)

	local point = AceGUI:Create("Dropdown")
	point:SetRelativeWidth(0.25)
	point:SetLabel("Point")
	point:SetList(SCM.Constants.AnchorPoints)
	point:SetValue(data.anchor[1])
	point:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[1] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(point)

	local relativeTo = AceGUI:Create("EditBox")
	relativeTo:SetRelativeWidth(0.25)
	relativeTo:SetLabel("Anchor Frame")
	relativeTo:SetText(data.anchor[2])
	relativeTo:SetCallback("OnEnterPressed", function(self, event, text)
		data.anchor[2] = text
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(relativeTo)

	local relativePoint = AceGUI:Create("Dropdown")
	relativePoint:SetRelativeWidth(0.25)
	relativePoint:SetLabel("Relative Point")
	relativePoint:SetList(SCM.Constants.AnchorPoints)
	relativePoint:SetValue(data.anchor[3])
	relativePoint:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[3] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(relativePoint)

	local grow = AceGUI:Create("Dropdown")
	grow:SetRelativeWidth(0.25)
	grow:SetList(SCM.Constants.GrowthDirections)
	grow:SetLabel("Growth Direction")
	grow:SetValue(data.grow or "CENTERED")
	grow:SetCallback("OnValueChanged", function(self, event, value)
		data.grow = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(grow)

	local spacing = AceGUI:Create("Slider")
	spacing:SetRelativeWidth(0.33)
	spacing:SetSliderValues(-10, 50, 0.1)
	spacing:SetLabel("Horizontal Spacing")
	spacing:SetValue(data.spacing or 0)
	spacing:SetCallback("OnValueChanged", function(self, event, value)
		data.spacing = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(spacing)

	local xOffset = AceGUI:Create("Slider")
	xOffset:SetRelativeWidth(0.33)
	xOffset:SetSliderValues(-1000, 1000, 0.1)
	xOffset:SetLabel("X Offset")
	xOffset:SetValue(data.anchor[4])
	xOffset:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[4] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(xOffset)

	local yOffset = AceGUI:Create("Slider")
	yOffset:SetRelativeWidth(0.33)
	yOffset:SetSliderValues(-1000, 1000, 0.1)
	yOffset:SetLabel("Y Offset")
	yOffset:SetValue(data.anchor[5])
	yOffset:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[5] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(yOffset)

	local rowTabsTbl = {}
	for i, row in ipairs(data.rowConfig) do
		tinsert(rowTabsTbl, { value = i, text = "Row " .. i })
	end

	local rowTabs = AceGUI:Create("TabGroup")
	rowTabs:SetLayout("flow")
	rowTabs:SetFullWidth(true)
	rowTabs:SetTabs(rowTabsTbl)
	rowTabs:SetCallback("OnGroupSelected", function(self, event, rowIndex)
		SelectRow(self, data, anchorIndex, rowIndex, rowTabsTbl, isGlobal)
	end)
	rowTabs:SelectTab(1)
	anchorOptions:AddChild(rowTabs)

	local top = AceGUI:Create("InlineGroup")
	top:SetLayout("flow")
	top:SetFullWidth(true)
	top:SetHeight(120)
	top:SetTitle("Spell Config")
	scrollFrame:AddChild(top)

	top:PauseLayout()
	local horizontalScrollFrame = AceGUI:Create("SCMHorizontalScrollFrame")
	horizontalScrollFrame:SetHeight(86)
	horizontalScrollFrame:SetFullWidth(true)
	horizontalScrollFrame.scrollbar:ClearAllPoints()
	horizontalScrollFrame.scrollbar:SetPoint("BOTTOMLEFT", horizontalScrollFrame.frame, "BOTTOMLEFT")
	horizontalScrollFrame.scrollbar:SetPoint("BOTTOMRIGHT", horizontalScrollFrame.frame, "BOTTOMRIGHT")
	horizontalScrollFrame.scrollBox:ClearAllPoints()
	horizontalScrollFrame.scrollBox:SetPoint("TOPLEFT", horizontalScrollFrame.frame, "TOPLEFT")
	horizontalScrollFrame.scrollBox:SetPoint("BOTTOMRIGHT", horizontalScrollFrame.scrollbar, "TOPRIGHT", 0, 2)

	horizontalScrollFrame:SetSortComparator(SortByIndex)

	local spells = {}
	if not isGlobal and SCM.spellConfig then
		local defaultCooldownViewerConfig = SCM.defaultCooldownViewerConfig
		for spellID, info in pairs(SCM.spellConfig) do
			if info.anchorGroup[anchorIndex] then
				for sourceIndex, spellAnchorIndex in pairs(info.source) do
					if anchorIndex == spellAnchorIndex then
						local data = defaultCooldownViewerConfig[sourceIndex]
						if data then
							if not data.spellIDs[spellID] then
								local pairData = defaultCooldownViewerConfig[SCM.Constants.SourcePairs[sourceIndex]]
								if pairData and pairData.spellIDs[spellID] then
									data = pairData
								end
							end

							if data.spellIDs[spellID] then
								tinsert(spells, { info = info, data = data.spellIDs[spellID], isBuffIcon = sourceIndex >= 2 })
								break
							end
						end
					end
				end
			end
		end
	end

	local function AddCustomCollection(customConfig)
		for _, config in pairs(customConfig) do
			if config.anchorGroup == anchorIndex then
				local iconType = config.iconType or (config.spellID and "spell") or "item"
				local texture
				if iconType == "spell" then
					texture = C_Spell.GetSpellTexture(config.spellID)
				elseif iconType == "slot" then
					texture = config.slotID and GetSlotTexture(config.slotID)
				else
					texture = C_Item.GetItemIconByID(config.itemID)
				end

				if texture or SCM.isOptionsOpen then
					tinsert(spells, {
						order = config.order,
						texture = texture or 134400,
						spellID = config.spellID or 0,
						itemID = config.itemID,
						slotID = config.slotID,
						iconType = iconType,
						id = config.id,
						isCustom = true,
					})
				end
			end
		end
	end

	if isGlobal then
		for _, customConfig in pairs(SCM.globalCustomConfig) do
			AddCustomCollection(customConfig)
		end
	else
		for _, customConfig in pairs(SCM.customConfig) do
			AddCustomCollection(customConfig)
		end
	end

	table.sort(spells, function(a, b)
		return (a.order or a.info.anchorGroup[anchorIndex].order) < (b.order or b.info.anchorGroup[anchorIndex].order)
	end)

	for _, spellInfo in ipairs(spells) do
		if spellInfo.isCustom then
			horizontalScrollFrame:AddCustomIcon(spellInfo)
		else
			horizontalScrollFrame:AddSpellBySpellID(spellInfo.data, spellInfo.info.anchorGroup[anchorIndex].order, spellInfo.isBuffIcon)
		end
	end

	horizontalScrollFrame:AddAddButton()

	local iconSettings = AceGUI:Create("InlineGroup")
	iconSettings:SetLayout("flow")
	iconSettings:SetFullWidth(true)
	iconSettings:SetHeight(120)
	iconSettings:SetTitle("")
	scrollFrame:AddChild(iconSettings)

	local label = AceGUI:Create("Label")
	label:SetRelativeWidth(1.0)
	label:SetHeight(24)
	label:SetJustifyH("CENTER")
	label:SetJustifyV("MIDDLE")
	label:SetText("|TInterface\\common\\help-i:40:40:0:0|tClick on an icon above to show spell specific options.")
	label:SetFontObject("Game12Font")
	iconSettings:AddChild(label)

	local lastButtonFrame
	horizontalScrollFrame:SetCallback("OnGroupSelected", function(scrollFrameWidget, event, buttonFrame, button)
		iconSettings:ReleaseChildren()

		if lastButtonFrame then
			lastButtonFrame:SetBackdropBorderColor(BLACK_FONT_COLOR:GetRGBA())
		end

		if button == "LeftButton" then
			if buttonFrame.data.isAddButton then
				local menu = MenuUtil.CreateContextMenu(nil, function(owner, rootDescription)
					CreateAddSpellDropdown(owner, rootDescription, horizontalScrollFrame, anchorIndex, isGlobal)
				end)
			else
				if not lastButtonFrame or lastButtonFrame ~= buttonFrame then
					local buttonData = buttonFrame.data
					local buttonConfig = buttonData.isCustom and SCM:GetConfigTableByID(buttonData.id, buttonData.iconType, isGlobal) or SCM.spellConfig[buttonData.spellID]

					buttonFrame:SetBackdropBorderColor(0, 1, 0, 1)

					if buttonConfig then
						local function ApplyIconConfigUpdate()
							if buttonFrame.data.isCustom then
								ApplyAnchorGroupUpdate(anchorIndex, isGlobal)
								return
							end
							SCM:ApplyAllCDManagerConfigs()
						end

						local iconSettingsTabs = AceGUI:Create("TabGroup")
						iconSettingsTabs:SetLayout("flow")
						iconSettingsTabs:SetFullWidth(true)
						iconSettingsTabs:SetTabs(iconTypeTabs[buttonData.iconType])
						iconSettingsTabs:SetCallback("OnGroupSelected", function(self, event, group)
							iconSettingsTabs:ReleaseChildren()

							if group == "general" then
								if buttonData.spellID and buttonData.spellID > 0 then
									iconSettings:SetTitle(C_Spell.GetSpellName(buttonData.spellID))
								elseif buttonData.itemID then
									iconSettings:SetTitle(C_Item.GetItemNameByID(buttonData.itemID))
								elseif buttonData.slotID then
									iconSettings:SetTitle("Slot ID " .. buttonData.slotID)
								end

								if buttonData.iconType == "spell" then
									local useCustomGlowColor = AceGUI:Create("CheckBox")
									useCustomGlowColor:SetLabel("Use Custom Glow Color")
									useCustomGlowColor:SetRelativeWidth(0.5)
									useCustomGlowColor:SetValue(buttonConfig.useCustomGlowColor)
									useCustomGlowColor:SetDisabled(not options.useCustomGlow)
									SCM.Utils.SetDisabledTooltip(useCustomGlowColor, "Enable 'Use Custom Glow' in Global Settings > Glow first.")
									useCustomGlowColor:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.useCustomGlowColor = value or nil
										ApplyIconConfigUpdate()
									end)
									iconSettingsTabs:AddChild(useCustomGlowColor)

									local customGlowColor = AceGUI:Create("ColorPicker")
									customGlowColor:SetRelativeWidth(0.33)
									customGlowColor:SetLabel("Glow Color")
									customGlowColor:SetHasAlpha(true)
									customGlowColor:SetDisabled(not options.useCustomGlow)
									if buttonConfig.customGlowColor then
										customGlowColor:SetColor(unpack(buttonConfig.customGlowColor))
									end
									customGlowColor:SetCallback("OnValueChanged", function(self, event, r, g, b, a)
										buttonConfig.customGlowColor = { r, g, b, a }
									end)
									iconSettingsTabs:AddChild(customGlowColor)
								end

								if not buttonFrame.data.isBuffIcon then
									local hideWhileReady = AceGUI:Create("CheckBox")
									hideWhileReady:SetLabel("Hide While Ready")
									hideWhileReady:SetRelativeWidth(0.5)
									hideWhileReady:SetValue(buttonConfig.hideWhenNotOnCooldown)
									hideWhileReady:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.hideWhenNotOnCooldown = value or nil
										ApplyIconConfigUpdate()
									end)
									iconSettingsTabs:AddChild(hideWhileReady)
								end

								if buttonFrame.data.isBuffIcon then
									local alwaysShow = AceGUI:Create("CheckBox")
									alwaysShow:SetLabel("Show Always")
									alwaysShow:SetRelativeWidth(0.5)
									alwaysShow:SetValue(buttonConfig.alwaysShow)
									alwaysShow:SetDisabled(not options.hideBuffsWhenInactive)
									SCM.Utils.SetDisabledTooltip(alwaysShow, "Enable 'Hide Inactive Auras' in Global Settings > General > Auras first.")
									iconSettingsTabs:AddChild(alwaysShow)

									local desaturate
									if not options.testSetting[buttonFrame.data.spellID] then
										desaturate = AceGUI:Create("CheckBox")
										desaturate:SetLabel("Desaturate While Inactive")
										desaturate:SetRelativeWidth(0.5)
										desaturate:SetValue(buttonConfig.desaturate)
										desaturate:SetDisabled(not buttonConfig.alwaysShow)
										SCM.Utils.SetDisabledTooltip(desaturate, "Enable 'Show Always' first.")
										desaturate:SetCallback("OnValueChanged", function(self, event, value)
											buttonConfig.desaturate = value or nil
											ApplyIconConfigUpdate()
										end)
										iconSettingsTabs:AddChild(desaturate)
									end
									alwaysShow:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.alwaysShow = value or nil
										ApplyIconConfigUpdate()

										if desaturate then
											desaturate:SetDisabled(not value)
										end
									end)
								end
							elseif group == "load" then
								local label = AceGUI:Create("Label")
								label:SetRelativeWidth(1.0)
								label:SetHeight(24)
								label:SetJustifyH("CENTER")
								label:SetJustifyV("MIDDLE")
								label:SetText("|TInterface\\common\\help-i:40:40:0:0|tNot yet implemented. Will come soon tm.")
								label:SetFontObject("Game12Font")
								iconSettings:AddChild(label)
							end
						end)
						iconSettingsTabs:SelectTab("general")
						iconSettings:AddChild(iconSettingsTabs)
						lastButtonFrame = buttonFrame
					end
				else
					iconSettings:SetTitle("")
					lastButtonFrame:SetBackdropBorderColor(BLACK_FONT_COLOR:GetRGBA())
					lastButtonFrame = nil

					local label = AceGUI:Create("Label")
					label:SetRelativeWidth(1.0)
					label:SetHeight(24)
					label:SetJustifyH("CENTER")
					label:SetJustifyV("MIDDLE")
					label:SetText("|TInterface\\common\\help-i:40:40:0:0|tClick on an icon to show spell specific options.")
					label:SetFontObject("Game12Font")
					iconSettings:AddChild(label)
				end
			end
		elseif button == "RightButton" and not buttonFrame.data.isAddButton then
			local menu = MenuUtil.CreateContextMenu(nil, function(owner, rootDescription)
				rootDescription:CreateButton("Remove", function()
					if buttonFrame.data.isCustom then
						SCM:RemoveCustomIcon(buttonFrame.data.id, isGlobal, buttonFrame.data.iconType)
					else
						SCM:RemoveSpellFromConfig(anchorIndex, buttonFrame.data)
					end
					horizontalScrollFrame:RemoveButton(buttonFrame.data)
					if buttonFrame.data.isCustom then
						ApplyAnchorGroupUpdate(anchorIndex, isGlobal)
						return
					end
					SCM:ApplyAllCDManagerConfigs()
				end)
			end)
		end
	end)

	horizontalScrollFrame:SetCallback("OnRelease", function()
		if lastButtonFrame then
			lastButtonFrame:SetBackdropBorderColor(BLACK_FONT_COLOR:GetRGBA())
		end
	end)

	horizontalScrollFrame:SetCallback("OnDragStop", function(self, event, collection)
		for i, entry in ipairs(collection) do
			if entry.isCustom and entry.id then
				local customConfig = SCM:GetConfigTableByID(entry.id, entry.iconType, isGlobal)
				if customConfig and customConfig.anchorGroup == anchorIndex then
					customConfig.order = i

					local customFrames = SCM.CustomIcons.GetCustomIconFrames(customConfig)
					if customFrames and customFrames[entry.id] then
						customFrames[entry.id].SCMOrder = i
					end
				end
			elseif entry.spellID and entry.spellID > 0 then
				local spellConfig = SCM.spellConfig[entry.spellID]
				if spellConfig and spellConfig.anchorGroup[anchorIndex] then
					spellConfig.anchorGroup[anchorIndex].order = i
				end
			end
		end
		SCM:ApplyAnchorGroupCDManagerConfig(anchorIndex, isGlobal)
	end)

	top:AddChild(horizontalScrollFrame)
	top:ResumeLayout()
	top:DoLayout()

	scrollFrame:DoLayout()
	scrollFrame:FixScroll()
	scrollFrame:SetScroll(0)

	RunNextFrame(function()
		horizontalScrollFrame.scrollbar:ScrollToEnd()
		horizontalScrollFrame.scrollbar:ScrollToBegin()
	end)
end

local function CreateAnchorTabGroup(parent, frame, isGlobal)
	parent:ReleaseChildren()

	local anchorTabs = AceGUI:Create("TabGroup")
	anchorTabs:SetLayout("fill")
	anchorTabs:SetFullWidth(true)
	anchorTabs:SetFullHeight(true)
	anchorTabs.frame:SetPoint("TOPLEFT", parent.frame, "TOPLEFT", 0, -30)
	anchorTabs.frame:SetPoint("BOTTOMRIGHT", parent.frame, "BOTTOMRIGHT", 0, -5)
	anchorTabs.frame:SetParent(parent.frame)
	anchorTabs.frame:Show()

	local sourceConfig = isGlobal and SCM.db.global.globalAnchorConfig or SCM.anchorConfig
	local anchorTabsTbl = {}
	for i in ipairs(sourceConfig) do
		tinsert(anchorTabsTbl, { value = i, text = "Anchor " .. i })
	end

	anchorTabs:SetTabs(anchorTabsTbl)
	anchorTabs:SetCallback("OnGroupSelected", function(self, event, anchorIndex)
		SelectAnchor(self, frame, anchorIndex, anchorTabsTbl, isGlobal)
	end)
	anchorTabs:SelectTab(1)
	--Not sure yet why I have to call this twice
	SelectAnchor(anchorTabs, frame, 1, anchorTabsTbl, isGlobal)
	parent:AddChild(anchorTabs)
end

local function CDM(self, frame, group)
	local modeTabs = AceGUI:Create("TabGroup")
	modeTabs:SetLayout("fill")
	modeTabs:SetFullWidth(true)
	modeTabs:SetFullHeight(true)

	local tabs = {
		{ value = "spec", text = "Spec Anchors" },
	}

	if SCM.db.global.options.enableCustomIcons then
		tinsert(tabs, { value = "global", text = "Global Anchors" })
	end

	modeTabs:SetTabs(tabs)
	modeTabs:SetCallback("OnGroupSelected", function(widget, event, mode)
		CreateAnchorTabGroup(widget, frame, mode == "global")
	end)
	modeTabs:SelectTab("spec")
	self:AddChild(modeTabs)

	self.typeTab = modeTabs
end

SCM.MainTabs.CDM.callback = CDM
