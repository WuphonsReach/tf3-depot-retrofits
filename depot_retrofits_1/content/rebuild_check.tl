-- Whether the game would build a construction's rebuild, asked before it is sent; shared by the game script and the building
-- window (each loads it with ug_require under pcall). The game refuses a proposal whose data carries error messages, for
-- example "Collision" when the building's street stub no longer fits what was built around it (docs/design/findings.md); the
-- base windows treat a proposal with no messages as buildable (gui/entity_window/bridge_and_tunnel.tl).
--
-- makeProposalData takes a SimpleProposal, not the Proposal that createProposalReplaceConstruction returns (the type
-- definition says Proposal; the game raises "SimpleProposal expected, got Proposal"). So the check asks about the same rebuild
-- as a SimpleProposal, written the way the base landmarks replace theirs (landmarks/landmarks.script.tl): remove the
-- construction and add it back with the new params, mapped old to new. The rebuild that is sent stays the Proposal.

local rebuildCheck : DepotRetrofitsRebuildCheck = {}

local simpleReplace = function(construction : Engine.Entity, params : {string : any}) : SimpleProposal
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil then return nil end
	local entry = api.type.SimpleProposal.ConstructionEntity.new()
	entry.fileName = con.fileName
	entry.transf = con.transf
	entry.params = params as table
	entry.playerEntity = api.engine.util.getPlayer()
	local proposal = api.type.SimpleProposal.new()
	proposal.constructionsToAdd = { entry }
	proposal.constructionsToRemove = { construction }
	proposal.old2new = { [construction] = 0 }
	return proposal
end

local check = function(construction : Engine.Entity, params : {string : any}) : Proposal, boolean, string
	local proposal = api.engine.util.proposal.createProposalReplaceConstruction(construction, params)
	if proposal == nil then return nil, nil, "noProposal" end
	local simple = simpleReplace(construction, params)
	if simple == nil then return proposal, nil, "noConstruction" end
	local data = api.engine.util.proposal.makeProposalData(simple as any as Proposal)
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
