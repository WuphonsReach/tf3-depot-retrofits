-- Whether the game would build a construction's rebuild, asked before it is sent; shared by the game script and the building
-- window (each loads it with ug_require under pcall). Its verdict goes into the log only: asked about a stand-in for the
-- rebuild, it called buildings blocked that the game rebuilds (docs/design/findings.md), so a buy is now sent and the game
-- decides. The game refuses a proposal whose data carries error messages, for
-- example "Collision" when something built around the building since, such as a town building, is in its way
-- (docs/design/findings.md); the base windows treat a proposal with no messages as buildable
-- (gui/entity_window/bridge_and_tunnel.tl).
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

-- Asked as a removal and a new building, the check also reports the building's own road connection: the road its entrance
-- joins collides with the entrance the new building would lay, while the game's own rebuild keeps the connection and is
-- built (a road depot in a 1900 save came back "Collision" with one half of the road its entrance had split, and the rebuild
-- sent anyway landed; docs/design/findings.md). So a collision only with road that ends at a node of the building's own
-- road pieces (its frozen edges and nodes) counts as clear. Any other message or colliding entity still blocks.
local ownRoadOnly = function(construction : Engine.Entity, messages : {string}, colliding : {Engine.Entity}) : boolean
	if #colliding == 0 then return false end
	for _, message in ipairs(messages) do
		if message ~= "Collision" then return false end
	end
	local con = api.engine.getComponent(construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil then return false end
	local own : {Engine.Entity : boolean} = {}
	for _, node in ipairs(con.frozenNodes or {}) do own[node] = true end
	for _, edge in ipairs(con.frozenEdges or {}) do
		local base = api.engine.getComponent(edge, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		if base ~= nil then
			own[base.node0] = true
			own[base.node1] = true
		end
	end
	for _, entity in ipairs(colliding) do
		local base = api.engine.getComponent(entity, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		if base == nil or not (own[base.node0] or own[base.node1]) then return false end
	end
	return true
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
	local colliding : {Engine.Entity} = {}
	local info = data.collisionInfo
	if info ~= nil and info.collisionEntities ~= nil then
		for _, c in ipairs(info.collisionEntities) do
			entities[#entities + 1] = tostring(c.entity)
			colliding[#colliding + 1] = c.entity
		end
	end
	local detail = "messages=" .. table.concat(messages, ";") .. " collisionEntities=" .. table.concat(entities, ",")
	if ownRoadOnly(construction, messages, colliding) then return proposal, true, "ownRoad " .. detail end
	return proposal, false, detail
end

function rebuildCheck.check(construction : Engine.Entity, params : {string : any}) : Proposal, boolean, string
	local ok, proposal, clear, reason = pcall(check, construction, params)
	if not ok then return nil, nil, "checkError error=" .. tostring(proposal) end
	return proposal, clear, reason
end

return rebuildCheck
