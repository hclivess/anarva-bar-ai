-- Replay analyzer: logs per-team economy curve, build orders and the winner while a demo plays headless.
function widget:GetInfo()
	return { name = "Replay Analyzer", desc = "dev: dumps replay stats to infolog", author = "anarva-dev",
		layer = 0, enabled = true }
end

local SPEED = 80
local gaia = Spring.GetGaiaTeamID()

-- declared before every callin that uses them: as later locals, UnitDestroyed saw undefined globals, the first kill
-- raised an error and the widget was removed (no STAT/DMG after that)
local dmgM, killM = {}, {}  -- [attackerDefID][victimDefID] = damage / metal killed (enemy pairs only)
local function enemies(t1, t2)
	if not t1 or not t2 or t1 == gaia or t2 == gaia then return false end
	return select(6, Spring.GetTeamInfo(t1, false)) ~= select(6, Spring.GetTeamInfo(t2, false))
end

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

local MAXF = 1e9  -- play to the end: late units (T3, Behemoth) matter for the counter matrix
function widget:GameFrame(n)
	if n >= MAXF then
		dumpMatrix()
		Spring.Echo("[REPLAY] CAP f=" .. n)
		Spring.SendCommands("quitforce")
		return
	end
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
	if n % 15 == 0 then sampleMotion(n) end
	if n % 1800 == 0 and n > 0 then
		for team, kinds in pairs(motion) do
			for k, m in pairs(kinds) do
				Spring.Echo(string.format("[REPLAY] MOTION min=%d team=%d kind=%s n=%d speed=%.2f turn=%.2f", n / 1800, team, k, m[1], m[2] / m[1], m[3] / m[1]))
			end
		end
		motion = {}
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
	if n == 31 then  -- demos ignore speed commands: skip simulates ahead at full speed, callins still run
		Spring.SendCommands("skip 36000")  -- simulate ahead at full speed; the game ends first
	end
	if n % 1800 == 0 and n > 0 then
		local teams = Spring.GetTeamList()
		for i = 1, #teams do
			local t = teams[i]
			if t ~= gaia then
				local mCur, mSto, mPull, mInc, mExp = Spring.GetTeamResources(t, "metal")
				local eCur, eSto, ePull, eInc, eExp = Spring.GetTeamResources(t, "energy")
				local units = Spring.GetTeamUnits(t) or {}
				local army, eco, def = 0, 0, 0
				local builders, bp, mex, facs, mexInc = 0, 0, 0, 0, 0
				for j = 1, #units do
					local ud = UnitDefs[Spring.GetUnitDefID(units[j])]
					if ud then
						if ud.canMove and #ud.weapons > 0 and not ud.isBuilder then army = army + ud.metalCost
						elseif not ud.canMove and #ud.weapons > 0 then def = def + ud.metalCost
						elseif not ud.canMove then eco = eco + ud.metalCost end
						if ud.isFactory then facs = facs + 1
						elseif ud.isBuilder and (ud.buildSpeed or 0) > 0 then builders = builders + 1; bp = bp + ud.buildSpeed end
						if (ud.extractsMetal or 0) > 0 then
							mex = mex + 1
							local mm = Spring.GetUnitResources(units[j])
							mexInc = mexInc + (mm or 0)
						end
					end
				end
				Spring.Echo(string.format("[REPLAY] STAT min=%d team=%d m_inc=%.1f e_inc=%.0f army=%d def=%d eco=%d units=%d"
					.. " m_cur=%d m_sto=%d m_exp=%.1f e_cur=%d e_sto=%d e_exp=%.0f builders=%d bp=%d mex=%d mex_inc=%.1f facs=%d",
					n / 1800, t, mInc or 0, eInc or 0, army, def, eco, #units,
					mCur or 0, mSto or 0, mExp or 0, eCur or 0, eSto or 0, eExp or 0, builders, bp, mex, mexInc, facs))
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

local function dumpMatrix()
	for a, row in pairs(dmgM) do
		for v, d in pairs(row) do
			local ad, vd = UnitDefs[a], UnitDefs[v]
			if ad and vd then
				Spring.Echo(string.format("[REPLAY] DMG att=%s vic=%s dmg=%d killM=%d", ad.name, vd.name, d, (killM[a] and killM[a][v]) or 0))
			end
		end
	end
end

function widget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeam)
	if attackerDefID and unitDefID and enemies(attackerTeam, teamID) then
		local vd = UnitDefs[unitDefID]
		killM[attackerDefID] = killM[attackerDefID] or {}
		killM[attackerDefID][unitDefID] = (killM[attackerDefID][unitDefID] or 0) + (vd and vd.metalCost or 0)
		dmgM[attackerDefID] = dmgM[attackerDefID] or {}
		dmgM[attackerDefID][unitDefID] = dmgM[attackerDefID][unitDefID] or 0
	end
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
		-- kind facts for clustering: tech level, air, sea, static, builder, armed, longest weapon range
		local cp = ud.customParams or {}
		local tl = tonumber(cp.techlevel) or 1
		local range = 0
		for _, w in ipairs(ud.weapons or {}) do
			local wd = WeaponDefs[w.weaponDef]
			if wd and wd.range and wd.range > range then range = wd.range end
		end
		local md = ud.moveDef and ud.moveDef.name or ""
		local sea = (ud.minWaterDepth or 0) > 0 or (md:find("boat") ~= nil) or (md:find("uboat") ~= nil)
		local bx, _, bz = Spring.GetUnitPosition(unitID)
		Spring.Echo(string.format("[REPLAY] BUILT f=%d team=%d %s m=%d tl=%d air=%d sea=%d static=%d builder=%d armed=%d range=%d fac=%d x=%d z=%d",
			Spring.GetGameFrame(), teamID, ud.name, ud.metalCost, tl, ud.canFly and 1 or 0, sea and 1 or 0,
			(ud.canMove and not ud.isFactory) and 0 or 1, ud.isBuilder and 1 or 0, #(ud.weapons or {}) > 0 and 1 or 0, range, ud.isFactory and 1 or 0, bx or -1, bz or -1))
	end
end

local firstHit = {}
local lastCombat = {}
local lastHeading = {}
local motion = {}  -- team -> kind -> {n, speedFrac, turnFrac}
local function kindOf(ud)
	local md = ud.moveDef and ud.moveDef.name or ""
	if md:find("boat") then return "boat" elseif md:find("hover") then return "hover"
	elseif md:find("tank") then return "tank" elseif md:find("bot") or md:find("kbot") then return "bot" end
	return "other"
end
local function sampleMotion(n)
	for uid, f in pairs(lastCombat) do
		if n - f > 150 then
			lastCombat[uid] = nil; lastHeading[uid] = nil
		else
			local udid = Spring.GetUnitDefID(uid)
			local ud = udid and UnitDefs[udid]
			local team = Spring.GetUnitTeam(uid)
			if ud and team and ud.canMove and not ud.canFly and #(ud.weapons or {}) > 0 and (ud.speed or 0) > 0 then
				local vx, _, vz = Spring.GetUnitVelocity(uid)
				local h = Spring.GetUnitHeading(uid)
				if vx and h then
					local sp = math.sqrt(vx * vx + vz * vz) * 30 / ud.speed
					local tf = 0
					if lastHeading[uid] and (ud.turnRate or 0) > 0 then
						local dh = math.abs(h - lastHeading[uid]) % 65536
						if dh > 32768 then dh = 65536 - dh end
						tf = (dh / 15) / ud.turnRate  -- heading units per frame vs max per frame
					end
					lastHeading[uid] = h
					local k = kindOf(ud)
					motion[team] = motion[team] or {}
					local m = motion[team][k] or {0, 0, 0}
					m[1] = m[1] + 1; m[2] = m[2] + math.min(sp, 1.5); m[3] = m[3] + math.min(tf, 1.5)
					motion[team][k] = m
				end
			end
		end
	end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	local fr = Spring.GetGameFrame()
	if attackerDefID and unitDefID and not paralyzer and damage > 0 and enemies(attackerTeam, unitTeam) then
		dmgM[attackerDefID] = dmgM[attackerDefID] or {}
		dmgM[attackerDefID][unitDefID] = (dmgM[attackerDefID][unitDefID] or 0) + damage
	end
	lastCombat[unitID] = fr
	if attackerID then lastCombat[attackerID] = fr end
	if attackerTeam and unitTeam and attackerTeam ~= unitTeam and attackerTeam ~= gaia and unitTeam ~= gaia and not firstHit[attackerTeam] then
		local a1 = select(6, Spring.GetTeamInfo(attackerTeam, false))
		local a2 = select(6, Spring.GetTeamInfo(unitTeam, false))
		if a1 ~= a2 then
			firstHit[attackerTeam] = true
			Spring.Echo(string.format("[REPLAY] FIRSTHIT f=%d team=%d", Spring.GetGameFrame(), attackerTeam))
		end
	end
end

local dumped = false
function widget:Shutdown()
	if not dumped then dumpMatrix(); dumped = true end  -- a replay cut by the wall clock never reaches GameOver
	Spring.Echo("[REPLAY] END f=" .. Spring.GetGameFrame())
end

function widget:GameOver(winners)
	dumpMatrix(); dumped = true
	Spring.Echo("[REPLAY] WINNERS ally=" .. table.concat(winners or {}, ",") .. " f=" .. Spring.GetGameFrame())
	Spring.SendCommands("quitforce")
end
