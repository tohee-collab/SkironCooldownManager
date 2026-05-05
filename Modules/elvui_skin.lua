local SCM = select(2, ...)

local function GetSkinsModule()
	if not ElvUI or not ElvUI[1] then return end

	return ElvUI[1]:GetModule('Skins', true)
end

local function HandleTabs(skins, tabGroup)
	if not tabGroup or type(tabGroup.tabs) ~= 'table' then return end

	for _, tab in pairs(tabGroup.tabs) do
		if tab and not tab.SCMElvUISkinned then
			skins:HandleTab(tab)
			tab.SCMElvUISkinned = true
		end
	end
end

local function HookTabBuilder(skins, tabGroup)
	if not tabGroup or tabGroup.SCMElvUITabHooked then return end

	tabGroup.SCMElvUITabHooked = true
	hooksecurefunc(tabGroup, 'BuildTabs', function(self)
		HandleTabs(skins, self)
	end)
end

local function SkinRootFrame(skins, rootFrame)
	skins:HandleFrame(rootFrame, nil, true)

	if rootFrame.CloseButton then
		skins:HandleCloseButton(rootFrame.CloseButton)
	end

	if rootFrame.Inset then
		skins:HandleFrame(rootFrame.Inset)
	end

	if rootFrame.NineSlice then
		rootFrame.NineSlice:SetTemplate()
	end
end

function SCM:SkinOptionsFrame(frame, tabGroup)
	if not frame or not frame.frame then return end

	local rootFrame = frame.frame
	if rootFrame.SCMElvUISkinned then return end

	local skins = GetSkinsModule()
	if not skins then return end

	SkinRootFrame(skins, rootFrame)

	if tabGroup and tabGroup.border then
		skins:HandleFrame(tabGroup.border)
	end

	HandleTabs(skins, tabGroup)
	HookTabBuilder(skins, tabGroup)

	rootFrame.SCMElvUISkinned = true
end
