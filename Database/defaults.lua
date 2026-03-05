local SCM = select(2, ...)

SCM.Defaults = {}

SCM.DefaultDB = {
    global = {
		globalAnchorConfig = {
			[1] = {
				anchor = { "CENTER", "UIParent", "CENTER", 0, -360 },
				rowConfig = {
					[1] = {
						size = 40,
						limit = 8,
					},
				},
			},
		},
		globalSpellConfig = {},
		globalItemConfig = {},
		globalSlotConfig = {},
		options = {
			anchorUUFRoles = {
				["HEALER"] = false,
				["DAMAGER"] = true,
				["TANK"] = true,
			},
			anchorElvUIRoles = {
				["HEALER"] = false,
				["DAMAGER"] = true,
				["TANK"] = true,
			},
			showAnchorHighlight = true,
			debug = false,
            enableSkinning = true,
			enableCustomIcons = true,
			simulateAuras = true,
			chargeFont = "Expressway",
			chargeFontSize = 22,
			chargeRelativePoint = "BOTTOMRIGHT",
			chargeXOffset = -8,
			chargeYOffset = 10,
            useCustomGlow = false,
            glowType = "Proc",
            borderSize = 1,
            anchorUUF = true,
            anchorElvUI = true,
            borderColor = {r = 0, g = 0, b = 0, a = 1},
            adjustResourceWidth = true,
            resourceBars = {
				"PrimaryResourceBar",
				"SecondaryResourceBar"
			},
			pandemicGlowOption = "keepPandemicGlow",
			recolorActiveSwipe = false,
			activeSwipeColor = {0, 0, 0, 0.8},
			castbarXOffset = 0,
			castbarYOffset = 25,
			glowTypeOptions = {
				["Proc"] = {
					glowColor = {0.95, 0.95, 0.32, 1},
				},
				["Pixel"] = {
					numLines = 8,
					frequency = 0.25,
					length = 2,
					thickness = 2,
					glowColor = {0.95, 0.95, 0.32, 1},
				},
				["Autocast"] = {
					startAnim = true,
					numParticles = 4,
					frequency = 0.125,
					scale = 1,
					glowColor = {0.95, 0.95, 0.32, 1},
				},
			},
			testSetting = {
				[193063] = true
			}
        }
    }
}

SCM.DB = {
	classes = {},

	defaultAnchorConfig = {
		[1] = {
			anchor = { "CENTER", "UIParent", "CENTER", 0, -285 },
			rowConfig = {
				[1] = {
					size = 47,
					limit = 8,
				},
			},
		},
		[2] = {
			anchor = { "TOP", "ANCHOR:1", "BOTTOM", 0, 1 },
			rowConfig = {
				[1] = {
					size = 41,
					limit = 8,
				},
			},
		},
		[3] = {
			anchor = { "TOP", "ANCHOR:2", "BOTTOM", 0, 1 },
			rowConfig = {
				[1] = {
					size = 40,
					limit = 8,
				},
			},
		},
	},
}

SCM.DefaultClassConfig = {
	spellConfig = {},
	anchorConfig = {},
	itemConfig = {},
	customConfig = {},
}

SCM.Defaults.GlobalSettingsTabs = {
	{ value = "General", text = "General"},
	{ value = "Glow", text = "Glow"},
}
