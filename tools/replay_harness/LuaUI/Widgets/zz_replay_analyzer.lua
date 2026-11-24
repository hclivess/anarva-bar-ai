-- Replay analyzer: logs per-team economy curve, build orders and the winner while a demo plays headless.
function widget:GetInfo()
	return { name = "Replay Analyzer", desc = "dev: dumps replay stats to infolog", author = "anarva-dev",
		layer = 0, enabled = true }
end

local SPEED = 80
local gaia = Spring.GetGaiaTeamID()

local function teamTag(t)
	local _, leader, _, isAI, side, ally = Spring.GetTeamInfo(t, false)
	local name = leader and Spring.GetPlayerInfo(leader, false) or "?"
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(t)
		name = "AI:" .. tostring(shortName or aiName)
	end
	return string.format("team=%d ally=%d side=%s name=%s", t, ally or -1, tostring(side), tostring(name))
end

-- Commander study: where each commander is, what it does and what is around it, every 5 s.
local comms = {}       -- unitID -> {team, x0, z0}
local cmdName = {}
local function isComm(ud) return ud and ud.customParams and ud.customParams.iscommander end
local function cmdOf(uid)
	local id, _, _, p1, _, p3 = Spring.GetUnitCurrentCommand(uid)
	if not id then return "idle" end
	if id < 0 then local bd = UnitDefs[-id]; return "build:" .. (bd and bd.name or "?") end
	return (cmdName[id] or "?") .. "#" .. tostring(id)
end
local function around(uid, team, r)
	local x, _, z = Spring.GetUnitPosition(uid)
	local own, enemy, nearest = 0, 0, 1e9
	local ally = select(6, Spring.GetTeamInfo(team, false))
	for _, v in ipairs(Spring.GetUnitsInCylinder(x, z, r) or {}) do
		if v ~= uid then
			local ud = UnitDefs[Spring.GetUnitDefID(v)]
			local vt = Spring.GetUnitTeam(v)
			if ud and #ud.weapons > 0 and vt ~= gaia then
				if select(6, Spring.GetTeamInfo(vt, false)) == ally then own = own + ud.metalCost else enemy = enemy + ud.metalCost end
			end
		end
	end
	for _, t in ipairs(Spring.GetTeamList()) do
		if t ~= gaia and select(6, Spring.GetTeamInfo(t, false)) ~= ally then
			local e = Spring.GetUnitNearestEnemy and Spring.GetUnitNearestEnemy(uid, 1e6, false)
			if e then local ex, _, ez = Spring.GetUnitPosition(e); if ex then nearest = math.sqrt((ex - x) ^ 2 + (ez - z) ^ 2) end end
			break
		end
	end
	return own, enemy, nearest
end

function widget:Initialize()
	for k, v in pairs(CMD) do if type(v) == "number" and type(k) == "string" and k:upper() == k then cmdName[v] = k end end
	Spring.SendCommands("specfullview 1")
	local teams = Spring.GetTeamList()
	for i = 1, #teams do
		if teams[i] ~= gaia then
			Spring.Echo("[REPLAY] TEAM " .. teamTag(teams[i]))
		end
	end
	Spring.Echo("[REPLAY] MAP " .. tostring(Game.mapName) .. " " .. Game.mapSizeX .. "x" .. Game.mapSizeZ)
end

function widget:GameFrame(n)
	if n % 90 == 1 then  -- pick up commanders that existed before the widget saw them
		for _, uid in ipairs(Spring.GetAllUnits()) do
			if not comms[uid] then
				local t = Spring.GetUnitTeam(uid)
				if t ~= gaia and isComm(UnitDefs[Spring.GetUnitDefID(uid)]) then
					local x, _, z = Spring.GetUnitPosition(uid)
					comms[uid] = {team = t, x0 = x or 0, z0 = z or 0}
				end
			end
		end
	end
	if n % 150 == 0 then
		for uid, c in pairs(comms) do
			local x, _, z = Spring.GetUnitPosition(uid)
			if x then
				local hp, maxhp = Spring.GetUnitHealth(uid)
				local own, enemy, nearest = around(uid, c.team, 600)
				Spring.Echo(string.format("[REPLAY] COMM f=%d team=%d x=%d z=%d fromStart=%d hp=%.2f cmd=%s own600=%d enemy600=%d nearestEnemy=%d",
					n, c.team, x, z, math.sqrt((x - c.x0) ^ 2 + (z - c.z0) ^ 2), (hp or 0) / math.max(1, maxhp or 1), cmdOf(uid), own, enemy, nearest))
			end
		end
	end
	if n % 300 == 5 then
		Spring.SendCommands("setmaxspeed " .. SPEED, "setminspeed " .. SPEED, "setspeed " .. SPEED)
	end
	if n % 1800 == 0 and n > 0 then
		local teams = Spring.GetTeamList()
		for i = 1, #teams do
			local t = teams[i]
			if t ~= gaia then
				local _, _, _, mInc = Spring.GetTeamResources(t, "metal")
				local _, _, _, eInc = Spring.GetTeamResources(t, "energy")
				local units = Spring.GetTeamUnits(t) or {}
				local army, eco, def = 0, 0, 0
				for j = 1, #units do
					local ud = UnitDefs[Spring.GetUnitDefID(units[j])]
					if ud then
						if ud.canMove and #ud.weapons > 0 and not ud.isBuilder then army = army + ud.metalCost
						elseif not ud.canMove and #ud.weapons > 0 then def = def + ud.metalCost
						elseif not ud.canMove then eco = eco + ud.metalCost end
					end
				end
				Spring.Echo(string.format("[REPLAY] STAT min=%d team=%d m_inc=%.1f e_inc=%.0f army=%d def=%d eco=%d units=%d",
					n / 1800, t, mInc or 0, eInc or 0, army, def, eco, #units))
			end
		end
	end
end

function widget:UnitCreated(unitID, unitDefID, teamID, builderID)
	local ud = UnitDefs[unitDefID]
	if isComm(ud) and teamID ~= gaia then
		local x, _, z = Spring.GetUnitPosition(unitID)
		comms[unitID] = {team = teamID, x0 = x or 0, z0 = z or 0}
	elseif builderID and comms[builderID] and ud then
		local x, _, z = Spring.GetUnitPosition(unitID)
		local c = comms[builderID]
		Spring.Echo(string.format("[REPLAY] CBUILD f=%d team=%d %s fromStart=%d", Spring.GetGameFrame(), teamID, ud.name,
			math.sqrt(((x or 0) - c.x0) ^ 2 + ((z or 0) - c.z0) ^ 2)))
	end
end

function widget:UnitDestroyed(unitID, unitDefID, teamID, attackerID)
	local c = comms[unitID]
	if c then
		local x, _, z = Spring.GetUnitPosition(unitID)
		Spring.Echo(string.format("[REPLAY] CDEATH f=%d team=%d fromStart=%d", Spring.GetGameFrame(), c.team,
			math.sqrt(((x or 0) - c.x0) ^ 2 + ((z or 0) - c.z0) ^ 2)))
		comms[unitID] = nil
	end
end

function widget:UnitFinished(unitID, unitDefID, teamID)
	local ud = UnitDefs[unitDefID]
	if ud and teamID ~= gaia then
		Spring.Echo(string.format("[REPLAY] BUILT f=%d team=%d %s m=%d", Spring.GetGameFrame(), teamID, ud.name, ud.metalCost))
	end
end

function widget:GameOver(winners)
	Spring.Echo("[REPLAY] WINNERS ally=" .. table.concat(winners or {}, ",") .. " f=" .. Spring.GetGameFrame())
	Spring.SendCommands("quitforce")
end
