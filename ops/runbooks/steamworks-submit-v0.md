# Steamworks Submission Checklist v0

## Prerequisites

- [ ] Steamworks developer account ($100 fee, one-time)
- [ ] App created in Steamworks (App ID assigned)
- [ ] Build artifacts ready: `dist/spell-cascade-v0.1.0-win.zip`

---

## 1. Store Page — Basic Info

Location: **Steamworks > App Admin > Store Page > Basic Info**

| Field | Value |
|-------|-------|
| App Type | Game |
| Name | Spell Cascade |
| Developer | yurukusa |
| Publisher | yurukusa |
| Release State | Coming Soon / Released |
| Supported Languages | English (Interface) |

## 2. Store Page — Description

Location: **Store Page > Description**

### Short Description (300 char max)

> A top-down survival shooter where your build choices matter. Equip attack chips, survive 10 minutes of escalating waves, and take down a 3-phase boss. Made entirely with AI pair programming.

### About This Game (long description)

Copy from: `ops/marketing/spell-cascade-steam-page-v0.md` → "About This Game" section.

## 3. Store Page — Graphical Assets

Location: **Store Page > Graphical Assets**

| Asset | Spec | Source File |
|-------|------|-------------|
| Header Capsule | 460x215 PNG | `marketing/header_capsule.png` |
| Small Capsule | 231x87 PNG | `marketing/small_capsule.png` |
| Main Capsule | 616x353 PNG | `marketing/main_capsule.png` |
| Hero Graphic | 3840x1240 PNG | `marketing/hero_graphic.png` |
| Screenshots (min 5) | 1280x720 PNG | `marketing/screenshot_title.png`, `screenshot_combat.png`, `screenshot_boss.png`, `screenshot_gameplay_early.png`, `screenshot_settings.png` |
| Trailer (optional) | MP4 | Not available yet |

## 4. Store Page — Tags & Categories

Location: **Store Page > Tags**

Apply these tags:
- Action
- Indie
- Top-Down Shooter
- Roguelite
- Survival
- Singleplayer
- Early Access (if applicable)

Genre: **Action**, **Indie**

## 5. System Requirements

Location: **Store Page > System Requirements**

### Minimum (Windows)

| Field | Value |
|-------|-------|
| OS | Windows 10 64-bit |
| Processor | Any x86_64 CPU |
| Memory | 2 GB RAM |
| Graphics | OpenGL 3.3 compatible |
| Storage | 100 MB |

## 6. Content Survey / Rating

Location: **Store Page > Content Survey**

| Question | Answer |
|----------|--------|
| Violence | No realistic violence (abstract shapes only) |
| Blood/Gore | None |
| Sexual Content | None |
| Language | None |
| Gambling | None |
| User-Generated Content | None |
| In-App Purchases | None |

Expected rating: **Everyone / PEGI 3**

## 7. Pricing

Location: **Store Page > Pricing**

| Field | Value |
|-------|-------|
| Price | Free to Play |
| DLC | None |
| Regional pricing | N/A (free) |

## 8. Build Upload (SteamPipe / Depot)

Location: **Steamworks > App Admin > SteamPipe > Depots**

### Option A: SteamPipe GUI (recommended for first time)

1. Download SteamPipe GUI from Steamworks docs
2. Set content root to extracted `dist/spell-cascade-v0.1.0-win.zip`
3. Upload to default depot

### Option B: CLI (steamcmd)

```bash
# content_builder/scripts/app_build_APPID.vdf
"AppBuild"
{
    "AppID" "YOUR_APP_ID"
    "Desc" "v0.1.0 initial upload"
    "ContentRoot" "./content/"
    "BuildOutput" "./output/"
    "Depots"
    {
        "YOUR_DEPOT_ID"
        {
            "FileMapping"
            {
                "LocalPath" "*"
                "DepotPath" "."
                "recursive" "1"
            }
        }
    }
}
```

Put `SpellCascade.exe` in `content/` and run:
```bash
steamcmd +login YOUR_LOGIN +run_app_build ./scripts/app_build_APPID.vdf +quit
```

### Set Build Live

1. Go to **SteamPipe > Builds**
2. Find your uploaded build
3. Set branch to `default`

## 9. Release Checklist (Final)

- [ ] Store page text filled (short + long description)
- [ ] All graphical assets uploaded (capsules, screenshots)
- [ ] System requirements filled
- [ ] Content survey completed
- [ ] Pricing set (Free)
- [ ] Build uploaded via SteamPipe
- [ ] Build set live on default branch
- [ ] **Test**: Install from Steam client and verify title screen → Play
- [ ] Click "Release" or set release date

## 10. Post-Release

- [ ] Verify store page is live and looks correct
- [ ] Test download from a second account
- [ ] Post announcement on Twitter (@yurukusa_dev)
- [ ] Update itch.io page with Steam link

---

## Files Reference

| Purpose | Path |
|---------|------|
| Steam page copy | `ops/marketing/spell-cascade-steam-page-v0.md` |
| itch.io page copy | `ops/marketing/spell-cascade-itch-page-v0.md` |
| Release notes | `ops/release-notes/spell-cascade-v0.1.0.md` |
| Windows zip | `dist/spell-cascade-v0.1.0-win.zip` |
| SHA256 hash | `dist/SHA256SUMS.txt` |
| Screenshots | `marketing/screenshot_*.png` |
| GIF | `marketing/gameplay.gif` |
| Credits | `CREDITS.md`, `THIRDPARTY.md` |
