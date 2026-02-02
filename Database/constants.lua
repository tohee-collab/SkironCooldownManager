local SCM = select(2, ...)
SCM.Constants = {}

BACKDROP_SCM_PIXEL = {
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 2,
}

SCM.CooldownViewerNameToIndex = {
	["EssentialCooldownViewer"] = Enum.CooldownViewerCategory.Essential,
	--["UtilityCooldownViewer"] = Enum.CooldownViewerCategory.Utility,
	["UtilityCooldownViewer"] = Enum.CooldownViewerCategory.Essential,
	["BuffIconCooldownViewer"] = Enum.CooldownViewerCategory.TrackedBuff,
	["BuffBarCooldownViewer"] = Enum.CooldownViewerCategory.TrackedBar,
}

SCM.Constants.AnchorPoints = {
	TOPLEFT = "TOPLEFT",
	TOP = "TOP",
	TOPRIGHT = "TOPRIGHT",
	LEFT = "LEFT",
	CENTER = "CENTER",
	RIGHT = "RIGHT",
	BOTTOMLEFT = "BOTTOMLEFT",
	BOTTOM = "BOTTOM",
	BOTTOMRIGHT = "BOTTOMRIGHT",
}

SCM.Constants.GrowthDirections = {
	CENTERED = "Centered Horizontal",
	LEFT = "Left",
	RIGHT = "Right",
}

SCM.Constants.SourcePairs = {
	[0] = 1,
	[1] = 0,
	[2] = 2,
	[3] = 2,
}

SCM.Constants.SpecIDs = {
	-- DK
	250,
	251,
	252,
	-- DH
	577,
	581,
	1480,
	-- Druid
	102,
	103,
	104,
	105,
	-- Evoker
	1467,
	1468,
	1473,
	-- Hunter
	253,
	254,
	255,
	-- Mage
	62,
	63,
	64,
	-- Monk
	268,
	269,
	270,
	-- Paladin
	65,
	66,
	70,
	-- Priest
	256,
	257,
	258,
	-- Rogue
	259,
	260,
	261,
	-- Shaman
	262,
	263,
	264,
	-- Warlock
	265,
	266,
	267,
	-- Warrior
	71,
	72,
	73,
}

SCM.Constants.SecondaryPower = {
	["DEATHKNIGHT"] = Enum.PowerType.Runes,
	["DEMONHUNTER"] = {
		[581] = "SOUL_FRAGMENTS_VENGEANCE",
		[1480] = "SOUL_FRAGMENTS",
	},
	["DRUID"] = {
		[DRUID_CAT_FORM] = Enum.PowerType.ComboPoints,
	},
	["EVOKER"] = Enum.PowerType.Essence,
	["HUNTER"] = {
		[255] = "TIP_OF_THE_SPEAR",
	},
	["MAGE"] = {
		[62] = Enum.PowerType.ArcaneCharges,
	},
	["MONK"] = {
		[269] = Enum.PowerType.Chi,
	},
	["PALADIN"] = Enum.PowerType.HolyPower,
	["ROGUE"] = Enum.PowerType.ComboPoints,
	["SHAMAN"] = {
		[262] = Enum.PowerType.Mana,
		[263] = Enum.PowerType.Maelstrom,
	},
	["WARLOCK"] = Enum.PowerType.SoulShards,
}
