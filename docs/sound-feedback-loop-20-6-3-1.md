# Sound Feedback Loop Design: 20→6→3→1

Date: 2026-02-16
Task: explore-spell-cascade-sound-feedback-loop-20-6-3-1

## Current Sound Inventory (11 sounds)
1. Shot (0.08s chirp) — fire projectile
2. Hit (0.06s impact) — damage enemy
3. Kill (0.2s pop+sparkle) — enemy dies
4. UI Select (0.1s blip) — menu confirm
5. Low HP Warning (0.3s pulse) — danger
6. Level Up (0.35s arpeggio) — player grew
7. XP Pickup (0.05s blip + pitch streak) — collect orb
8. BGM (8s loop) — ambient
9. Wave Clear (0.4s fanfare) — milestone/boss kill
10. Boss Entrance (0.6s impact) — boss spawns
11. UI Cancel (0.08s descending blip) — pause/back

## 20 Candidates (brainstorm)

1. **Player Damage Taken** — flash + crunch when tower hit
2. **Upgrade Acquired** — satisfying confirmation after choosing upgrade
3. **Critical Hit** — louder/deeper hit for high-damage instances
4. **Crush Warning Escalation** — intensifying pulse as crush activates
5. **Breakout Explosion** — dramatic burst when crush breakout triggers
6. **Combo Tier Up** — ascending chime when combo reaches 3/8/15/30
7. **Shield/Regen Tick** — soft pulse when HP regenerates
8. **Shrine Appear** — mystical chime for mid-game shrine event
9. **Near-Death Heartbeat** — rhythmic pulse at <10% HP
10. **Skill Swap Confirmation** — distinct from upgrade, more "click/lock"
11. **BGM Intensity Layer** — procedural BPM/filter change at high enemy count
12. **Projectile Bounce/Chain** — trailing ping when chain/fork fires
13. **Enemy Spawn Warning** — subtle whoosh for off-screen spawns
14. **Game Over Stinger** — dramatic defeat sound
15. **Victory Fanfare** — celebratory end-game music
16. **Treasure/Rare Drop** — sparkling sound for rare events
17. **Speed Boost** — whoosh when move speed increases
18. **Cooldown Ready** — subtle click when skill comes off cooldown
19. **Phase Transition** — ominous tone shift for boss phase changes
20. **Menu Open/Close** — ambient whoosh for pause menu transitions

## Narrowed to 6

### Cut reasons:
- 3 (Critical Hit): Hit already has ±15% pitch variation, diminishing returns
- 7 (Regen Tick): No regen mechanic currently in game
- 9 (Heartbeat): Low HP Warning already covers this; overlap
- 11 (BGM Intensity): Complex CPU cost, deferred to v0.4
- 12 (Chain Ping): Too frequent, would create noise wall with shot+hit
- 13 (Spawn Warning): Off-screen indicators already visual; redundant
- 17 (Speed Boost): Rare event, low impact per-play
- 18 (Cooldown Ready): Too frequent at high fire rates
- 10 (Skill Swap): Same UI context as Upgrade Acquired
- 16 (Treasure Drop): No treasure mechanic yet
- 8 (Shrine): Only triggers once per run at 2:30; very low frequency
- 20 (Menu Open): Minimal player impact
- 19 (Phase Transition): Boss phases are rare; visual already handles this
- 5 (Breakout): Could merge with Wave Clear; similar "victory" moment

### Kept:
1. **Player Damage Taken** — Critical feedback gap. Players can't feel when they're hit
2. **Upgrade Acquired** — The dopamine moment. Choosing upgrade needs its own satisfaction
3. **Combo Tier Up** — Rewards sustained kill streaks (core engagement loop)
4. **Crush Warning Escalation** — Crush is the most dangerous mechanic; needs audio
5. **Game Over Stinger** — End of run needs emotional punctuation
6. **Victory Fanfare** — Winning needs celebration

## Narrowed to 3

### Cut reasons:
- 5 (Game Over): Player already knows they died; cosmetic, not feedback
- 6 (Victory): Same — cosmetic endpoint, not gameplay feedback
- 4 (Crush Escalation): Crush visual + warning label already communicate danger

### THE THREE:
1. **Player Damage Taken** — 0.12s metallic crunch/thud
   - WHY: The #1 missing feedback. Every survival game needs "I just got hit" audio
   - WHERE: `_on_tower_damaged()` in game_main.gd (only when HP decreases)
   - DESIGN: Low-freq impact (100-200Hz) + high click (2kHz), short decay

2. **Upgrade Acquired** — 0.25s ascending shimmer
   - WHY: The reward confirmation. VS-like core loop = power trip
   - WHERE: `_on_upgrade_chosen()` in game_main.gd
   - DESIGN: Rising sweep (400→1200Hz) + sparkle harmonics, bright tone

3. **Combo Tier Up** — 0.15s ascending chime per tier
   - WHY: Combos reward sustained play. Audio makes streaks feel earned
   - WHERE: `_update_combo_display()` when combo_count hits [3, 8, 15, 30]
   - DESIGN: Single bell tone, pitch increases per tier (C5→E5→G5→C6)

## THE ONE (highest ROI single addition)

**Player Damage Taken** — 0.12s

This is the single biggest gap in the current sound design. Without it:
- Players don't feel urgency when surrounded
- Crush mechanic loses tension
- HP bar changes go unnoticed during intense play
- The survival aspect has no audio feedback

Every VS-like game and action game has a damage-taken sound. It's the most fundamental game-feel sound after "I hit something."

## Mixing Rules (to implement alongside)

1. **Volume Priority**: Damage > Level Up > Boss > Kill > Hit > Shot
2. **BGM Ducking**: -6dB for 0.5s on Level Up, Boss Entrance, Wave Clear
3. **Frequency Separation**: Keep damage at 100-200Hz, kills at 300-600Hz, UI at 800-2000Hz
4. **Concurrent Limit**: Max 6 hit sounds, max 4 XP pickup sounds simultaneously
