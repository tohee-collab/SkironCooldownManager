local SCM = select(2, ...)
local LibCustomGlow = LibStub("LibCustomGlow-1.0")

local activeGlows = {}

function SCM:StartCustomGlow(child)
	local options = self.db.global.options

	if child.SCMGlow and (options.glowType ~= child.SCMGlow or (self.OptionsFrame and self.OptionsFrame:IsVisible()))then
		self:StopCustomGlow(child)
	end

	local childConfig = child.SCMConfig
	local glowTypeOptions = options.glowTypeOptions[options.glowType]
	local color = childConfig.useCustomGlowColor and childConfig.customGlowColor or glowTypeOptions.glowColor
	child.SCMGlow = options.glowType

	if options.glowType == "Proc" then
		LibCustomGlow.ProcGlow_Start(child, { key = "SCM", frameLevel = 1, color = color, startAnim = glowTypeOptions.startAnim, xOffset = glowTypeOptions.xOffset, yOffset = glowTypeOptions.yOffset })
	elseif options.glowType == "Autocast" then
        -- color,N,frequency,scale,xOffset,yOffset,key,frameLevel
		LibCustomGlow.AutoCastGlow_Start(child, color, glowTypeOptions.numParticles, glowTypeOptions.frequency, glowTypeOptions.scale, glowTypeOptions.xOffset, glowTypeOptions.yOffset, "SCM", 1)
	elseif options.glowType == "Pixel" then
        -- N,frequency,length,th,xOffset,yOffset,border
		LibCustomGlow.PixelGlow_Start(child, color, glowTypeOptions.numLines, glowTypeOptions.frequency, glowTypeOptions.length, glowTypeOptions.thickness, glowTypeOptions.xOffset, glowTypeOptions.yOffset, glowTypeOptions.border, "SCM", 1)
	end

	activeGlows[child] = true
end

function SCM:StopCustomGlow(child)
	if child.SCMGlow == "Proc" then
		LibCustomGlow.ProcGlow_Stop(child, "SCM")
	elseif child.SCMGlow == "Autocast" then
		LibCustomGlow.AutoCastGlow_Stop(child, "SCM")
	elseif child.SCMGlow == "Pixel" then
		LibCustomGlow.PixelGlow_Stop(child, "SCM")
	end

	child.SCMGlow = nil
	activeGlows[child] = nil
end

function SCM:StopAllGlows()
	for child in pairs(activeGlows) do
		self:StopCustomGlow(child)
	end
end

function SCM:RefreshAllGlows()
	for child in pairs(activeGlows) do
		self:StartCustomGlow(child)
	end
end
