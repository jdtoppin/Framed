#!/usr/bin/env luajit
--[[
	sync-changelog.lua

	Parses the two most recent release blocks from CHANGELOG.md and rewrites
	the CHANGELOG table in Settings/Cards/About.lua between its
	BEGIN/END GENERATED CHANGELOG markers.

	Run from the repo root before bumping the TOC version:
		./tools/sync-changelog.lua
	or:
		luajit tools/sync-changelog.lua
]]

local CHANGELOG_MD = 'CHANGELOG.md'
local TARGET_LUA   = 'Settings/Cards/About.lua'
local MAX_RELEASES = 2

-- ── Parse CHANGELOG.md ────────────────────────────────────────
local releases = {}
local current

local f, err = io.open(CHANGELOG_MD, 'r')
if(not f) then
	io.stderr:write('Cannot open ' .. CHANGELOG_MD .. ': ' .. tostring(err) .. '\n')
	os.exit(1)
end

for line in f:lines() do
	local ver = line:match('^## (v[%w%.%-]+)')
	if(ver) then
		if(#releases >= MAX_RELEASES) then break end
		current = { version = ver, entries = {} }
		releases[#releases + 1] = current
	elseif(current) then
		local entry = line:match('^%- (.+)$')
		if(entry) then
			current.entries[#current.entries + 1] = entry
		end
	end
end
f:close()

if(#releases == 0) then
	io.stderr:write('No release blocks found in ' .. CHANGELOG_MD .. '\n')
	os.exit(1)
end

-- ── Emit Lua table block ──────────────────────────────────────
local function escape(s)
	return (s:gsub('\\', '\\\\'):gsub('\'', '\\\''))
end

local out = { 'local CHANGELOG = {' }
for _, r in ipairs(releases) do
	out[#out + 1] = '\t{'
	out[#out + 1] = string.format('\t\tversion = \'%s\',', escape(r.version))
	out[#out + 1] = '\t\tentries = {'
	for _, e in ipairs(r.entries) do
		out[#out + 1] = string.format('\t\t\t\'%s\',', escape(e))
	end
	out[#out + 1] = '\t\t},'
	out[#out + 1] = '\t},'
end
out[#out + 1] = '}'
local block = table.concat(out, '\n')

-- ── Splice into target file ───────────────────────────────────
f, err = io.open(TARGET_LUA, 'r')
if(not f) then
	io.stderr:write('Cannot open ' .. TARGET_LUA .. ': ' .. tostring(err) .. '\n')
	os.exit(1)
end
local src = f:read('*a')
f:close()

local pattern = '%-%- BEGIN GENERATED CHANGELOG\n.-\n%-%- END GENERATED CHANGELOG'
local replacement = '-- BEGIN GENERATED CHANGELOG\n' .. block .. '\n-- END GENERATED CHANGELOG'
local new, n = src:gsub(pattern, function() return replacement end, 1)

if(n == 0) then
	io.stderr:write('No BEGIN/END GENERATED CHANGELOG markers found in ' .. TARGET_LUA .. '\n')
	os.exit(1)
end

if(new == src) then
	print('Already up to date: ' .. TARGET_LUA)
	os.exit(0)
end

f, err = io.open(TARGET_LUA, 'w')
if(not f) then
	io.stderr:write('Cannot write ' .. TARGET_LUA .. ': ' .. tostring(err) .. '\n')
	os.exit(1)
end
f:write(new)
f:close()

print(string.format('Synced %d release(s) from %s → %s', #releases, CHANGELOG_MD, TARGET_LUA))
