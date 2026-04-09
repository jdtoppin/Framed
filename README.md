# Framed

Modern, customizable unit frames and raid frames for World of Warcraft (Retail).

Built on [oUF](https://github.com/oUF-wow/oUF).

## Features

- Player, Target, Target of Target, Focus, Pet, Party, Raid, Boss, and Arena frames
- Fully configurable health, power, cast bars, and name text
- Aura indicators: buffs, debuffs, defensives, externals, dispellable, missing buffs, private auras, targeted spells
- Custom indicator system: icons, bars, border glows, color overlays, and border icons
- Click casting with per-spec defaults
- Preset system with content-based auto-switching (raid, dungeon, PvP)
- Drag-and-drop edit mode with snap-to-grid and alignment guides
- Profile import/export
- Secret value safe — works correctly in combat

## Installation

Download the latest release from the [Releases](https://github.com/jdtoppin/Framed/releases) page and extract into your `World of Warcraft/_retail_/Interface/AddOns/` folder.

## Usage

- `/framed` or `/fr` — Open settings
- `/framed edit` — Toggle edit mode
- `/framed help` — Show all commands

## Development

Run the local lint check with:

```bash
luacheck . --config .luacheckrc
```

If `luacheck` is not installed yet, one option is:

```bash
luarocks --lua-version=5.1 install luacheck
```

GitHub Actions runs the same check on pushes to `main` and on pull requests.

## License

GPL v3. See [LICENSE](LICENSE) for details.

oUF is licensed under MIT. See `Libs/oUF/LICENSE` for details.
