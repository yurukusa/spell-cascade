# Playtest Analysis Log

## 2026-02-16 01:30 JST - Code-Based Balance Analysis

### Critical Issues (Must Fix)

1. **Boss is unreachable**: 200m = 10min pure movement, game ends at 10min. 99% of runs never see the boss.
   - Fix: Reduce to 100m (~500s with upgrades)

2. **Dead zone 120-225s**: Enemies scale faster than upgrades arrive. Feels like running in place.
   - Fix: Already have guaranteed chain/fork/pierce at 10m. Consider tighter upgrade schedule.

3. **Late-game crush hell (400s+)**: Spawn rate 0.4s + manual movement = constant crush cycles.
   - Fix: Offer Move AI chip earlier (upgrade 3 instead of rare drop)

4. **Upgrade feast→famine**: Upgrades 1-3 in 225s, then gaps of 125s+. Upgrades 6-10 unreachable.
   - Fix: Rescale distances: [10, 25, 40, 55, 75, 95, 120, 150, 180, 220]

### Feel Issues (Should Fix)

5. **No "skill moment" between upgrades**: Long stretches of "just survive"
6. **Cooldown scaling weak**: Even 2 cooldown picks = 1.56x, underwhelming
7. **Boss at late-game is overwhelming**: 8-16 burst bullets + charge on top of heavy spawn

### What Works Well

- Crush system: warning → danger → breakout burst loop is engaging
- Kill VFX: hitstop + scaled explosions feel good
- Combo system: tier labels (RAMPAGE, MASSACRE, GODLIKE) give dopamine hits
- Upgrade UI: clear choices with immediate impact
- HP bar: smooth color change communicates urgency

### Balance Numbers

| Time | Spawn Rate | Enemy HP | Player DPS (est) | Crush Risk |
|------|-----------|----------|------------------|------------|
| 0s   | 1.5s      | 25       | 25               | <10%       |
| 60s  | 1.4s      | 26       | 25               | <10%       |
| 120s | 1.3s      | 27       | 30+              | 15%        |
| 300s | 0.9s      | 30       | 40-60            | 50%        |
| 600s | 0.4s      | 35       | 80-120           | 80%+       |
