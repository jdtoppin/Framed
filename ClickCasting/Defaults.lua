local addonName, Framed = ...
local F = Framed

F.ClickCasting = F.ClickCasting or {}
F.ClickCasting.Defaults = {}

-- Generic defaults (all classes/specs)
F.ClickCasting.Defaults['generic'] = {
	{ button = 'LeftButton', type = 'target' },
	{ button = 'RightButton', type = 'menu' },
}
