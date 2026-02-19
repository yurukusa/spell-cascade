# Spell Cascade Sprite Mapping — Visual Upgrade (Task #27)

**Date**: 2026-02-19
**Author**: designer (factory team)
**Purpose**: Map specific sprite files to each visual fix in Task #27

---

## CRITICAL CORRECTION

The `visual-upgrade-plan.md` references `roguelike-rpg-pack/` and `top-down-shooter/` asset paths.
**These directories DO NOT EXIST in this project.** The subagent report was incorrect.

**Actual available asset packs (on `master` branch):**
```
assets/kenney-tiny-dungeon/          ← 132 tiles (16x16) — PRIMARY SOURCE
assets/sprites/kenney/micro-roguelike/ ← 80 tiles (16x16) — SECONDARY
assets/sprites/generated/             ← 5 enemy + 6 projectile sprites
```

All paths below are relative to project root on `master` branch.

---

## 1. PLAYER CHARACTER

| Priority | Tile | Path | Description |
|----------|------|------|-------------|
| **PRIMARY** | tile_0100 | `assets/kenney-tiny-dungeon/tile_0100.png` | Blue/gray armored knight. Clear humanoid silhouette, white outline, distinct from red/green enemies. Best color contrast for player identification. |
| ALT | tile_0098 | `assets/kenney-tiny-dungeon/tile_0098.png` | Brown-haired human character. More approachable/friendly look. |
| ALT | tile_0096 | `assets/kenney-tiny-dungeon/tile_0096.png` | Purple dark knight. Edgier aesthetic. |

**Implementation notes:**
- 16x16 native → scale to 32x32 with `texture_filter = NEAREST` for crisp pixel art
- Add 1px white outline shader or pre-baked outline for visibility against dark backgrounds
- Consider adding a subtle blue glow aura (PointLight2D, energy 0.2, radius 24px) for "hero" feel

---

## 2. ENEMIES (7 types — minimum 4 for CRITICAL fix)

Each enemy is visually distinct by color AND silhouette. Sorted by suggested game role.

| Role | Tile | Path | Visual | Color |
|------|------|------|--------|-------|
| **Slime (Basic)** | tile_0108 | `assets/kenney-tiny-dungeon/tile_0108.png` | Green blob creature | Green — classic starter enemy |
| **Demon (Elite)** | tile_0110 | `assets/kenney-tiny-dungeon/tile_0110.png` | Red horned demon | Red — menacing, clear threat |
| **Beast (Tank)** | tile_0112 | `assets/kenney-tiny-dungeon/tile_0112.png` | Orange/brown ogre | Orange — bulky, tanky feel |
| **Skeleton (Ranged)** | tile_0121 | `assets/kenney-tiny-dungeon/tile_0121.png` | White skull/skeleton | Pale — classic dungeon enemy |
| Goblin (Fast) | tile_0114 | `assets/kenney-tiny-dungeon/tile_0114.png` | Small green humanoid | Dark green — fast, sneaky |
| Ghost (Special) | tile_0119 | `assets/kenney-tiny-dungeon/tile_0119.png` | Pale ethereal spirit | Red/pale — unique silhouette |
| Boss Demon | tile_0120 | `assets/kenney-tiny-dungeon/tile_0120.png` | Large fierce demon | Orange/brown — boss variant |

**CRITICAL 4 (minimum for Task #27):** Slime, Demon, Beast, Skeleton — they cover green/red/orange/white = maximum visual variety.

**Implementation notes:**
- Same 16x16 → 32x32 NEAREST scaling
- Add white hit-flash shader (50ms on damage): `shader_parameter/flash_amount = 1.0` then tween to 0
- Add death particles: 6-8 particles matching enemy color, burst outward, fade over 300ms
- Enemy-specific scale: Boss Demon at 1.5x, Slime at 0.8x for size variety

---

## 3. GROUND TILES (Tiled floor)

| Variant | Tile | Path | Description |
|---------|------|------|-------------|
| **Stone A** | tile_0036 | `assets/kenney-tiny-dungeon/tile_0036.png` | Gray stone brick — primary ground |
| **Stone B** | tile_0037 | `assets/kenney-tiny-dungeon/tile_0037.png` | Slightly different gray stone |
| **Stone C** | tile_0038 | `assets/kenney-tiny-dungeon/tile_0038.png` | Another gray stone variant |
| **Stone D** | tile_0039 | `assets/kenney-tiny-dungeon/tile_0039.png` | Fourth gray stone variant |
| Earth A | tile_0000 | `assets/kenney-tiny-dungeon/tile_0000.png` | Brown earth/dirt (outdoor alternative) |
| Earth B | tile_0001 | `assets/kenney-tiny-dungeon/tile_0001.png` | Darker brown earth variant |
| Wall | tile_0040 | `assets/kenney-tiny-dungeon/tile_0040.png` | Blue-gray brick (for boundary walls) |

**Recommended approach:**
- Use `TileMapLayer` with `TileSet` resource containing tiles 0036-0039 as terrain variants
- Paint with weighted random: 60% Stone A, 20% Stone B, 10% Stone C, 10% Stone D
- This creates natural visual variation without repetitive tiling artifacts
- Tile size: 16x16 native, can scale TileMap node to 2x for 32x32 visual size
- **Color modulation**: Apply a slight dark purple/green tint (`modulate = Color(0.7, 0.8, 0.7)`) to match Spell Cascade's existing color scheme

---

## 4. PROJECTILES

| Type | Files | Path | Description |
|------|-------|------|-------------|
| **Fire** | 000-002 | `assets/sprites/generated/projectile_fire_000.png` through `002` | Orange circle (~8px) — 3 animation frames |
| **Ice** | 000-002 | `assets/sprites/generated/projectile_ice_000.png` through `002` | Blue circle (~8px) — 3 animation frames |

**These exist and are functional, but need visual enhancement:**
- Scale sprite 2-3x (from ~8px to 16-24px visible size)
- Add `PointLight2D` child: energy 0.4, radius 32px, color matching element
- Add trail: `GPUParticles2D` or `Line2D` behind projectile, 6-8 trail points, matching color with decreasing alpha
- Add impact burst on hit: 4-6 particles, bright center fading to element color

---

## 5. XP GEMS / PICKUPS

| Item | Tile | Path | Description |
|------|------|------|-------------|
| **XP Gem** | tile_0101 | `assets/kenney-tiny-dungeon/tile_0101.png` | Small dark item — recolor to bright blue/cyan |
| ALT | tile_0104 | `assets/kenney-tiny-dungeon/tile_0104.png` | Purple potion — could work as-is for magic theme |

**Implementation notes:**
- Apply bright cyan/blue `modulate` to make XP gems pop against dark ground
- Add pulsing animation: `scale` tween between 0.9 and 1.1, period 0.5s
- Add `PointLight2D` glow: energy 0.3, radius 16px, cyan color
- Pickup feedback: brief scale-up + particle burst when collected

---

## 6. ENVIRONMENT OBJECTS (decoration, not CRITICAL)

| Object | Tile | Path | Use |
|--------|------|------|-----|
| Chest | tile_0030 | `assets/kenney-tiny-dungeon/tile_0030.png` | Decorative ground object |
| Barrel | tile_0042 | `assets/kenney-tiny-dungeon/tile_0042.png` | Scatter on field edges |
| Door | tile_0043 | `assets/kenney-tiny-dungeon/tile_0043.png` | Arena boundary decoration |
| Bookshelf | tile_0070 | `assets/kenney-tiny-dungeon/tile_0070.png` | Environment variety |

---

## Asset Pack Reference

### Kenney Tiny Dungeon (PRIMARY — 132 tiles)
- All 16x16 pixel art, CC0 license
- Individual PNGs: `assets/kenney-tiny-dungeon/tile_NNNN.png`
- Characters: tiles 0096-0100
- Items: tiles 0101-0107
- Enemies: tiles 0108-0131
- Ground/walls: tiles 0000-0050
- Furniture/objects: tiles 0060-0095

### Kenney Micro-Roguelike (SECONDARY — 80 tiles)
- 16x16 colored tilemap: `assets/sprites/kenney/micro-roguelike/Tiles/Colored/tile_NNNN.png`
- Has additional character/enemy tiles that could supplement tiny-dungeon
- More stylized/abstract than tiny-dungeon

### Generated Sprites (existing)
- `assets/sprites/generated/enemy_fire_000-004.png` — Abstract fire pixel patterns (5 variants)
- `assets/sprites/generated/projectile_fire_000-002.png` — Orange circles (3 frames)
- `assets/sprites/generated/projectile_ice_000-002.png` — Blue circles (3 frames)

---

## Implementation Priority for Task #27

```
Step 1: Player sprite swap (tile_0100) — immediate visual impact
Step 2: Enemy sprite swap (4 types: 0108, 0110, 0112, 0121) — biggest "cheap" fix
Step 3: Ground tilemap (tiles 0036-0039) — removes flat background
Step 4: Projectile scaling + glow — makes combat readable
Step 5: Debug text removal — professional appearance
```

All sprites are already in the project repository on `master` branch. No external downloads needed.
