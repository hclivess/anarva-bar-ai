-- Test harness for headless AI-vs-AI runs. Only copied into the test write-dir by run_match.py.
function widget:GetInfo()
	return {
		name    = "AI Test Harness",
		desc    = "Speeds up sim, logs team stats, quits at game end",
		author  = "tactician-dev",
		layer   = 0,
		enabled = true,
	}
end

local MAX_FRAMES = tonumber(Spring.GetConfigString("HarnessMaxFrames", "")) or (30 * 60 * 30)
local SPEED = 60

local function teamLine(teamID)
	local mCur, mStor, _, mInc = Spring.GetTeamResources(teamID, "metal")
	local eCur, eStor, _, eInc = Spring.GetTeamResources(teamID, "energy")
	local units = Spring.GetTeamUnits(teamID) or {}
	local army, eco = 0, 0
	for i = 1, #units do
		local ud = UnitDefs[Spring.GetUnitDefID(units[i])]
		if ud then
			if ud.canMove and #ud.weapons > 0 and not ud.isBuilder then
				army = army + ud.metalCost
			elseif not ud.canMove then
				eco = eco + ud.metalCost
			end
		end
	end
	local hist = Spring.GetTeamStatsHistory(teamID, 0, Spring.GetTeamStatsHistory(teamID))
	local last = hist and hist[#hist] or {}
	return string.format("team=%d units=%d army_m=%d static_m=%d m_inc=%.1f e_inc=%.0f m=%d/%d e=%d/%d killed_m=%d lost_m=%d",
		teamID, #units, army, eco, mInc or 0, eInc or 0, mCur or 0, mStor or 0, eCur or 0, eStor or 0,
		last.unitsKilled or 0, last.unitsDied or 0)
end

-- What each team has built, by kind and tech level (diagnostic: when do the bots tech, convert, expand?)
local function techLine(teamID)
	local c = {lab1 = 0, lab2 = 0, lab3 = 0, mex1 = 0, mex2 = 0, conv1 = 0, conv2 = 0, fus = 0, nano = 0, con = 0,
		arm1 = 0, arm2 = 0, arm3 = 0, def = 0}
	local units = Spring.GetTeamUnits(teamID) or {}
	for i = 1, #units do
		local _, _, _, _, bp = Spring.GetUnitHealth(units[i])
		local ud = UnitDefs[Spring.GetUnitDefID(units[i])]
		if ud and (bp or 1) >= 1 then
			local cp = ud.customParams or {}
			local tl = tonumber(cp.techlevel) or 1
			if ud.isFactory then
				c["lab" .. math.min(tl, 3)] = c["lab" .. math.min(tl, 3)] + 1
			elseif (ud.extractsMetal or 0) > 0 then
				if tl >= 2 then c.mex2 = c.mex2 + 1 else c.mex1 = c.mex1 + 1 end
			elseif cp.energyconv_capacity then
				if tl >= 2 then c.conv2 = c.conv2 + 1 else c.conv1 = c.conv1 + 1 end
			elseif (ud.energyMake or 0) >= 500 then
				c.fus = c.fus + 1
			elseif ud.isBuilder and not ud.canMove then
				c.nano = c.nano + 1
			elseif ud.isBuilder and ud.canMove then
				c.con = c.con + 1
			elseif ud.canMove and #ud.weapons > 0 then
				local k = "arm" .. math.min(tl, 3)
				c[k] = c[k] + ud.metalCost
			elseif #ud.weapons > 0 then
				c.def = c.def + ud.metalCost
			end
		end
	end
	return string.format("team=%d lab=%d/%d/%d mex=%d/%d conv=%d/%d fus=%d nano=%d con=%d armyM=%d/%d/%d defM=%d",
		teamID, c.lab1, c.lab2, c.lab3, c.mex1, c.mex2, c.conv1, c.conv2, c.fus, c.nano, c.con, c.arm1, c.arm2, c.arm3, c.def)
end

local function logAll(tag)
	local teams = Spring.GetTeamList()
	for i = 1, #teams do
		local t = teams[i]
		local _, _, isDead, isAI = Spring.GetTeamInfo(t, false)
		if t ~= Spring.GetGaiaTeamID() then
			Spring.Echo(string.format("[HARNESS] %s f=%d dead=%s %s", tag, Spring.GetGameFrame(), tostring(isDead), teamLine(t)))
				Spring.Echo(string.format("[HARNESS] tech f=%d %s", Spring.GetGameFrame(), techLine(t)))
		end
	end
end

function widget:GameFrame(n)
	if n == 5 or n % 300 == 0 then
		Spring.SendCommands("setmaxspeed " .. SPEED, "setminspeed " .. SPEED)
	end
	if n % 1800 == 0 then
		logAll("stats")
	end
	if n >= MAX_FRAMES then
		logAll("timeout")
		Spring.Echo("[HARNESS] RESULT timeout")
		Spring.SendCommands("quitforce")
	end
end

function widget:GameOver(winners)
	logAll("final")
	Spring.Echo("[HARNESS] RESULT winners=" .. table.concat(winners or {}, ","))
	Spring.SendCommands("quitforce")
end
