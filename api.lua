local SCM = select(2, ...)
SCMAPI = {}

function SCMAPI.AddTab(tab)
	SCM:AddTab(tab)
end

function SCMAPI.RegisterClassConfig(classFileName, config)
	if classFileName and config then
		SCM.DB:RegisterClassConfig(classFileName, config)
	end
end

function SCMAPI.ImportProfile(profileName, importString)
	SCM:ImportProfile(profileName, importString)
end

function SCMAPI.RegisterAndLoadConfig(profileName, classFileName, config, specID)
	SCM.DB:RegisterAndLoadConfig(profileName, classFileName, config, specID)
end

function SCMAPI.RegisterCustomSkin(skinFunction)
	tinsert(SCM.Skins, skinFunction)
end

function SCMAPI.ReloadSkins()
	SCM:ApplyAllCDManagerConfigs()
end

function SCMAPI.RegisterCustomAnchor(frame, options, override)
	if frame and (not SCM.CustomAnchors[frame] or override) then
		SCM.CustomAnchors[frame] = options
	end
end

function SCMAPI.RegisterCustomEntry(customEntry)
	tinsert(SCM.CustomEntries, customEntry)
end
