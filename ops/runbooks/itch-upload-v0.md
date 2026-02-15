# itch.io Upload Runbook — Spell Cascade v0.1.0

## Prerequisites

- [x] Windows zip: `dist/spell-cascade-v0.1.0-win.zip` (30.1 MB)
- [x] Web export: `exports/web/` (SpellCascade.html + .wasm + .pck + .js)
- [x] Marketing copy: `ops/marketing/spell-cascade-itch-page-v0.md`
- [x] Screenshots: 5 images in `marketing/screenshot_*.png`
- [ ] itch.io login (yurukusa account, CDP automation)
- [ ] Cover image for itch.io page

## Step 1: Login to itch.io

```
1. chrome-auto (ensure port 9222 up)
2. cdp-eval -e "window.location.href = 'https://itch.io/login'"
3. Wait 5s
4. Fill username: yurukusa
5. Fill password: (from ~/.credentials)
6. Submit login form
7. Verify: check for dashboard link or profile
```

Note: If CAPTCHA appears → pending_for_human.md immediately.

## Step 2: Create New Game Page

```
1. Navigate: https://itch.io/game/new
2. Wait for form to load
3. Fill fields:
   - Title: "Spell Cascade"
   - Project URL: spell-cascade (auto-slugged)
   - Short description / tagline: "Build your spell loadout. Survive 10 minutes. Cascade your power."
   - Classification: Game
   - Kind of project: HTML (for web playable)
   - Pricing: $0 or more (Name Your Price)
   - Uploads: Windows zip + Web build
   - Description (body): Full feature bullets + controls + honest context from itch-page-v0.md
   - Genre: Action
   - Tags: survivor, top-down-shooter, roguelite, build-crafting, ai-made, godot, 10-minutes
```

## Step 3: Upload Files

### Web Build (playable in browser)
- Navigate to uploads section
- Upload the following files from exports/web/:
  - SpellCascade.html
  - SpellCascade.js
  - SpellCascade.wasm
  - SpellCascade.pck
- Mark as "This file will be played in the browser"

### Windows Build
- Upload `dist/spell-cascade-v0.1.0-win.zip`
- Mark platform: Windows
- NOT played in browser

## Step 4: Upload Screenshots

Upload 5 screenshots from marketing/:
1. screenshot_title.png — Cover/first screenshot
2. screenshot_gameplay_early.png
3. screenshot_combat.png
4. screenshot_boss.png
5. screenshot_settings.png

## Step 5: Cover Image

Need a 630x500 cover image. Options:
- Use screenshot_title.png cropped/resized
- Use main_capsule.png (616x353) — close but wrong aspect ratio
- Generate via Pillow: composite title text over gameplay background

## Step 6: Publish

1. Set visibility: Public
2. Click "Save & view page"
3. Verify page renders correctly
4. Take screenshot of live page for verification

## Step 7: Post-Publish Verification

- [ ] Page is accessible at https://yurukusa.itch.io/spell-cascade
- [ ] Web build loads and plays in browser
- [ ] Windows download link works
- [ ] Screenshots display correctly
- [ ] Pricing shows "Name your own price" with $0 minimum
- [ ] Tags appear on page

## CDP Technical Notes

- All CDP operations via `cdp-eval` (NOT raw WebSocket)
- itch.io uses Redactor for rich text editing (contenteditable div)
- File upload: May need PowerShell-based file dialog automation
- CSRF token present in forms — extract before submit
- Previous itch.io game ID (Azure Flame Dungeon): 4254604
- Spell Cascade will get a NEW game ID

## Fallback

If CDP automation fails at any step:
1. Record exact failure point in pending_for_human.md
2. Provide ぐらす with: URL, field values, files to upload
3. All content is ready — manual upload would take 5 min
