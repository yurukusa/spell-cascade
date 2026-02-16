# GameDistribution Submit Readiness: 20→6→3→1

Date: 2026-02-16
Task: explore-spell-cascade-gamedistribution-submit-readiness-20-6-3-1

## Context
GameDistribution = 2nd priority distribution channel (after CrazyGames).
Auto-distributes to 4800+ publisher sites. Ad-based revenue (min €100 payout).

## Key Requirements Discovered
- Account: Google OAuth supported
- Package: ZIP renamed to `.html5`, standard HTML5 export
- SDK: Required for monetization (JS loader + ad calls)
- Review: "Request Activation" → email approval (1-7 days typical)
- Ad types: Rewarded, Interstitial, Display banner

## 20 Preparation Steps (brainstorm)

1. Create GameDistribution developer account (Google OAuth)
2. Register game in portal (get Game ID + User ID)
3. Add GD SDK script tag to SpellCascade.html
4. Initialize SDK with Game ID/User ID
5. Implement rewarded ad at game over
6. Implement interstitial ad between runs
7. Implement display banner ad
8. Add ad pause/resume logic (game pauses during ads)
9. Create game thumbnail/cover image
10. Fill metadata form (title, category, description)
11. Test in portal iframe viewer
12. Complete quality checklist
13. Rename ZIP to .html5
14. Upload to portal
15. Click "Request Activation"
16. Write AI disclosure note
17. Test sound preferences persistence
18. Test language settings persistence
19. Add FPS counter for stability proof
20. Create marketing screenshots for portal

## Narrowed to 6

### Cut reasons:
- 7 (Display banner): Optional, adds UI clutter, skip for v1
- 9 (Thumbnail): Can reuse autotest screenshot or itch.io assets
- 17 (Sound prefs): Not yet implemented in game (future feature)
- 18 (Language): Not yet i18n'd (English only)
- 19 (FPS counter): Godot's built-in FPS is sufficient
- 20 (Marketing screenshots): Can use existing autotest screenshots
- 5 (Rewarded ad): Requires game design for "what does ad give?" — defer
- 8 (Pause logic): Simple but blocks on SDK integration
- 11 (Iframe test): Happens after upload
- 12 (Quality checklist): Happens after upload
- 14 (Upload): Depends on all other steps
- 15 (Activate): Final step
- 16 (AI disclosure): Simple text addition

### Kept (ordered):
1. **Create account + register game** — Get Game ID/User ID
2. **Add SDK to HTML** — Script tag + init code
3. **Implement interstitial ad** — At game over (natural pause point)
4. **Package + rename** — ZIP → .html5
5. **Fill metadata + upload** — Portal form completion
6. **Request Activation** — Submit for review

## Narrowed to 3

### Cut reasons:
- 1 (Account): Just OAuth login, trivial
- 5 (Metadata): Form filling, mechanical
- 6 (Activate): Button click

### THE THREE (technical work needed):
1. **Add SDK to HTML** — Inject GD loader script + init in SpellCascade.html
2. **Implement interstitial ad** — Game over screen → show ad before retry
3. **Package + rename** — Re-export with SDK → ZIP → rename .html5

## THE ONE

**Add SDK to HTML** — This is the only true blocker.

Without the SDK, GameDistribution won't distribute (no monetization = no incentive
for publishers). The SDK integration is minimal:
```html
<script src="https://cdn.gamedistribution.com/html5/gd.js"></script>
<script>
var gameDistributionSettings = {
  gameId: "GAME_ID_FROM_PORTAL",
  userId: "USER_ID_FROM_PORTAL"
};
</script>
```

This single addition unlocks the entire 4800+ publisher network.

## Dependency Chain
```
Account creation (Google OAuth) → Get Game/User ID → SDK integration →
Package → Upload → Activate → Review (1-7 days)
```

## Effort Estimate
- Total: ~1-2 hours (account + SDK + package + submit)
- Blocker: Need ぐらす approval (external/public action, same as CrazyGames)

## Status
BLOCKED: Waiting for CrazyGames approval decision from ぐらす.
When approved, GameDistribution can be submitted in parallel.
