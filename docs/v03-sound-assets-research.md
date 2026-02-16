# Spell Cascade v0.3 Sound & Music Assets Research
Date: 2026-02-16
Task: explore-spell-cascade-v03-sound-assets

## 最小構成（即ダウンロード可能）

### BGM（4トラック必要）

| 用途 | 推奨 | ライセンス | ソース |
|------|------|-----------|--------|
| Gameplay loop | Fast Fight Battle Music (looped) | CC0 | [OpenGameArt](https://opengameart.org/content/fast-fight-battle-music-looped) |
| Title screen | CC0 Fantasy Music & Sounds collection | CC0 | [OpenGameArt](https://opengameart.org/content/cc0-fantasy-music-sounds) |
| Boss fight | 16+ Boss Battle Tracks (Towball) | CC-BY 4.0 | [itch.io](https://towball.itch.io/15-royalty-free-boss-fight) |
| Game over | Game Over Theme (No Hope) | CC0 | [OpenGameArt](https://opengameart.org/content/game-over-theme) |

### UI Sound Effects

| 推奨パック | 内容 | ライセンス | ソース |
|-----------|------|-----------|--------|
| Interface SFX Pack 1 (ObsydianX) | 200+ UI音 (confirm/back/cursor/error) | CC0 | [itch.io](https://obsydianx.itch.io/interface-sfx-pack-1) |
| Kenney UI Audio | 50音 (click/switch/select) | CC0 | [Kenney.nl](https://kenney.nl/assets/ui-audio) |

### Special Effects

| 推奨パック | 内容 | ライセンス | ソース |
|-----------|------|-----------|--------|
| 80 CC0 RPG SFX (rubberduck) | creature roar, spells, items, chains | CC0 | [OpenGameArt](https://opengameart.org/content/80-cc0-rpg-sfx) |
| Fantasy Ambient SFX (kmontesdev) | 2GB: ambience, monsters, spells | CC0 | [itch.io](https://kmontesdev.itch.io/fantasy-ambient-sound-effects-pack-cc0) |

## Godot 4 統合ノート

- **推奨フォーマット**: OGG Vorbis（Godot 4ネイティブ、WAVより小さい）
- **WAV→OGG変換**: `ffmpeg -i input.wav -c:a libvorbis -q:a 6 output.ogg`
- **BGMはストリーミング**: AudioStreamOGGVorbis + loop=true
- **SEはプリロード**: AudioStreamWAV or short OGG

## ディレクトリ構造案

```
res://assets/audio/
├── bgm/
│   ├── gameplay_loop.ogg
│   ├── title_screen.ogg
│   ├── boss_fight.ogg
│   └── game_over.ogg
├── sfx/
│   ├── ui/
│   │   ├── button_click.ogg
│   │   ├── menu_open.ogg
│   │   ├── confirm.ogg
│   │   └── cancel.ogg
│   └── special/
│       ├── boss_entrance.ogg
│       ├── wave_clear.ogg
│       └── achievement.ogg
└── ambient/
    └── dungeon_hum.ogg
```

## サイズ影響（HTML5エクスポート）

現在の.pck: 282 KB（マーケティング除外後）
BGM 4トラック（OGG, 各~1MB）: +4 MB
SE 20ファイル（OGG, 各~50KB）: +1 MB
**予想 .pck: ~5.3 MB → gzip ~5 MB**
**予想合計 gzip: ~12.7 MB**（wasmは変わらず7.7MB）

⚠️ Poki向けには音声ファイルの品質/ビットレートを下げる必要あり

## ライセンスまとめ

| License | 帰属表示 | 商用利用 | 該当アセット |
|---------|---------|---------|-------------|
| CC0 | 不要 | OK | 大半のアセット |
| CC-BY 4.0 | 必要 | OK | Boss Battle Tracks (Towball) |
| CC-BY-SA 3.0 | 必要+SA | OK | DarkWinds (バックアップ候補のみ) |

CC-BY使用時はクレジット画面に帰属表示を追加すること。
