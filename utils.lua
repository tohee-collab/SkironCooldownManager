local _, SCM = ...

SCM.Utils = SCM.Utils or {}

local Utils = SCM.Utils
local GLOBAL_GROUP_OFFSET = 100

function Utils.ToGlobalGroup(index)
	return GLOBAL_GROUP_OFFSET + (index or 1)
end

function Utils.GetAnchorConfigForGroup(config, group, globalAnchorConfig)
	if config and config.anchorConfig and config.anchorConfig[group] then
		return config.anchorConfig[group]
	end

	if group < GLOBAL_GROUP_OFFSET then
		return
	end

	if not globalAnchorConfig then
		return
	end

	return globalAnchorConfig[group - GLOBAL_GROUP_OFFSET]
end

function Utils.SortBySCMOrder(a, b)
	return (a.SCMOrder or 0) < (b.SCMOrder or 0)
end

function Utils.GetOrCreateBucket(container, key)
	local bucket = container[key]
	if bucket then
		return bucket
	end

	bucket = {}
	container[key] = bucket
	return bucket
end

function Utils.AddChildToGroup(validChildren, group, child, isGlobal)
	if isGlobal then
		group = Utils.ToGlobalGroup(group)
		child.SCMGlobal = true
	end

	local groupChildren = Utils.GetOrCreateBucket(validChildren, group)
	groupChildren[#groupChildren + 1] = child
	return group
end

function Utils.NormalizeIconType(config)
	return config.iconType or (config.spellID and "spell") or "item"
end
