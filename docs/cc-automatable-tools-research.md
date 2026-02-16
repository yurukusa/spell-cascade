# CC自律運用可能なゲーム開発ツール調査

Date: 2026-02-16
Context: ゲームファクトリー構想 — 人間操作不要のツールのみ

## 選定基準（ハードゲート）

- **Recurring human touch: NO** — 毎回の使用に人間操作が不要
- API/CLI/MCP完結でCCが自律運用できること
- GUIのみのツールは候補外

---

## Tier 1: 即時利用可能（無料、インストールのみ）

| ツール | 用途 | 自律度 |
|--------|------|--------|
| **pyfxr** (`pip install pyfxr`) | sfxr互換の音声合成 | 完全自律 |
| **noise** (`pip install noise`) | Perlin/Simplexノイズ→テクスチャ | 完全自律 |
| **SoX** (`apt install sox`) | CLI音声合成・加工 | 完全自律 |
| **ImageMagick** (`apt install imagemagick`) | 画像加工・パターン生成 | 完全自律 |
| **Pillow + NumPy** (インストール済み) | スプライト生成・加工 | 完全自律 |
| **Python wave** (標準ライブラリ) | WAV直接生成 | 完全自律 |
| **Kenney Fonts** (wget) | CC0フォント | 完全自律 |

## Tier 2: 小投資・高リターン

| ツール | 価格 | 用途 | 自律度 | 備考 |
|--------|------|------|--------|------|
| **PixelLab MCP** | $24/月 | ピクセルアート生成 | 完全自律 | MCP Server直結。キャラ/アニメ/タイルセット。無料トライアル40回 |
| **Retro Diffusion (Replicate)** | ~$0.01-0.05/画像 | ピクセルスプライト生成 | 完全自律 | グリッド整列・パレット制限付きのAI生成。rd-fast/rd-plus/rd-animation |
| **Aseprite + pixel-mcp** | $20 買切り | ピクセルアート制作パイプライン | 完全自律 | MCP経由で40+ツール。スプライトシート出力。CLI batch mode |

## 不適格（却下済み）

| ツール | 理由 |
|--------|------|
| **PixelComposer** | GUIのみ。Recurring human touch: YES |
| **CryPixels GUI** | GUIのみ |
| **Local Stable Diffusion** | GPU未搭載環境 |
| **Bfxr/jsfxr web版** | ブラウザのみ、CLI未対応 |

---

## 推奨アクション

### 今すぐ（コスト0）
```bash
pip install pyfxr noise pydub
sudo apt install -y sox imagemagick
```

### 要決裁
- PixelLab MCP ($24/月) → pending_for_human.md に起票
- Aseprite ($20 買切り) → pending_for_human.md に起票
