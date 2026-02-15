# GIF Recording & itch.io Upload Tools

Scripts for capturing gameplay GIFs and uploading to itch.io screenshot gallery via CDP.

## Recording Pipeline

### 1. Record gameplay GIF
```bash
# All-in-one: starts game, auto-clicks upgrades, captures 40 frames, converts to GIF
powershell.exe -ExecutionPolicy Bypass -File '\\wsl.localhost\Ubuntu\home\namakusa\projects\spell-cascade\tools\record_gif\gif-record-v2.ps1'
```

This script:
- Connects to CC Chrome (CDP port 9222)
- Navigates to the game page
- Clicks "Play" to start
- Auto-clicks first upgrade option every 8 seconds
- After 15s warmup, captures 40 PNG frames (1 per 250ms)
- Saves frames as `/tmp/gif_frame_*.png`

### 2. Convert frames to GIF
```bash
python3 -c "
from PIL import Image
import glob
frames = sorted(glob.glob('/tmp/gif_frame_*.png'))
imgs = [Image.open(f).resize((640, int(640*Image.open(f).height/Image.open(f).width))) for f in frames]
imgs[0].save('marketing/gameplay.gif', save_all=True, append_images=imgs[1:], duration=250, loop=0, optimize=True)
"
```

### 3. Upload GIF to itch.io
```bash
# Click "Add screenshots" button
cdp-eval -f tools/record_gif/click-add-screenshot.js

# Set the file on the hidden input
CONSENSUS_ID=<stamp> FACTCHECK_ID=<stamp> powershell.exe -ExecutionPolicy Bypass -File '\\wsl.localhost\Ubuntu\home\namakusa\projects\spell-cascade\tools\record_gif\set-gif-file.ps1'

# Save the page
CONSENSUS_ID=<stamp> FACTCHECK_ID=<stamp> cdp-eval -f tools/record_gif/save-itch-page.js
```

## Files

| File | Purpose |
|------|---------|
| `gif-record-v2.ps1` | Main recording script (CDP screenshot capture) |
| `capture-gif-frames.ps1` | Standalone frame capture (no game start) |
| `auto-click-loop.js` | Auto-click first upgrade option |
| `start-and-play.js` | Navigate to game and click Play |
| `set-gif-file.ps1` | Upload GIF via DOM.setFileInputFiles |
| `click-add-screenshot.js` | Click "Add screenshots" on itch.io edit page |
| `find-screenshot-upload.js` | Debug: find screenshot-related elements |
| `check-screenshot-state.js` | Debug: check upload status |
| `save-itch-page.js` | Click Save on itch.io edit page |

## Notes
- Requires CC Chrome running on CDP port 9222
- itch.io scripts require consensus + factcheck stamps
- GIF target: <1MB, 640px wide, 10-12s loop, 250ms frame delay
- Current GIF: `marketing/gameplay.gif` (0.4MB, 40 frames)
