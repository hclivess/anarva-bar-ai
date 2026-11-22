--
--  Anarva - a BARb (CircuitAI) derivative for Beyond All Reason.
--  Same C++ core as BARb, with its own AngelScript brain and configs.
--

local infos = {
	{
		key    = 'shortName',
		value  = 'Anarva', -- AI name - !This comment is used for parsing!
		desc   = 'machine conform name.',
	},
	{
		key    = 'version',
		value  = 'stable', -- AI version - !This comment is used for parsing!
	},
	{
		key    = 'name',
		value  = 'Anarvā',
		desc   = 'human readable name.',
	},
	{
		key    = 'description',
		value  = 'BARb-based AI: massed attacks, reclaims obsolete eco, hunts jammers.',
		desc   = 'tooltip.',
	},
	{
		key    = 'url',
		value  = 'https://github.com/rlcevg/CircuitAI',
		desc   = 'URL with more detailed info about the AI',
	},
	{
		key    = 'loadSupported',
		value  = 'yes',
		desc   = 'whether this AI supports loading or not',
	},
	{
		key    = 'interfaceShortName',
		value  = 'C', -- AI Interface name - !This comment is used for parsing!
		desc   = 'the shortName of the AI interface this AI needs',
	},
	{
		key    = 'interfaceVersion',
		value  = '0.1', -- AI Interface version - !This comment is used for parsing!
		desc   = 'the minimum version of the AI interface this AI needs',
	},
}

return infos
