-- Whether the game would build a construction's rebuild, asked before it is sent; shared by the game script and the building
-- window (each loads it with ug_require under pcall). The game refuses a proposal whose data carries error messages, for
-- example "Collision" when the building's street stub no longer fits what was built around it (docs/design/findings.md); the
-- base windows treat a proposal with no messages as buildable (gui/entity_window/bridge_and_tunnel.tl).

local rebuildCheck : DepotRetrofitsRebuildCheck = {}

local check = function(construction : Engine.Entity, params : {string : any}) : Proposal, boolean, string
	local proposal = api.engine.util.proposal.createProposalReplaceConstruction(construction, params)
	if proposal == nil then return nil, nil, "noProposal" end
	local data = api.engine.util.proposal.makeProposalData(proposal)
	if data == nil or data.errorState == nil then return proposal, nil, "noProposalData" end
	local messages = data.errorState.messages or {}
	if #messages == 0 then return proposal, true, "clear" end
	local entities : {string} = {}
	local info = data.collisionInfo
	if info ~= nil and info.collisionEntities ~= nil then
		for _, colliding in ipairs(info.collisionEntities) do entities[#entities + 1] = tostring(colliding.entity) end
	end
	return proposal, false, "messages=" .. table.concat(messages, ";") .. " collisionEntities=" .. table.concat(entities, ",")
end

function rebuildCheck.check(construction : Engine.Entity, params : {string : any}) : Proposal, boolean, string
	local ok, proposal, clear, reason = pcall(check, construction, params)
	if not ok then return nil, nil, "checkError error=" .. tostring(proposal) end
	return proposal, clear, reason
end

return rebuildCheck
