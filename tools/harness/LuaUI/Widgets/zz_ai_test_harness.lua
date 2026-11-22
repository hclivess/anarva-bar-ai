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

local MAX_FRAMES = tonumber(Spring.GetConfigString("HarnessMaxFrames", "")) or (40 * 60 * 30)
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

local function logAll(tag)
	local teams = Spring.GetTeamList()
	for i = 1, #teams do
		local t = teams[i]
		local _, _, isDead, isAI = Spring.GetTeamInfo(t, false)
		if t ~= Spring.GetGaiaTeamID() then
			Spring.Echo(string.format("[HARNESS] %s f=%d dead=%s %s", tag, Spring.GetGameFrame(), tostring(isDead), teamLine(t)))
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
