local SCM = select(2, ...)

SCM.Cache = {}
local Cache = SCM.Cache

Cache.cachedViewerScale = 1
Cache.cachedChildrenTbl = {}
Cache.cachedVisibleChildren = {}
Cache.cachedCooldownFrameTbl = {}
Cache.cachedViewerChildren = {}
Cache.cachedActiveItemFrames = {}
Cache.cachedVisitedAnchorGroups = {}
Cache.reusableCustomIconContext = {}
Cache.cachedScopedAnchorGroups = Cache.cachedScopedAnchorGroups or {
	essential = {},
	utility = {},
	buff = {},
}

function SCM:ClearChildrenCache()
	wipe(Cache.cachedChildrenTbl)
end

function SCM:ClearViewerChildrenCache()
	wipe(Cache.cachedViewerChildren)
end

function SCM:InvalidatePixelPerfectCache()
	Cache.cachedPixelPerfectMultiplier = nil
end

function SCM:GetPixelPerfectMultiplier()
	if not Cache.cachedPixelPerfectMultiplier then
		local screenHeight = select(2, GetPhysicalScreenSize())
		local scale = UIParent:GetEffectiveScale()
		if not screenHeight or screenHeight == 0 or not scale or scale == 0 then
			Cache.cachedPixelPerfectMultiplier = 1
		else
			Cache.cachedPixelPerfectMultiplier = (768 / screenHeight) / scale
		end
	end

	return Cache.cachedPixelPerfectMultiplier
end

function SCM:PixelPerfect(value)
	local pixelPerfectMultiplier = self:GetPixelPerfectMultiplier()
	if value ~= nil then
		return value * pixelPerfectMultiplier
	end

	return pixelPerfectMultiplier
end
