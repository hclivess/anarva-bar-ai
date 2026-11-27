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

-- all state and helpers before the first callin (a later local is an undefined global inside earlier functions)
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


-- Squads: each team's armed mobile units (no builders, no air) grouped by single linkage - two units belong to the
-- same squad when they are within the longer of their two weapon ranges (they can support each other's fight). One
-- line per team every 15 s: unit count, squad sizes (largest first), and the largest squad's units.
local function maxRange(ud)
	local r = 0
	for _, w in ipairs(ud.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and (wd.range or 0) > r then r = wd.range end
	end
	return r
end
local function logSquads(n)
	local byTeam = {}
	for _, uid in ipairs(Spring.GetAllUnits()) do
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		local team = Spring.GetUnitTeam(uid)
		if ud and team and team ~= gaia and ud.canMove and not ud.canFly and not ud.isBuilder and #(ud.weapons or {}) > 0
			and not (ud.customParams and ud.customParams.iscommander) then
			local x, _, z = Spring.GetUnitPosition(uid)
			if x then
				byTeam[team] = byTeam[team] or {}
				local t = byTeam[team]
				t[#t + 1] = {x = x, z = z, r = maxRange(ud), name = ud.name}
			end
		end
	end
	for team, us in pairs(byTeam) do
		local cl, nc = {}, 0
		for i = 1, #us do
			if not cl[i] then
				nc = nc + 1; cl[i] = nc
				local stack = {i}
				while #stack > 0 do
					local a = table.remove(stack)
					for j = 1, #us do
						if not cl[j] then
							local dx, dz = us[a].x - us[j].x, us[a].z - us[j].z
							local link = math.max(us[a].r, us[j].r)
							if dx * dx + dz * dz <= link * link then cl[j] = nc; stack[#stack + 1] = j end
						end
					end
				end
			end
		end
		local size, comp = {}, {}
		for i = 1, #us do size[cl[i]] = (size[cl[i]] or 0) + 1 end
		local order = {}
		for c = 1, nc do order[#order + 1] = c end
		table.sort(order, function(a, b) return size[a] > size[b] end)
		local big = order[1]
		for i = 1, #us do if cl[i] == big then comp[us[i].name] = (comp[us[i].name] or 0) + 1 end end
		local sizes, parts = {}, {}
		for k = 1, math.min(#order, 12) do sizes[#sizes + 1] = tostring(size[order[k]]) end
		for name, c in pairs(comp) do parts[#parts + 1] = name .. ":" .. c end
		Spring.Echo(string.format("[REPLAY] SQUAD f=%d team=%d units=%d squads=%d sizes=%s big=%s", n, team, #us, nc, table.concat(sizes, ","), table.concat(parts, ",")))
		-- formation of the biggest squad (owner, 2026-11-26: "1 unit type bulked in one ball", #116): per type, count,
		-- weapon range, mean health share and mean distance to the nearest armed enemy - in contact, which types keep in
		-- front and which behind
		local ally = Spring.GetTeamAllyTeamID(team)
		local form = {}
		for i = 1, #us do
			if cl[i] == big then
				local nd = math.huge
				for t2, us2 in pairs(byTeam) do
					if Spring.GetTeamAllyTeamID(t2) ~= ally then
						for j = 1, #us2 do
							local dx, dz = us[i].x - us2[j].x, us[i].z - us2[j].z
							local d = math.sqrt(dx * dx + dz * dz)
							if d < nd then nd = d end
						end
					end
				end
				local f = form[us[i].name] or {n = 0, d = 0, r = us[i].r}
				f.n = f.n + 1; f.d = f.d + ((nd < math.huge) and nd or 0)
				form[us[i].name] = f
			end
		end
		local fp = {}
		for name, f in pairs(form) do fp[#fp + 1] = string.format("%s:%d:r%d:d%d", name, f.n, f.r, f.d / f.n) end
		Spring.Echo(string.format("[REPLAY] FORM f=%d team=%d %s", n, team, table.concat(fp, ",")))
		-- shape of the biggest squad (owner's 8v8 screenshot, #119: lines/arcs across the enemy's approach, not balls):
		-- principal axes of its positions (aspect = long / short spread), the angle between the long axis and the
		-- direction to the nearest enemy armed unit from the squad centre (90 = a line across their approach), and
		-- concavity: the flanks' (outer thirds along the long axis) mean distance to that enemy minus the centre third's
		-- (negative = flanks forward, a concave)
		local px, pz, m = {}, {}, 0
		for i = 1, #us do if cl[i] == big then m = m + 1; px[m] = us[i].x; pz[m] = us[i].z end end
		if m >= 3 then
			local cx, cz = 0, 0
			for i = 1, m do cx = cx + px[i]; cz = cz + pz[i] end
			cx, cz = cx / m, cz / m
			local sxx, szz, sxz = 0, 0, 0
			for i = 1, m do local dx, dz = px[i] - cx, pz[i] - cz; sxx = sxx + dx * dx; szz = szz + dz * dz; sxz = sxz + dx * dz end
			sxx, szz, sxz = sxx / m, szz / m, sxz / m
			local tr, det = sxx + szz, sxx * szz - sxz * sxz
			local disc = math.sqrt(math.max(0, tr * tr / 4 - det))
			local l1, l2 = tr / 2 + disc, math.max(0, tr / 2 - disc)
			local ax, az = (math.abs(sxz) > 1e-6) and (l1 - szz) or 1, (math.abs(sxz) > 1e-6) and sxz or 0
			if sxx < szz and math.abs(sxz) <= 1e-6 then ax, az = 0, 1 end
			local al = math.sqrt(ax * ax + az * az); ax, az = ax / al, az / al
			local ex, ez, nd = nil, nil, math.huge
			for t2, us2 in pairs(byTeam) do
				if Spring.GetTeamAllyTeamID(t2) ~= ally then
					for j = 1, #us2 do
						local dx, dz = us2[j].x - cx, us2[j].z - cz
						local d = math.sqrt(dx * dx + dz * dz)
						if d < nd then nd, ex, ez = d, us2[j].x, us2[j].z end
					end
				end
			end
			if ex then
				local vx, vz = (ex - cx) / math.max(1, nd), (ez - cz) / math.max(1, nd)
				local ang = math.deg(math.acos(math.min(1, math.abs(ax * vx + az * vz))))
				local proj, lo, hi = {}, math.huge, -math.huge
				for i = 1, m do proj[i] = (px[i] - cx) * ax + (pz[i] - cz) * az; lo = math.min(lo, proj[i]); hi = math.max(hi, proj[i]) end
				local third = (hi - lo) / 3
				local fs, fn, cs, cn = 0, 0, 0, 0
				for i = 1, m do
					local dx, dz = px[i] - ex, pz[i] - ez
					local d = math.sqrt(dx * dx + dz * dz)
					if proj[i] < lo + third or proj[i] > hi - third then fs = fs + d; fn = fn + 1 else cs = cs + d; cn = cn + 1 end
				end
				local conc = (fn > 0 and cn > 0) and (fs / fn - cs / cn) or 0
				Spring.Echo(string.format("[REPLAY] SHAPE f=%d team=%d units=%d aspect=%.2f long=%d facing=%d concave=%d enemy=%d",
					n, team, m, math.sqrt(l1 / math.max(1, l2)), 2 * math.sqrt(l1), ang, conc, nd))
			end
		end
	end
	-- factories (owner's friend game, #121: production stopped at minute 13 with both banks full): per factory its current
	-- command (5 = WAIT), queue length, what it is building and that unit's build progress
	for _, team in ipairs(Spring.GetTeamList()) do
		local parts = {}
		for _, uid in ipairs(Spring.GetTeamUnits(team) or {}) do
			local ud = UnitDefs[Spring.GetUnitDefID(uid)]
			if ud and ud.isFactory then
				local cmd = Spring.GetUnitCurrentCommand(uid)
				local q = Spring.GetFactoryCommands(uid, 0) or 0
				local b = Spring.GetUnitIsBuilding(uid)
				local bn, bp = "-", -1
				if b then
					local bd = UnitDefs[Spring.GetUnitDefID(b)]
					bn = bd and bd.name or "?"
					local _, _, _, _, prog = Spring.GetUnitHealth(b)
					bp = prog or -1
				end
				parts[#parts + 1] = string.format("%s:cmd%s:q%s:%s:%.2f", ud.name, tostring(cmd), tostring(q), bn, bp)
			end
		end
		if #parts > 0 then Spring.Echo(string.format("[REPLAY] FACT f=%d team=%d %s", n, team, table.concat(parts, ","))) end
	end
	-- the alive army: per team, every armed mobile unit type alive now, its count, mean health share, how many are
	-- moving, and their orders (the first command of each unit), plus where the army's centre is relative to its start
	local army = {}
	for _, uid in ipairs(Spring.GetAllUnits()) do
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		local team = Spring.GetUnitTeam(uid)
		if ud and team and team ~= gaia and ud.canMove and #(ud.weapons or {}) > 0 and not ud.isBuilder
			and not (ud.customParams and ud.customParams.iscommander) then
			army[team] = army[team] or {types = {}, cmds = {}, sx = 0, sz = 0, n = 0}
			local a = army[team]
			local t = a.types[ud.name] or {0, 0, 0}
			local hp, maxhp = Spring.GetUnitHealth(uid)
			local vx, _, vz = Spring.GetUnitVelocity(uid)
			t[1] = t[1] + 1
			t[2] = t[2] + ((hp and maxhp and maxhp > 0) and hp / maxhp or 0)
			t[3] = t[3] + ((vx and (vx * vx + vz * vz) > 0.01) and 1 or 0)
			a.types[ud.name] = t
			local q = Spring.GetUnitCommands(uid, 1)
			local c = (q and q[1]) and (cmdName[q[1].id] or tostring(q[1].id)) or "idle"
			a.cmds[c] = (a.cmds[c] or 0) + 1
			local x, _, z = Spring.GetUnitPosition(uid)
			if x then a.sx = a.sx + x; a.sz = a.sz + z; a.n = a.n + 1 end
		end
	end
	for team, a in pairs(army) do
		local parts, cmds = {}, {}
		for name, t in pairs(a.types) do parts[#parts + 1] = string.format("%s:%d:%.2f:%d", name, t[1], t[2] / t[1], t[3]) end
		for c, k in pairs(a.cmds) do cmds[#cmds + 1] = c .. ":" .. k end
		Spring.Echo(string.format("[REPLAY] ARMY f=%d team=%d cx=%d cz=%d types=%s cmds=%s", n, team,
			a.n > 0 and math.floor(a.sx / a.n) or -1, a.n > 0 and math.floor(a.sz / a.n) or -1, table.concat(parts, ","), table.concat(cmds, ",")))
	end
end

local dumped = false

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
	-- the engine's own wind range and tidal strength (map defaults and overrides applied): the map's energy facts
	Spring.Echo(string.format("[REPLAY] WIND min=%.2f max=%.2f tidal=%.2f", Game.windMin or -1, Game.windMax or -1, Game.tidal or -1))
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
	if n % 450 == 0 and n > 0 then logSquads(n) end
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

function widget:Shutdown()
	if not dumped then dumpMatrix(); dumped = true end  -- a replay cut by the wall clock never reaches GameOver
	Spring.Echo("[REPLAY] END f=" .. Spring.GetGameFrame())
end

function widget:GameOver(winners)
	dumpMatrix(); dumped = true
	Spring.Echo("[REPLAY] WINNERS ally=" .. table.concat(winners or {}, ",") .. " f=" .. Spring.GetGameFrame())
	Spring.SendCommands("quitforce")
end
