# Framed

WoW unit frames and raid frames addon. GPL v3.

## Architecture

- `Libs/oUF/` — Embedded oUF (MIT). Do not modify unless necessary.
- `Core/` — Config API, EventBus, Constants, SecretValues. The boundary between settings and frames.
- `Widgets/` — AF-inspired widget library. One file per widget type.
- `Elements/` — Self-registering oUF elements. Subfolders: Core/, Auras/, Indicators/, Status/.
- `Units/` — One file per unit type. Self-registering with oUF.
- `Settings/` — Sidebar + panels. Self-registering.
- `Layouts/` — Content detection, auto-switching, layout management.

## Code Style (Align with oUF)

- **Indentation**: Tabs (match oUF)
- **Conditions**: Parenthesized — `if(not unit) then` not `if not unit then`
- **Strings**: Single quotes for Lua strings (`'string'`), double-bracket for paths (`[[Interface\...]]`)
- **Iteration**: `for _, v in next, tbl do` — never `pairs()` or `ipairs()`
- **Naming**:
  - Local variables: `camelCase` — `local healthBar`, `local maxHealth`
  - Local functions: `camelCase` — `local function updateHealth()`
  - Element Update/Enable/Disable/Path: `PascalCase` — `local function Update()`, `local function Enable()`
  - Element properties on frames: `PascalCase` — `self.Health`, `self.Power`
  - Boolean options: `camelCase` — `element.colorClass`, `element.frequentUpdates`
  - Internal/private properties: double-underscore — `element.__owner`, `frame.__restricted`
- **File structure** (for oUF elements): locals → helpers → UpdateColor → ColorPath → Update → Path → ForceUpdate → setters → Enable → Disable → `oUF:AddElement()` last line

## Conventions

- Namespace: `local addonName, Framed = ...` in every file, with `local F = Framed` shorthand
- File size: ~500 lines max
- Settings never reach into frame internals — use Config API + EventBus
- Follow Blizzard API naming for code/files, player terminology for UI labels

## Secret Values

- ALWAYS use `F.IsValueNonSecret()` — never bare `issecretvalue()`
- One wrapper in `Core/SecretValues.lua`, used everywhere. Never create per-file wrappers or polyfills.
- **Derive from non-secret sources when possible** — e.g., determine `isHarmful` from the filter string, not the secret aura field (this is how oUF handles it)
- **Pass secrets to C-level APIs** that accept them: `SetValue()`, `SetMinMaxValues()`, `SetStatusBarColor()` — but NOT `SetStatusBarTexture()` or `SetTimerDuration()`
- **Never sanitize** secret values into placeholders. Pass through or degrade gracefully.
- **Treat potentially-secret auras as always secret** — don't juggle mixed state

## No pcall

- No `pcall` for error suppression or feature detection
- Feature detection: `if C_UnitAuras.GetAuraDuration then` not `pcall(...)`
- Only acceptable use: deserialization of untrusted import strings, or with explicit `-- BUG:` comment for known Blizzard bugs (oUF does this for `UnitPvpClassification`)

## Key Commands

- `/framed` or `/fr` — Show help
- `/framed version` — Version info
- `/framed config` — Debug config state
- `/framed events` — Debug registered events

## References

- Design spec: `docs/superpowers/specs/2026-03-24-framed-design.md`
- API source: https://github.com/jdtoppin/wow-ui-source/tree/live
- API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes
