# Framed

WoW unit frames and raid frames addon. GPL v3.

## Architecture

- `Libs/oUF/` — Embedded oUF (MIT). Do not modify unless necessary.
- `Core/` — Config API, EventBus, Constants. The boundary between settings and frames.
- `Widgets/` — AF-inspired widget library. One file per widget type.
- `Elements/` — Self-registering oUF elements. Subfolders: Core/, Auras/, Indicators/, Status/.
- `Units/` — One file per unit type. Self-registering with oUF.
- `Settings/` — Sidebar + panels. Self-registering.
- `Layouts/` — Content detection, auto-switching, layout management.

## Conventions

- Namespace: `local addonName, Framed = ...` in every file
- File size: ~500 lines max
- Settings never reach into frame internals — use Config API + EventBus
- No pcall for error suppression
- Secret values: ALWAYS use Framed.IsValueNonSecret() — never bare issecretvalue()
- One wrapper in Core/SecretValues.lua, used everywhere. Never create per-file wrappers or polyfills.
- Follow Blizzard API naming for code/files, player terminology for UI labels

## Key Commands

- `/framed` or `/fr` — Show help
- `/framed version` — Version info
- `/framed config` — Debug config state
- `/framed events` — Debug registered events

## References

- Design spec: `docs/superpowers/specs/2026-03-24-framed-design.md`
- API source: https://github.com/jdtoppin/wow-ui-source/tree/live
- API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes
