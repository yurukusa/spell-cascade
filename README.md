# Spell Cascade

**Build your spell loadout. Survive 10 minutes. Cascade your power.**

A top-down survival shooter where your build choices matter. Equip attack chips, survive waves of enemies, make trade-off decisions at shrines, and take down a 3-phase boss.

## Quick Start

### Windows

1. Download `SpellCascade-win.zip` from [Releases](https://github.com/yurukusa/spell-cascade/releases) or [itch.io](https://yurukusa.itch.io/spell-cascade)
2. Extract the zip
3. Run `SpellCascade.exe`

### Web

Play directly in your browser on [itch.io](https://yurukusa.itch.io/spell-cascade).

## Controls

| Input | Action |
|-------|--------|
| WASD / Arrow Keys | Move |
| Mouse | Aim (tower faces cursor) |
| Auto | Attacks fire automatically |
| ESC | Pause / Settings |
| R | Restart (after game over) |
| T | Return to Title (after game over) |

## Build from Source

Requires [Godot 4.3](https://godotengine.org/download/).

```bash
git clone https://github.com/yurukusa/spell-cascade.git
cd spell-cascade
godot --path . --editor   # Open in editor
godot --path .            # Run directly
```

### Export

See [Export Runbook](ops/runbooks/spell-cascade-export-v0.md) for full export instructions.

```bash
# Windows
godot --headless --export-release "Windows Desktop" exports/windows/SpellCascade.exe

# Web
godot --headless --export-release "Web" exports/web/SpellCascade.html
```

## Version

Current: **v0.3.1** (see [VERSION](VERSION))

## Known Issues

- Placeholder visuals (geometric shapes + Kenney pixel sprites)
- No music (SFX only, procedurally generated)
- Boss kill time is ~60s (target was 90-180s)
- Web: Quit button has no effect (browser limitation)

## Credits

See [CREDITS.md](CREDITS.md) and [THIRDPARTY.md](THIRDPARTY.md).

## License

[MIT](LICENSE)
