local addonName, SCM = ...
local AceGUI = LibStub("AceGUI-3.0")
local LibCustomGlow = LibStub("LibCustomGlow-1.0")
local LSM = LibStub("LibSharedMedia-3.0")

local colorKnown = "ffffff"
local colorUnknown = "808080"
local colorDisabled = "ff0000"

SCM.MainTabs.CDM = { value = "CDM", text = "Cooldown Manager", order = 2, subgroups = {} }

local iconTypeTabs = {
	all = {
		{ value = "general", text = "General" },
		{ value = "glow", text = "Glow" },
		{ value = "load", text = "Load Conditions" },
	},
	spell = {},
	item = {},
	timer = {},
	slot = {},
}
for iconType, options in pairs(iconTypeTabs) do
	if iconType ~= "all" then
		for i = #iconTypeTabs.all, 1, -1 do
			tinsert(options, 1, iconTypeTabs.all[i])
		end
	end
end

local customIconClassList
local function GetCustomIconClassList()
	if not customIconClassList then
		customIconClassList = {}
		for classIndex = 1, GetNumClasses() do
			local className, classFile = GetClassInfo(classIndex)
			if className and classFile then
				local classColor = GetClassColorObj(classFile)
				local classAtlas = GetClassAtlas(classFile)
				customIconClassList[classFile] = classAtlas and ("|A:%s:0:0|a %s"):format(classAtlas, classColor:WrapTextInColorCode(className)) or classColor:WrapTextInColorCode(className)
			end
		end
	end

	return customIconClassList
end

local function GetDefaultCustomIconLoadClasses()
	local loadClasses = {}
	for classFile in pairs(GetCustomIconClassList()) do
		loadClasses[classFile] = true
	end
	return loadClasses
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
			preferredIndex = 3,
			OnAccept = function(self)
				local id = tonumber(self.EditBox:GetText() or "")
				if id and id > 0 then
					callback(id)
				end
			end,
			hideOnEscape = true,
			EditBoxOnEnterPressed = function(self)
				if self:GetParent():GetButton1():IsEnabled() then
					self:GetParent():GetButton1():Click()
				end
			end,
		}
	StaticPopup_Show(key)
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
		texture = GetInventoryItemTexture("player", slotID) or 134400,
		spellID = 0,
		slotID = slotID,
	}
end

local customButtonConfigs = {
	{
		text = "Spell",
		popupKey = "SCM_CUSTOM_SPELL_ID",
		popupTitle = "Enter Spell ID",
		iconType = "spell",
		buildIconData = BuildSpellIconData,
	},
	{
		text = "Item",
		popupKey = "SCM_CUSTOM_ITEM_ID",
		popupTitle = "Enter Item ID",
		iconType = "item",
		buildIconData = BuildItemIconData,
	},
	{
		text = "Slot",
		popupKey = "SCM_SPEC_SLOT_ID",
		popupTitle = "Enter Slot ID",
		iconType = "slot",
		buildIconData = BuildSlotIconData,
	},
	{
		text = "Timer",
		popupKey = "SCM_TIMER_SPELL_ID",
		popupTitle = "Enter Spell ID",
		iconType = "timer",
		buildIconData = BuildSpellIconData,
		tooltip = function(tooltip, elementDescription)
			GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription))
			GameTooltip_AddInstructionLine(tooltip, "Timers can only be created based on successful casts.")
		end,
	},
}

local function CreateCustomIconButton(rootDescription, scrollFrame, anchorIndex, isGlobal, buttonConfig)
	local button = rootDescription:CreateButton(buttonConfig.text, function()
		ShowNumericInputPopup(buttonConfig.popupKey, buttonConfig.popupTitle, function(configID)
			local iconData = buttonConfig.buildIconData(configID)
			if not iconData then
				return
			end

			iconData.iconType = buttonConfig.iconType
			iconData.isCustom = true

			local uniqueID = SCM:AddCustomIcon(anchorIndex, buttonConfig.iconType, configID, nil, nil, isGlobal)
			if not uniqueID then
				return
			end

			iconData.id = uniqueID
			scrollFrame:AddCustomIcon(iconData)
			SCM:ApplyAnchorGroupCDManagerConfig(anchorIndex, isGlobal)
		end)
	end)

	if buttonConfig.tooltip then
		button:SetTooltip(buttonConfig.tooltip)
	end
end

local function CreateCustomIconButtons(rootDescription, scrollFrame, anchorIndex, isGlobal, buttonConfigs)
	for _, buttonConfig in ipairs(buttonConfigs) do
		CreateCustomIconButton(rootDescription, scrollFrame, anchorIndex, isGlobal, buttonConfig)
	end
end

local function GetSpellIDForCooldownInfo(cooldownInfo)
	if cooldownInfo then
		if cooldownInfo.linkedSpellIDs and #cooldownInfo.linkedSpellIDs == 1 then
			return cooldownInfo.linkedSpellIDs[1]
		end

		return cooldownInfo.spellID
	end
end

local function BuildScrollSpellData(data, configID)
	return {
		spellID = data.spellID,
		linkedSpellIDs = data.linkedSpellIDs,
		isKnown = data.isKnown,
		category = data.category,
		cooldownID = data.cooldownID,
		configID = configID,
	}
end

local function DoesScrollFrameContainSpellConfig(scrollFrame, configID, cooldownID)
	return scrollFrame.dataProvider:FindByPredicate(function(data)
		if data.isCustom or data.isAddButton then
			return false
		end

		if data.id == configID then
			return true
		end

		if cooldownID and data.cooldownID == cooldownID then
			return true
		end
	end)
end

local function GetDisplayDataForSpellConfig(defaultCooldownViewerConfig, sourceIndex, configID, config)
	local data = defaultCooldownViewerConfig[sourceIndex]
	if not data then
		return
	end

	local pairData = defaultCooldownViewerConfig[SCM.Constants.SourcePairs[sourceIndex]]
	local cooldownID = config.cooldownID or tonumber(tostring(configID):match("(%d+)$"))

	if cooldownID then
		return data.cooldownIDs[cooldownID] or (pairData and pairData.cooldownIDs[cooldownID])
	end
end

local function CreateAddSpellDropdown(owner, rootDescription, scrollFrame, anchorIndex, isGlobal)
	rootDescription:CreateTitle("Add Icon")

	if isGlobal then
		local customButton = rootDescription:CreateButton("Custom")
		CreateCustomIconButtons(customButton, scrollFrame, anchorIndex, true, customButtonConfigs)
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
			local configID = SCM:GetCooldownConfigKey(cooldownID)
			if configID then
				info.cooldownID = item.cooldownID
				info.configID = configID
				info.isDisabled = data.category < 0

				local activeColor = (data.category < 0 and colorDisabled) or (info.isKnown and colorKnown) or colorUnknown
				parentButton:CreateButton(string.format("|T%d:0|t |cff%s%s (%d)|r", C_Spell.GetSpellTexture(info.spellID), activeColor, C_Spell.GetSpellName(info.spellID), cooldownID), function(info)
					local dataIndex = scrollFrame:AddSpellBySpellID(info)
					SCM:AddSpellToConfig(anchorIndex, dataIndex, info, data, item.targetCategory, isBuffIcon)
					SCM:ApplyAllCDManagerConfigs()
					return MenuResponse.Open
				end, info)
			end
		end
	end

	local essentialItems = {}
	local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(0, true)
	for _, cooldownID in ipairs(cooldownIDs) do
		local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
		local data = cooldownInfoByID[cooldownID]

		if info and data then
			local spellID = GetSpellIDForCooldownInfo(info)
			local configID = SCM:GetCooldownConfigKey(cooldownID)
			info.spellID = spellID

			if configID and not SCM:IsSpellInData(cooldownID, data.category) and not DoesScrollFrameContainSpellConfig(scrollFrame, configID, cooldownID) then
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
			local spellID = GetSpellIDForCooldownInfo(info)
			local configID = SCM:GetCooldownConfigKey(cooldownID)
			info.spellID = spellID

			if configID and not SCM:IsSpellInData(cooldownID, data.category) and not DoesScrollFrameContainSpellConfig(scrollFrame, configID, cooldownID) then
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
			local spellID = GetSpellIDForCooldownInfo(info)
			local configID = SCM:GetCooldownConfigKey(cooldownID)
			info.spellID = spellID

			if configID and not SCM:IsSpellInData(cooldownID, data.category) and not DoesScrollFrameContainSpellConfig(scrollFrame, configID, cooldownID) then
				table.insert(buffItems, { info = info, data = data, cooldownID = cooldownID, targetCategory = 2 })
			end
		end
	end

	cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(3, true)
	for _, cooldownID in ipairs(cooldownIDs) do
		local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
		local data = cooldownInfoByID[cooldownID]

		if info and data and data.category < 3 then
			local spellID = GetSpellIDForCooldownInfo(info)
			local configID = SCM:GetCooldownConfigKey(cooldownID)
			info.spellID = spellID

			if configID and not SCM:IsSpellInData(cooldownID, data.category) and not DoesScrollFrameContainSpellConfig(scrollFrame, configID, cooldownID) then
				table.insert(buffItems, { info = info, data = data, cooldownID = cooldownID, targetCategory = 3 })
			end
		end
	end

	buffButton:SetGridMode(MenuConstants.VerticalGridDirection, floor(#buffItems / 15) + 1)

	ProcessAndCreateButtons(buffButton, buffItems, true)

	rootDescription:CreateDivider()

	local customButton = rootDescription:CreateButton("Custom")
	CreateCustomIconButtons(customButton, scrollFrame, anchorIndex, false, customButtonConfigs)

	for _, customEntry in pairs(SCM.CustomEntries) do
		customEntry(rootDescription, scrollFrame, anchorIndex)
	end
end

local function SelectAdvancedRowSettings(self, tabGroup, rowConfig, rowIndex, options)
	self:ReleaseChildren()

	if tabGroup == "general" then
		local keepAspectRatio = AceGUI:Create("CheckBox")
		keepAspectRatio:SetLabel("Lock Aspect Ratio")
		keepAspectRatio:SetRelativeWidth(0.5)
		keepAspectRatio:SetValue(rowConfig.keepAspectRatio)
		keepAspectRatio:SetCallback("OnValueChanged", function(_, _, value)
			rowConfig.keepAspectRatio = value
		end)
		self:AddChild(keepAspectRatio)

		local hardLimit = AceGUI:Create("CheckBox")
		hardLimit:SetLabel("Hard Limit")
		hardLimit:SetRelativeWidth(0.5)
		hardLimit:SetValue(rowConfig.hardLimit)
		hardLimit:SetCallback("OnValueChanged", function(_, _, value)
			rowConfig.hardLimit = value
			SCM:ApplyAllCDManagerConfigs()
		end)
		self:AddChild(hardLimit)

		if rowIndex == 1 then
			local fixedWidth
			local useFixedWidth = AceGUI:Create("CheckBox")
			useFixedWidth:SetLabel("Use Fixed Width")
			useFixedWidth:SetRelativeWidth(0.5)
			useFixedWidth:SetValue(rowConfig.useFixedWidth)
			useFixedWidth:SetCallback("OnValueChanged", function(_, _, value)
				rowConfig.useFixedWidth = value
				SCM:ApplyAllCDManagerConfigs()

				if fixedWidth then
					rowConfig.fixedWidth = rowConfig.fixedWidth or 200
					fixedWidth:SetDisabled(not value)
				end
			end)
			self:AddChild(useFixedWidth)

			fixedWidth = AceGUI:Create("Slider")
			fixedWidth:SetRelativeWidth(0.5)
			fixedWidth:SetSliderValues(100, 1000, 0.1)
			fixedWidth:SetLabel("Fixed Width")
			fixedWidth:SetValue(rowConfig.fixedWidth or 200)
			fixedWidth:SetDisabled(not rowConfig.useFixedWidth)
			fixedWidth:SetCallback("OnValueChanged", function(_, _, value)
				rowConfig.fixedWidth = value
				SCM:ApplyAllCDManagerConfigs()
			end)
			self:AddChild(fixedWidth)
		end
	elseif tabGroup == "charges" then
		local chargeRelativePoint = AceGUI:Create("Dropdown")
		chargeRelativePoint:SetRelativeWidth(0.5)
		chargeRelativePoint:SetLabel("Point")
		chargeRelativePoint:SetList(SCM.Constants.AnchorPoints)
		chargeRelativePoint:SetValue(rowConfig.chargePoint or options.chargePoint)
		chargeRelativePoint:SetCallback("OnValueChanged", function(_, _, value)
			rowConfig.chargePoint = value
			SCM:ApplyAllCDManagerConfigs()
		end)
		self:AddChild(chargeRelativePoint)

		local chargeRelativePoint = AceGUI:Create("Dropdown")
		chargeRelativePoint:SetRelativeWidth(0.5)
		chargeRelativePoint:SetLabel("Relative Point")
		chargeRelativePoint:SetList(SCM.Constants.AnchorPoints)
		chargeRelativePoint:SetValue(rowConfig.chargeRelativePoint or options.chargeRelativePoint)
		chargeRelativePoint:SetCallback("OnValueChanged", function(_, _, value)
			rowConfig.chargeRelativePoint = value
			SCM:ApplyAllCDManagerConfigs()
		end)
		self:AddChild(chargeRelativePoint)

		local xOffset = AceGUI:Create("Slider")
		xOffset:SetRelativeWidth(0.33)
		xOffset:SetSliderValues(-50, 50, 0.1)
		xOffset:SetLabel("X Offset")
		xOffset:SetValue(rowConfig.chargeXOffset or options.chargeXOffset)
		xOffset:SetCallback("OnValueChanged", function(self, event, value)
			rowConfig.chargeXOffset = value
			SCM:ApplyAllCDManagerConfigs()
		end)
		self:AddChild(xOffset)

		local yOffset = AceGUI:Create("Slider")
		yOffset:SetRelativeWidth(0.33)
		yOffset:SetSliderValues(-50, 50, 0.1)
		yOffset:SetLabel("Y Offset")
		yOffset:SetValue(rowConfig.chargeYOffset or options.chargeYOffset)
		yOffset:SetCallback("OnValueChanged", function(self, event, value)
			rowConfig.chargeYOffset = value
			SCM:ApplyAllCDManagerConfigs()
		end)
		self:AddChild(yOffset)

		local chargeFontSize = AceGUI:Create("Slider")
		chargeFontSize:SetRelativeWidth(0.33)
		chargeFontSize:SetLabel("Font Size")
		chargeFontSize:SetSliderValues(1, 50, 1)
		chargeFontSize:SetValue(rowConfig.chargeFontSize or options.chargeFontSize)
		chargeFontSize:SetCallback("OnValueChanged", function(self, event, value)
			rowConfig.chargeFontSize = value
			SCM:ApplyAllCDManagerConfigs()
		end)
		self:AddChild(chargeFontSize)
	end

	self:DoLayout()
end

local function SelectRow(self, data, anchorIndex, rowIndex, rowTabsTbl, isGlobal, options)
	self:ReleaseChildren()

	if not data.rowConfig[rowIndex] then
		return
	end

	local rowConfig = data.rowConfig[rowIndex]
	local iconWidth = AceGUI:Create("Slider")
	iconWidth:SetRelativeWidth(0.33)
	iconWidth:SetSliderValues(10, 200, 0.1)
	iconWidth:SetLabel("Icon Width")
	iconWidth:SetValue(rowConfig.iconWidth or rowConfig.size)

	self:AddChild(iconWidth)

	local iconHeight = AceGUI:Create("Slider")
	iconHeight:SetRelativeWidth(0.33)
	iconHeight:SetSliderValues(10, 200, 0.1)
	iconHeight:SetLabel("Icon Height")
	iconHeight:SetValue(rowConfig.iconHeight or rowConfig.size)
	iconHeight:SetCallback("OnValueChanged", function(self, event, value)
		if rowConfig.keepAspectRatio then
			local newWidth
			if (rowConfig.iconHeight or rowConfig.size) == (rowConfig.iconWidth or rowConfig.size) then
				newWidth = value
			else
				local ratio = (rowConfig.iconWidth or rowConfig.size) / (rowConfig.iconHeight or rowConfig.size)
				newWidth = ceil((ratio * value) * 10) / 10
			end

			rowConfig.iconWidth = newWidth
			iconWidth:SetValue(rowConfig.iconWidth)
		end

		rowConfig.iconHeight = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	iconWidth:SetCallback("OnValueChanged", function(self, event, value)
		if rowConfig.keepAspectRatio then
			local newHeight
			if (rowConfig.iconHeight or rowConfig.size) == (rowConfig.iconWidth or rowConfig.size) then
				newHeight = value
			else
				local ratio = (rowConfig.iconHeight or rowConfig.size) / (rowConfig.iconWidth or rowConfig.size)
				newHeight = ceil((ratio * value) * 10) / 10
			end

			rowConfig.iconHeight = newHeight
			iconHeight:SetValue(rowConfig.iconHeight)
		end
		rowConfig.iconWidth = value

		SCM:ApplyAllCDManagerConfigs()
	end)
	self:AddChild(iconHeight)

	local limit = AceGUI:Create("Slider")
	limit:SetRelativeWidth(0.33)
	limit:SetSliderValues(1, 20, 1)
	limit:SetLabel("Limit")
	limit:SetValue(rowConfig.limit)
	limit:SetCallback("OnValueChanged", function(self, event, value)
		rowConfig.limit = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	self:AddChild(limit)

	local advancedRowSettings = AceGUI:Create("TabGroup")
	advancedRowSettings:SetLayout("flow")
	advancedRowSettings:SetFullWidth(true)
	advancedRowSettings:SetTabs({ { value = "general", text = "General" }, { value = "charges", text = "Charges/Stacks" } })
	advancedRowSettings:SetCallback("OnGroupSelected", function(self, event, tabGroup)
		SelectAdvancedRowSettings(self, tabGroup, rowConfig, rowIndex, options)
	end)
	advancedRowSettings:SelectTab("general")
	self:AddChild(advancedRowSettings)

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
	self:DoLayout()
end

local function SelectAnchor(anchorWidget, frame, anchorIndex, anchorTabsTbl, isGlobal)
	anchorWidget:ReleaseChildren()

	SCM.activeAnchorSettings = anchorIndex
	local options = SCM.db.profile.options

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
		local nextIndex = isGlobal and SCM:AddGlobalAnchor(anchorTabsTbl) or SCM:AddAnchor(anchorTabsTbl)
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
	point:SetRelativeWidth(0.33)
	point:SetLabel("Point")
	point:SetList(SCM.Constants.AnchorPoints)
	point:SetValue(data.anchor[1])
	point:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[1] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(point)

	local relativeTo = AceGUI:Create("EditBox")
	relativeTo:SetRelativeWidth(0.33)
	relativeTo:SetLabel("Anchor Frame")
	relativeTo:SetText(data.anchor[2])
	relativeTo:SetCallback("OnEnterPressed", function(self, event, text)
		data.anchor[2] = text
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(relativeTo)

	local relativePoint = AceGUI:Create("Dropdown")
	relativePoint:SetRelativeWidth(0.33)
	relativePoint:SetLabel("Relative Point")
	relativePoint:SetList(SCM.Constants.AnchorPoints)
	relativePoint:SetValue(data.anchor[3])
	relativePoint:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[3] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(relativePoint)

	local grow = AceGUI:Create("Dropdown")
	grow:SetRelativeWidth(0.5)
	grow:SetList(SCM.Constants.GrowthDirections)
	grow:SetLabel("Growth Direction")
	grow:SetValue(data.grow or "CENTERED")
	grow:SetCallback("OnValueChanged", function(self, event, value)
		data.grow = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(grow)

	local spacing = AceGUI:Create("Slider")
	spacing:SetRelativeWidth(0.5)
	spacing:SetSliderValues(-10, 50, 0.1)
	spacing:SetLabel("Horizontal Spacing")
	spacing:SetValue(data.spacing or 0)
	spacing:SetCallback("OnValueChanged", function(self, event, value)
		data.spacing = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(spacing)

	local xOffset = AceGUI:Create("Slider")
	xOffset:SetRelativeWidth(0.5)
	xOffset:SetSliderValues(-1000, 1000, 0.1)
	xOffset:SetLabel("X Offset")
	xOffset:SetValue(data.anchor[4])
	xOffset:SetCallback("OnValueChanged", function(self, event, value)
		data.anchor[4] = value
		SCM:ApplyAllCDManagerConfigs()
	end)
	anchorOptions:AddChild(xOffset)

	local yOffset = AceGUI:Create("Slider")
	yOffset:SetRelativeWidth(0.5)
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
		SelectRow(self, data, anchorIndex, rowIndex, rowTabsTbl, isGlobal, options)
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
		for configID, info in pairs(SCM.spellConfig) do
			if info.anchorGroup[anchorIndex] then
				for sourceIndex, spellAnchorIndex in pairs(info.source) do
					if anchorIndex == spellAnchorIndex then
						local data = GetDisplayDataForSpellConfig(defaultCooldownViewerConfig, sourceIndex, configID, info)
						if data then
							tinsert(spells, { configID = configID, info = info, data = data, isBuffIcon = sourceIndex >= 2 })
							break
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
				if iconType == "spell" or iconType == "timer" then
					texture = config.spellID and C_Spell.GetSpellTexture(config.spellID)
				elseif iconType == "slot" then
					texture = config.slotID and GetInventoryItemTexture("player", config.slotID) or 134400
				elseif iconType == "item" then
					texture = config.itemID and C_Item.GetItemIconByID(config.itemID)
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
			horizontalScrollFrame:AddSpellBySpellID(BuildScrollSpellData(spellInfo.data, spellInfo.configID), spellInfo.info.anchorGroup[anchorIndex].order, spellInfo.isBuffIcon)
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
					local buttonConfig = buttonData.isCustom and SCM:GetConfigTableByID(buttonData.id, buttonData.iconType, isGlobal) or SCM:GetSpellConfigForGroup(buttonData.id, anchorIndex)

					buttonFrame:SetBackdropBorderColor(0, 1, 0, 1)

					if buttonConfig then
						local function ApplyIconConfigUpdate()
							if buttonFrame.data.isCustom then
								SCM.CustomIcons.CreateIcons(SCM:GetConfigTable(buttonData.iconType, isGlobal), isGlobal)
								SCM:ApplyAnchorGroupCDManagerConfig(anchorIndex, isGlobal)
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

								local desaturate
								if buttonFrame.data.isBuffIcon or buttonData.isCustom then
									local alwaysShow = AceGUI:Create("CheckBox")
									alwaysShow:SetLabel("Show Always")
									alwaysShow:SetRelativeWidth(0.5)
									alwaysShow:SetValue(buttonConfig.alwaysShow)
									alwaysShow:SetDisabled(not options.hideBuffsWhenInactive)
									SCM.Utils.SetDisabledTooltip(alwaysShow, "Enable 'Hide Inactive Auras' in Global Settings > General > Auras first.")
									iconSettingsTabs:AddChild(alwaysShow)
									alwaysShow:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.alwaysShow = value or nil
										ApplyIconConfigUpdate()

										if desaturate then
											desaturate:SetDisabled(not value)
										end
									end)
								end

								if buttonFrame.data.isBuffIcon then
									local hideWhileMounted = AceGUI:Create("CheckBox")
									hideWhileMounted:SetRelativeWidth(0.5)
									hideWhileMounted:SetValue(buttonConfig.hideWhileMounted)
									hideWhileMounted:SetLabel("Hilde While Mounted")
									hideWhileMounted:SetDisabled(not options.hideWhileMounted)
									hideWhileMounted:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.hideWhileMounted = value or nil
										ApplyIconConfigUpdate()
									end)
									iconSettingsTabs:AddChild(hideWhileMounted)

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
								elseif buttonData.iconType ~= "timer" then
									local hideWhileReady = AceGUI:Create("CheckBox")
									hideWhileReady:SetLabel("Hide While Ready")
									hideWhileReady:SetRelativeWidth(0.5)
									hideWhileReady:SetValue(buttonConfig.hideWhenNotOnCooldown)
									hideWhileReady:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.hideWhenNotOnCooldown = value or nil
										ApplyIconConfigUpdate()
									end)
									iconSettingsTabs:AddChild(hideWhileReady)

									if buttonData.isCustom then
										local showGCD = AceGUI:Create("CheckBox")
										showGCD:SetLabel("Show GCD")
										showGCD:SetRelativeWidth(0.5)
										showGCD:SetValue(buttonConfig.showGCD)
										showGCD:SetCallback("OnValueChanged", function(self, event, value)
											buttonConfig.showGCD = value or nil
											ApplyIconConfigUpdate()
										end)
										iconSettingsTabs:AddChild(showGCD)
										if buttonData.iconType == "item" then
											local showCraftQuality = AceGUI:Create("CheckBox")
											showCraftQuality:SetLabel("Show Craft Quality")
											showCraftQuality:SetRelativeWidth(0.5)
											showCraftQuality:SetValue(buttonConfig.showCraftQuality)
											showCraftQuality:SetCallback("OnValueChanged", function(self, event, value)
												buttonConfig.showCraftQuality = value or nil
												ApplyIconConfigUpdate()
											end)
											iconSettingsTabs:AddChild(showCraftQuality)
										end
									else
										local forceActiveSwipe = AceGUI:Create("CheckBox")
										forceActiveSwipe:SetLabel("Force Active Swipe")
										forceActiveSwipe:SetRelativeWidth(0.5)
										forceActiveSwipe:SetValue(buttonConfig.forceActiveSwipe)
										forceActiveSwipe:SetCallback("OnValueChanged", function(self, event, value)
											buttonConfig.forceActiveSwipe = value or nil
											ApplyIconConfigUpdate()
										end)
										iconSettingsTabs:AddChild(forceActiveSwipe)
									end
								end

								if buttonData.isCustom and (buttonData.iconType == "spell" or buttonData.iconType == "timer") then
									local castTimer = AceGUI:Create("Slider")
									castTimer:SetRelativeWidth(0.5)
									castTimer:SetSliderValues(0, 30, 0.1)
									castTimer:SetLabel("Timer Duration")
									castTimer:SetValue(buttonConfig.duration or 0)
									castTimer:SetCallback("OnValueChanged", function(_, _, value)
										buttonConfig.duration = value > 0 and value or nil
										ApplyIconConfigUpdate()
									end)

									iconSettingsTabs:AddChild(castTimer)
								end
							elseif group == "load" then
								if buttonData.isCustom then
									if isGlobal then
										local loadClass = AceGUI:Create("Dropdown")
										loadClass:SetRelativeWidth(0.5)
										loadClass:SetLabel("Classes")
										loadClass:SetList(GetCustomIconClassList())
										loadClass:SetMultiselect(true)
										loadClass:SetCallback("OnValueChanged", function(_, _, key, value)
											buttonConfig.loadClasses = buttonConfig.loadClasses or GetDefaultCustomIconLoadClasses()
											buttonConfig.loadClasses[key] = value
											ApplyIconConfigUpdate()
										end)

										if not buttonConfig.loadClasses then
											buttonConfig.loadClasses = GetDefaultCustomIconLoadClasses()
										end

										for key, value in pairs(buttonConfig.loadClasses) do
											loadClass:SetItemValue(key, value)
										end

										iconSettingsTabs:AddChild(loadClass)

										local loadRole = AceGUI:Create("Dropdown")
										loadRole:SetRelativeWidth(0.5)
										loadRole:SetLabel("Roles")
										loadRole:SetList(SCM.Constants.Roles)
										loadRole:SetMultiselect(true)
										loadRole:SetCallback("OnValueChanged", function(_, _, key, value)
											buttonConfig.loadRoles = buttonConfig.loadRoles or {}
											buttonConfig.loadRoles[key] = value
											ApplyIconConfigUpdate()
										end)

										if not buttonConfig.loadRoles then
											buttonConfig.loadRoles = { ["TANK"] = true, ["HEALER"] = true, ["DAMAGER"] = true }
										end

										for key, value in pairs(buttonConfig.loadRoles) do
											loadRole:SetItemValue(key, value)
										end

										iconSettingsTabs:AddChild(loadRole)
										return
									end
								end

								local label = AceGUI:Create("Label")
								label:SetRelativeWidth(1.0)
								label:SetHeight(24)
								label:SetJustifyH("CENTER")
								label:SetJustifyV("MIDDLE")
								label:SetText("|TInterface\\common\\help-i:40:40:0:0|tLoad conditions are only available for global custom icons (for now).")
								label:SetFontObject("Game12Font")
								iconSettingsTabs:AddChild(label)
							elseif group == "glow" then
								if not buttonData.isCustom and buttonData.iconType == "spell" then
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

								if buttonData.iconType == "spell" or buttonData.iconType == "timer" then
									local glowWhileActive = AceGUI:Create("CheckBox")
									glowWhileActive:SetLabel("Glow While Active")
									glowWhileActive:SetRelativeWidth(0.5)
									glowWhileActive:SetValue(buttonConfig.glowWhileActive)
									glowWhileActive:SetDisabled(not options.useCustomGlow)
									SCM.Utils.SetDisabledTooltip(glowWhileActive, "Enable 'Use Custom Glow' in Global Settings > Glow first.")
									glowWhileActive:SetCallback("OnValueChanged", function(self, event, value)
										buttonConfig.glowWhileActive = value or nil
										ApplyIconConfigUpdate()
									end)
									iconSettingsTabs:AddChild(glowWhileActive)
								end
							end

							iconSettings:DoLayout()
							scrollFrame:DoLayout()
						end)
						iconSettingsTabs:SelectTab("general")
						iconSettings:AddChild(iconSettingsTabs)
						lastButtonFrame = buttonFrame

						iconSettings:DoLayout()
						scrollFrame:DoLayout()
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

					iconSettings:DoLayout()
					scrollFrame:DoLayout()
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
						SCM:ApplyAnchorGroupCDManagerConfig(anchorIndex, isGlobal)
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
				local spellConfig = entry.id and SCM.spellConfig[entry.id]
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
		{ value = "global", text = "Global Anchors" },
	}

	modeTabs:SetTabs(tabs)
	modeTabs:SetCallback("OnGroupSelected", function(widget, event, mode)
		CreateAnchorTabGroup(widget, frame, mode == "global")
	end)
	modeTabs:SelectTab("spec")
	self:AddChild(modeTabs)

	self.typeTab = modeTabs
end

SCM.MainTabs.CDM.callback = CDM
