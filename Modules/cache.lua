local SCM = select(2, ...)

local Cache = SCM.Cache

Cache.cachedViewerScale = 1
Cache.cachedChildrenTbl = {}
Cache.cachedVisibleChildren = {}
Cache.cachedCooldownFrameTbl = {}
Cache.cachedViewerChildren = {}
Cache.cachedActiveItemFrames = {}
Cache.cachedVisitedAnchorGroups = {}
Cache.cachedAnchorStates = {}
Cache.cachedAnchorChildren = {}
Cache.cachedAnchorLinks = {}
Cache.cachedAnchorLinksDirty = true
Cache.cachedAnchorQueue = {}
Cache.cachedAnchorOffsetVisited = {}
Cache.reusableCustomIconContext = {}
Cache.reusableScopedGroupTables = {}
Cache.cachedScopedAnchorGroups = {
	essential = {},
	utility = {},
	buff = {},
	buffBar = {},
}

function SCM:ClearChildrenCache()
	wipe(Cache.cachedChildrenTbl)
end

function SCM:ClearViewerChildrenCache()
	wipe(Cache.cachedViewerChildren)
end

function SCM:InvalidateViewerChildrenCache(viewer)
	if viewer then
		Cache.cachedViewerChildren[viewer] = nil
		return
	end

	self:ClearViewerChildrenCache()
end

function SCM:InvalidatePixelPerfectCache()
	Cache.cachedPixelPerfectMultiplier = nil
end

function SCM:InvalidateAnchorLinks()
	Cache.cachedAnchorLinksDirty = true
end

function SCM:AcquireScopedGroupCache()
	local reusableScopedGroupTables = Cache.reusableScopedGroupTables
	local scopedGroups = reusableScopedGroupTables[#reusableScopedGroupTables]
	if scopedGroups then
		reusableScopedGroupTables[#reusableScopedGroupTables] = nil
		return scopedGroups
	end

	return {}
end

function SCM:ReleaseScopedGroupCache(scopedGroups)
	if not scopedGroups then
		return
	end

	wipe(scopedGroups)
	local reusableScopedGroupTables = Cache.reusableScopedGroupTables
	reusableScopedGroupTables[#reusableScopedGroupTables + 1] = scopedGroups
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
