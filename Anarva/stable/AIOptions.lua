local options = {
	{ -- section
		key    = 'performance',
		name   = 'Performance Relevant Settings',
		desc   = 'These settings may be relevant for both CPU usage and AI difficulty.',
		type   = 'section',
	},
	{ -- bool
		key     = 'cheating',
		name    = 'LOS vision',
		desc    = 'Enable global sight (cheat)',
		type    = 'bool',
		section = 'performance',
		def     = false,
	},
	{ -- bool
		key     = 'comm_merge',
		name    = 'Merge neighbour AIs',
		desc    = 'Merge spatially close ally commanders',
		type    = 'bool',
		section = 'performance',
		def     = false,
	},
	{ -- bool
		key     = 'ally_base',
		name    = 'Avoid building in allied bases',
		desc    = 'Do not build units near allied factories',
		type    = 'bool',
		section = 'performance',
		def     = true,
	},
	{ -- string
		key     = 'disabledunits',
		name    = 'Disabled units',
		desc    = 'Disable usage of specific units.\nSyntax: armwar+armpw+raveparty\nkey: disabledunits',
		type    = 'string',
		def     = '',
	},
	{ -- bool
		-- Must stay false: configs/scripts ship with this AI, not with the game.
		key     = 'game_config',
		name    = 'Load game config',
		desc    = 'Load game-side config (leave off for Anarva)',
		type    = 'bool',
		def     = false,
	},
	{ -- list
		key     = 'profile',
		name    = 'Profile',
		desc    = 'Play-style of AI.\nkey: profile',
		type    = 'list',
		def     = 'anarva',
		items   = {
			{
				key  = 'anarva',
				name = 'Anarva',
				desc = 'Massed attacks, eco recycling, jammer hunting',
			},
			{
				key  = 'anarva_b',
				name = 'Anarva (test variant)',
				desc = 'Development A/B variant',
			},
		},
	},
}

return options
