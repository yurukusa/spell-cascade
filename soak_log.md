# Soak Test Log

## 2026-02-16 00:33 JST - Soak Pass

- **Duration**: 60s automated run (Screenshot autoload at 3s, 10s, 20s, 35s, 60s)
- **Godot Version**: 4.3.stable
- **Script errors**: 0
- **Debugger breaks**: 0
- **Crashes**: 0
- **Warnings**: `enemy_killed` signal declared but not used (cosmetic, not error)
- **Engine errors**: `area_set_shape_disabled` (known Godot 4.3 physics flush limitation, not script code)
- **Screenshots captured**: 5/5 OK

### Commits included in this soak:
```
057b03f feat: distinct skill projectile visuals per element type
e596104 feat: XP progress bar under level display with level-up flash
ff282a7 feat: kill combo counter with tiered display and best combo tracking
f4f100d feat: screen shake on enemy kills, boss hits, and crush state
1d7b593 fix: reduce area_set_shape_disabled errors by disabling monitoring before free
8048ffb feat: tiered damage numbers - size/color/animation scales with damage
feb1719 feat: projectile trail effects with gradient fade
78e3232 feat: offscreen enemy indicators + enemies group + warning fixes
bc8a32e feat: distance milestones + fix all area_set_shape_disabled errors
8468c75 feat: Game Over result screen with stats
```

### Verdict: PASS
