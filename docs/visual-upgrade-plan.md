# Spell Cascade Visual Upgrade Plan

**Date**: 2026-02-19
**Author**: designer (factory team)
**Status**: Analysis complete, ready for builder implementation

---

## Deliverables (this package)

| File | Description |
|------|------------|
| `docs/visual-quality-analysis-v083.md` | Full 30+ item analysis with VS genre comparison |
| `docs/visual-upgrade-plan.md` | This file — executive summary and implementation guide |
| `docs/mockups/before_after_comparison.png` | Side-by-side visual target |
| `docs/mockups/current_state.png` | Current state reference |
| `docs/mockups/target_state.png` | Target state reference |
| `memory/game-design-knowledge.md` | Updated with "ビジュアル品質基準" section |
| `docs/sprite-mapping.md` | **Exact sprite file selections with verified paths** |

---

## ⚠️ ASSET PATH CORRECTION (2026-02-19 designer verified)

The original plan referenced `roguelike-rpg-pack/` and `top-down-shooter/` paths.
**These DO NOT EXIST in this project.** See `docs/sprite-mapping.md` for verified paths.

Actual asset packs available (on `master` branch):
- `assets/kenney-tiny-dungeon/` — 132 tiles (16x16) ← **PRIMARY SOURCE**
- `assets/sprites/kenney/micro-roguelike/` — 80 tiles (16x16)
- `assets/sprites/generated/` — 5 enemy + 6 projectile sprites

---

## CRITICAL 5 Fixes (Task #27)

These 5 changes will transform the game from "prototype" to "real game" appearance.
**Full sprite selections with exact paths → `docs/sprite-mapping.md`**

### 1. Remove Debug Text Panel
**What**: Delete left-side "Move: Kite | Aim: Nearest | Trigger: Auto Cast / Bullets: x1 / Kills: 0 / [1] Fireball (1.2s) / [2] empty / [3] empty"
**Why**: This is developer-facing debug info. No shipped VS game exposes internals to players.
**How**: Find the `Label` or `RichTextLabel` nodes that render this. Set `visible = false` or remove from scene tree. If useful for development, wrap in `if OS.is_debug_build():`.

### 2. Replace Enemy Red Squares with Kenney Sprites
**What**: Swap `ColorRect`/`Polygon2D` enemy visuals with actual sprite assets.
**Assets**: `assets/kenney-tiny-dungeon/` — Slime (tile_0108), Demon (tile_0110), Beast (tile_0112), Skeleton (tile_0121)
**How**: Add `Sprite2D` node to enemy scene, load texture. Scale 16x16 to 32x32 with `texture_filter = NEAREST`.

### 3. Replace Player Circle with Character Sprite
**What**: The player is currently a ~30px circle with a blue dot. Replace with a character sprite.
**Assets**: `assets/kenney-tiny-dungeon/tile_0100.png` — Blue/gray armored knight
**How**: Add `Sprite2D`, load texture, set `texture_filter = NEAREST`. Add 1px outline for visibility.

### 4. Make Projectiles 2-3x Larger and Brighter
**What**: Current fireballs are ~8px tiny circles, nearly invisible on dark backgrounds.
**Assets**: Existing `assets/sprites/generated/projectile_fire_000-002.png` and `projectile_ice_000-002.png`
**How**: Scale sprite 2-3x. Add `PointLight2D` (energy 0.4, radius 32px). Add trail via `Line2D` or `GPUParticles2D`.

### 5. Add Tiled Ground Texture
**What**: Replace flat single-color backgrounds with tiled ground.
**Assets**: `assets/kenney-tiny-dungeon/tile_0036.png` through `tile_0039.png` — 4 gray stone variants
**How**: Add `TileMapLayer` behind game objects. Create `TileSet` with 4 ground variants, weighted random (60/20/10/10). Apply dark purple/green modulate to match game palette.

---

## Quick Reference: Verified Asset Locations

```
assets/kenney-tiny-dungeon/           ← PRIMARY (132 individual 16x16 PNGs)
├── tile_0000-0050.png                 Ground, walls, structures
├── tile_0060-0095.png                 Furniture, objects, decorations
├── tile_0096-0100.png                 Player characters (heroes)
├── tile_0101-0107.png                 Items (potions, shields)
└── tile_0108-0131.png                 Enemies (slimes, demons, skeletons, etc.)

assets/sprites/kenney/micro-roguelike/ ← SECONDARY
└── Tiles/Colored/tile_0000-0079.png   Additional character/tile variety

assets/sprites/generated/              ← EXISTING PROJECTILES
├── enemy_fire_000-004.png             Abstract fire enemy sprites (5)
├── projectile_fire_000-002.png        Orange circle projectiles (3 frames)
└── projectile_ice_000-002.png         Blue circle projectiles (3 frames)
```

---

## Implementation Order

1. ~~**Task #20 first** (HTML5 fix)~~ ✅ DONE
2. **Task #27** (CRITICAL 5 — use `docs/sprite-mapping.md` for exact sprite paths)
3. Future: HIGH priority items from `visual-quality-analysis-v083.md` (hit flash, death particles, projectile trails, UI styling, etc.)
