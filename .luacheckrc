std = 'lua51'
codes = true
global = false
unused_args = false
max_line_length = false

-- Every file starts with `local addonName, Framed = ...` per project
-- convention (see CLAUDE.md). The first return is frequently unused.
ignore = {
	'211/addonName',
}

exclude_files = {
	'Libs/**',
}
