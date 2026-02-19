extends Node

## SFX — サウンドエフェクトマネージャー（Autoload）
## WAVファイルがあればロード、なければランタイムPCM生成にフォールバック。
## Why: pyfxr生成WAVはランタイム生成より音質が良い。フォールバックで堅牢性を確保。

const SOUNDS_DIR := "res://assets/sounds/"

# プレイヤープール
var _shot_players: Array[AudioStreamPlayer] = []
var _hit_players: Array[AudioStreamPlayer] = []
var _kill_player: AudioStreamPlayer
var _ui_select_player: AudioStreamPlayer
var _low_hp_player: AudioStreamPlayer
var _level_up_player: AudioStreamPlayer
var _xp_pickup_players: Array[AudioStreamPlayer] = []
const XP_PICKUP_POOL_SIZE := 4
var _xp_pickup_idx := 0
var _xp_pitch_streak := 0.0  # 連続回収でピッチが上がる（Mario coin効果）

const SHOT_POOL_SIZE := 4
const HIT_POOL_SIZE := 6
var _shot_idx := 0
var _hit_idx := 0

var _bgm_player: AudioStreamPlayer       # Battle BGM (Wave 1-15)
var _bgm_intense_player: AudioStreamPlayer  # Intense BGM (Wave 16+)
var _bgm_boss_player: AudioStreamPlayer     # Boss BGM
var _current_bgm: String = ""  # "battle", "intense", "boss"
var _wave_clear_player: AudioStreamPlayer
var _boss_entrance_player: AudioStreamPlayer
var _ui_cancel_player: AudioStreamPlayer
# 被弾は複数バリアント（4種）をプールして自然なバリエーション
var _damage_taken_players: Array[AudioStreamPlayer] = []
const DAMAGE_POOL_SIZE := 4
var _damage_idx := 0

var _low_hp_cooldown := 0.0
const LOW_HP_INTERVAL := 2.0
var _bgm_playing := false
var _damage_cooldown := 0.0
const DAMAGE_COOLDOWN := 0.15  # 被弾SE連続再生を制限（150ms間隔）
# 改善172: DoT tick SE（多数の敵が同時DoT時でも過剰にならないようglobal throttle）
var _dot_player: AudioStreamPlayer
var _dot_cooldown := 0.0
const DOT_COOLDOWN := 0.35  # 350ms以内は再生しない（連続DoTのノイズ抑制）
# 改善178: ゲームオーバーSE（低音下降スイープ + 残響）
# Why: BGM停止→無音のみでは敗北の「重さ」が伝わらない。"DOOM"感を音で完結させる。
var _game_over_player: AudioStreamPlayer
# 改善179: 勝利ファンファーレSE（上昇アルペジオ + 鐘残響）
# Why: ゲームオーバーに下降音があるなら、勝利に上昇ファンファーレが必要。喜びを音で完結させる。
var _victory_player: AudioStreamPlayer
# 改善180: ボス撃破専用SFX（爆発 + 残響クレッシェンド）
# Why: play_wave_clear()はウェーブ終了と同じ音。ボス撃破は最大の達成感なので専用音が必要。
var _boss_kill_player: AudioStreamPlayer
# 改善181: ボスフェーズ移行SFX（不協和スウェル + 金属打撃）
# Why: フェーズ移行は視覚・振動あり、音なし。「まだ続くのか」という恐怖感を音で演出。
var _boss_phase_player: AudioStreamPlayer
# 改善182: ステージ警告SFX（SURGE/CRISIS/FINAL PUSH — 3段階緊張音）
# Why: ステージ遷移は視覚+振動あり、音なし。「局面が変わった」を耳でも確認させる。
var _stage_alert_players: Array[AudioStreamPlayer] = []
# 改善174: コンボティアアップSE（COMBO=3/RAMPAGE=8/MASSACRE=15/GODLIKE=30）
# Why: 視覚的なスケールパンチ+リングに対応する音がなかった。達成感を音で確認させる。
var _combo_tier_players: Array[AudioStreamPlayer] = []
# 改善175: 回復SE（small/large 2段階、1.2sクールダウン）
# Why: heal VFXはあるが音がなかった。life stealは高頻度なのでスロットル必須。
var _heal_small_player: AudioStreamPlayer
var _heal_large_player: AudioStreamPlayer
var _heal_cooldown := 0.0
const HEAL_COOLDOWN := 1.2  # 1.2s以内は再生しない（life steal連打抑制）
const HEAL_LARGE_THRESHOLD := 50.0  # 大回復SFXの閾値

const SAMPLE_RATE := 22050

## WAVファイルロード: あればWAVを使い、なければnullを返す（呼び出し側でフォールバック）
func _try_load_wav(filename: String) -> AudioStream:
	var path := SOUNDS_DIR + filename
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _ready() -> void:
	# Shot: pyfxr WAV (laser_alt) があればそれ、なければ procedural
	var shot_stream: AudioStream = _try_load_wav("laser_alt.wav")
	if shot_stream == null:
		shot_stream = _gen_shot()
	for i in SHOT_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = shot_stream
		p.volume_db = -8.0   # v0.7.0: -6→-8（SFX全体を2dB下げてBGMとのバランス改善）
		add_child(p)
		_shot_players.append(p)

	var hit_stream := _gen_hit()
	for i in HIT_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = hit_stream
		p.volume_db = -10.0  # v0.7.0: -8→-10
		add_child(p)
		_hit_players.append(p)

	# Kill: pyfxr WAV (explosion) があればそれ、なければ procedural
	var kill_stream: AudioStream = _try_load_wav("explosion.wav")
	if kill_stream == null:
		kill_stream = _gen_kill()
	_kill_player = AudioStreamPlayer.new()
	_kill_player.stream = kill_stream
	_kill_player.volume_db = -5.0   # v0.7.0: -3→-5
	add_child(_kill_player)

	_ui_select_player = AudioStreamPlayer.new()
	_ui_select_player.stream = _gen_ui_select()
	_ui_select_player.volume_db = -4.0  # v0.7.0: -2→-4
	add_child(_ui_select_player)

	_low_hp_player = AudioStreamPlayer.new()
	_low_hp_player.stream = _gen_low_hp()
	_low_hp_player.volume_db = -4.0
	add_child(_low_hp_player)

	# 改善172: DoT tick SE（柔らかいジジジ音）
	_dot_player = AudioStreamPlayer.new()
	_dot_player.stream = _gen_dot()
	_dot_player.volume_db = -14.0  # 控えめ — DoTは補助フィードバック
	add_child(_dot_player)

	# Level Up: pyfxr WAV (upgrade_acquired) があればそれ、なければ procedural
	var lvl_stream: AudioStream = _try_load_wav("upgrade_acquired.wav")
	if lvl_stream == null:
		lvl_stream = _gen_level_up()
	_level_up_player = AudioStreamPlayer.new()
	_level_up_player.stream = lvl_stream
	_level_up_player.volume_db = -3.0   # v0.7.0: -2→-3（レベルアップは少し大きめを維持）
	add_child(_level_up_player)

	# XP Pickup: pyfxr WAV (xp_pickup_v1/v2) をプール、なければ procedural
	var xp_streams: Array[AudioStream] = []
	var xp_v1: AudioStream = _try_load_wav("xp_pickup_v1.wav")
	var xp_v2: AudioStream = _try_load_wav("xp_pickup_v2.wav")
	if xp_v1 != null:
		xp_streams.append(xp_v1)
	if xp_v2 != null:
		xp_streams.append(xp_v2)
	var xp_fallback: AudioStream = _gen_xp_pickup()
	for i in XP_PICKUP_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		if xp_streams.size() > 0:
			p.stream = xp_streams[i % xp_streams.size()]
		else:
			p.stream = xp_fallback
		p.volume_db = -10.0
		add_child(p)
		_xp_pickup_players.append(p)

	# v0.7.0: BGMを+4dB引き上げ（SFXとのバランス改善: -12→-8, -10→-6, -8→-4）
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.stream = _gen_bgm()
	_bgm_player.volume_db = -8.0   # v0.7.0: -12→-8
	add_child(_bgm_player)

	_bgm_intense_player = AudioStreamPlayer.new()
	_bgm_intense_player.stream = _gen_bgm_intense()
	_bgm_intense_player.volume_db = -6.0  # v0.7.0: -10→-6
	add_child(_bgm_intense_player)

	_bgm_boss_player = AudioStreamPlayer.new()
	_bgm_boss_player.stream = _gen_bgm_boss()
	_bgm_boss_player.volume_db = -4.0   # v0.7.0: -8→-4（ボスBGMは最も前面に）
	add_child(_bgm_boss_player)

	# Wave Clear: pyfxr WAV (combo_tierup) があればそれ、なければ procedural
	var wc_stream: AudioStream = _try_load_wav("combo_tierup.wav")
	if wc_stream == null:
		wc_stream = _gen_wave_clear()
	_wave_clear_player = AudioStreamPlayer.new()
	_wave_clear_player.stream = wc_stream
	_wave_clear_player.volume_db = -4.0  # v0.7.0: -3→-4
	add_child(_wave_clear_player)

	_boss_entrance_player = AudioStreamPlayer.new()
	_boss_entrance_player.stream = _gen_boss_entrance()
	_boss_entrance_player.volume_db = -3.0  # v0.7.0: -2→-3
	add_child(_boss_entrance_player)

	_ui_cancel_player = AudioStreamPlayer.new()
	_ui_cancel_player.stream = _gen_ui_cancel()
	_ui_cancel_player.volume_db = -4.0
	add_child(_ui_cancel_player)

	# Damage Taken: pyfxr WAVバリアント (player_damage v1-v4) をプール
	# Why: 被弾は最重要フィードバック。4バリアントで反復疲労を防ぐ
	var dmg_wavs: Array[AudioStream] = []
	for suffix in ["", "_v2", "_v3", "_v4"]:
		var wav: AudioStream = _try_load_wav("player_damage%s.wav" % suffix)
		if wav != null:
			dmg_wavs.append(wav)
	var dmg_fallback: AudioStream = _gen_damage_taken()
	for i in DAMAGE_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		if dmg_wavs.size() > 0:
			p.stream = dmg_wavs[i % dmg_wavs.size()]
		else:
			p.stream = dmg_fallback
		p.volume_db = -3.0  # v0.7.0: -2→-3（被弾は依然として高優先だが少し下げる）
		add_child(p)
		_damage_taken_players.append(p)

	# 改善178: ゲームオーバーSE
	_game_over_player = AudioStreamPlayer.new()
	_game_over_player.stream = _gen_game_over()
	_game_over_player.volume_db = -2.0  # ゲームオーバーは目立たせる
	add_child(_game_over_player)

	# 改善179: 勝利ファンファーレSE
	_victory_player = AudioStreamPlayer.new()
	_victory_player.stream = _gen_victory()
	_victory_player.volume_db = -2.0  # 勝利も目立たせる
	add_child(_victory_player)

	# 改善180: ボス撃破専用SFX
	_boss_kill_player = AudioStreamPlayer.new()
	_boss_kill_player.stream = _gen_boss_kill()
	_boss_kill_player.volume_db = -1.0  # ゲーム最大のイベント — 最も目立たせる
	add_child(_boss_kill_player)

	# 改善181: ボスフェーズ移行SFX
	_boss_phase_player = AudioStreamPlayer.new()
	_boss_phase_player.stream = _gen_boss_phase()
	_boss_phase_player.volume_db = -3.0
	add_child(_boss_phase_player)

	# 改善182: ステージ警告SFX (0=SURGE, 1=CRISIS, 2=FINAL PUSH)
	var alert_vols := [-5.0, -3.0, -2.0]
	for ai in 3:
		var ap := AudioStreamPlayer.new()
		ap.stream = _gen_stage_alert(ai)
		ap.volume_db = alert_vols[ai]
		add_child(ap)
		_stage_alert_players.append(ap)

	# 改善175: 回復SE (small/large 2段階)
	_heal_small_player = AudioStreamPlayer.new()
	_heal_small_player.stream = _gen_heal(false)
	_heal_small_player.volume_db = -8.0  # 控えめ: 回復は常時SFXにならないよう
	add_child(_heal_small_player)
	_heal_large_player = AudioStreamPlayer.new()
	_heal_large_player.stream = _gen_heal(true)
	_heal_large_player.volume_db = -5.0  # 大回復はもう少し大きく
	add_child(_heal_large_player)

	# 改善174: コンボティアアップSE — 4段階それぞれ異なる音色
	var combo_streams := [_gen_combo_tier(0), _gen_combo_tier(1), _gen_combo_tier(2), _gen_combo_tier(3)]
	var combo_vols := [-6.0, -5.0, -4.0, -2.0]  # GODLIKEほど大きく
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.stream = combo_streams[i]
		p.volume_db = combo_vols[i]
		add_child(p)
		_combo_tier_players.append(p)

func _process(delta: float) -> void:
	if _low_hp_cooldown > 0.0:
		_low_hp_cooldown -= delta
	if _damage_cooldown > 0.0:
		_damage_cooldown -= delta
	if _dot_cooldown > 0.0:  # 改善172: DoTクールダウン管理
		_dot_cooldown -= delta
	if _heal_cooldown > 0.0:  # 改善175: 回復SEクールダウン管理
		_heal_cooldown -= delta
	# XP回収ストリークのピッチは時間で減衰（0.5s何も拾わないとリセット）
	if _xp_pitch_streak > 0.0:
		_xp_pitch_streak = maxf(_xp_pitch_streak - delta * 0.8, 0.0)

func play_shot() -> void:
	var p := _shot_players[_shot_idx]
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()
	_shot_idx = (_shot_idx + 1) % SHOT_POOL_SIZE

func play_hit() -> void:
	var p := _hit_players[_hit_idx]
	# ±15%のピッチ変動で聴覚疲労を防ぐ（同じ音の反復は「AI製」の兆候）
	p.pitch_scale = randf_range(0.85, 1.15)
	p.play()
	_hit_idx = (_hit_idx + 1) % HIT_POOL_SIZE

func play_kill() -> void:
	_kill_player.pitch_scale = randf_range(0.9, 1.1)
	_kill_player.play()

func play_ui_select() -> void:
	_ui_select_player.play()

func play_xp_pickup() -> void:
	var p := _xp_pickup_players[_xp_pickup_idx]
	# 連続回収でピッチが上がる（0.05ずつ、最大+0.5 = 半音4つ分上昇）
	_xp_pitch_streak = minf(_xp_pitch_streak + 0.05, 0.5)
	p.pitch_scale = 1.0 + _xp_pitch_streak + randf_range(-0.02, 0.02)
	p.play()
	_xp_pickup_idx = (_xp_pickup_idx + 1) % XP_PICKUP_POOL_SIZE

func play_level_up() -> void:
	_level_up_player.pitch_scale = randf_range(0.95, 1.05)
	_level_up_player.play()
	_xp_pitch_streak = 0.0  # レベルアップでリセット

func play_bgm() -> void:
	switch_bgm("battle")

func stop_bgm() -> void:
	_bgm_player.stop()
	_bgm_intense_player.stop()
	_bgm_boss_player.stop()
	_bgm_playing = false
	_current_bgm = ""

## 状況に応じたBGM切替
func switch_bgm(track: String) -> void:
	if _current_bgm == track:
		return
	# 全トラック停止
	_bgm_player.stop()
	_bgm_intense_player.stop()
	_bgm_boss_player.stop()
	# 該当トラック再生
	match track:
		"battle":
			_bgm_player.play()
		"intense":
			_bgm_intense_player.play()
		"boss":
			_bgm_boss_player.play()
	_current_bgm = track
	_bgm_playing = true

func play_wave_clear() -> void:
	_wave_clear_player.pitch_scale = randf_range(0.95, 1.05)
	_wave_clear_player.play()

func play_boss_entrance() -> void:
	_boss_entrance_player.play()

## 改善184: ボス警告SE（10秒前予告）。ボス登場音を低くして「遠くで何かが来る」感を演出。
func play_boss_warning() -> void:
	_boss_entrance_player.pitch_scale = 0.55  # 半音5つ下げて「遠い・重い」印象
	_boss_entrance_player.volume_db = -10.0   # 控えめに（実際の登場より小さく）
	_boss_entrance_player.play()
	# 登場時に元に戻す（play_boss_entrance()は1.0で呼ぶ）
	await get_tree().create_timer(2.0).timeout
	_boss_entrance_player.pitch_scale = 1.0
	_boss_entrance_player.volume_db = -3.0

func play_ui_cancel() -> void:
	_ui_cancel_player.play()

func play_damage_taken() -> void:
	if _damage_cooldown <= 0.0:
		var p := _damage_taken_players[_damage_idx]
		p.pitch_scale = randf_range(0.85, 1.15)
		p.play()
		_damage_idx = (_damage_idx + 1) % DAMAGE_POOL_SIZE
		_damage_cooldown = DAMAGE_COOLDOWN

func play_low_hp_warning() -> void:
	if _low_hp_cooldown <= 0.0:
		_low_hp_player.play()
		_low_hp_cooldown = LOW_HP_INTERVAL

## 改善172: DoT tick SE。fire=高め(680Hz)、poison=低め(320Hz)
func play_dot_tick(element: String = "fire") -> void:
	if _dot_cooldown > 0.0:
		return
	# 属性でピッチを変える（fire: 高め, poison: 低め）
	_dot_player.pitch_scale = 1.4 if element == "fire" else 0.8
	_dot_player.play()
	_dot_cooldown = DOT_COOLDOWN

## 改善174: コンボティアアップSE
## tier 0=COMBO(3), 1=RAMPAGE(8), 2=MASSACRE(15), 3=GODLIKE(30)
## Why: ティア昇格は「報酬の頂点」の瞬間。音がなかったので達成感が半減していた。
func play_combo_tier(tier: int) -> void:
	if tier < 0 or tier >= _combo_tier_players.size():
		return
	var p := _combo_tier_players[tier]
	p.pitch_scale = 1.0  # 固定ピッチ（tierごとに設計済み）
	p.play()

## 改善178: ゲームオーバーSE。BGM停止直後に呼ぶ。
func play_game_over() -> void:
	_game_over_player.play()

## 改善179: 勝利ファンファーレSE。BGM停止直後に呼ぶ。
func play_victory() -> void:
	_victory_player.play()

## 改善180: ボス撃破SE。_on_boss_died()から呼ぶ。wave_clearより重厚に。
func play_boss_kill() -> void:
	_boss_kill_player.play()

## 改善181: ボスフェーズ移行SE。_on_boss_phase_changed()から呼ぶ。
func play_boss_phase() -> void:
	_boss_phase_player.play()

## 改善182: ステージ警告SE。level: 0=SURGE, 1=CRISIS, 2=FINAL PUSH
func play_stage_alert(level: int) -> void:
	if level < 0 or level >= _stage_alert_players.size():
		return
	_stage_alert_players[level].play()

## 改善175: 回復SE。amount >= 50 で大回復音、それ以下で小回復音。
## Why: life stealは高頻度なのでHEAL_COOLDOWN(1.2s)でスロットル。
## large heal（ボス撃破回復/shrine/50+）は常に再生（クールダウンリセット）。
func play_heal(amount: float) -> void:
	if amount >= HEAL_LARGE_THRESHOLD:
		# 大回復は優先再生（クールダウンを無視してリセット）
		_heal_large_player.pitch_scale = randf_range(0.95, 1.05)
		_heal_large_player.play()
		_heal_cooldown = HEAL_COOLDOWN
	elif _heal_cooldown <= 0.0:
		# 小回復はクールダウン制限付き
		_heal_small_player.pitch_scale = randf_range(0.9, 1.1)
		_heal_small_player.play()
		_heal_cooldown = HEAL_COOLDOWN

# --- サウンド生成 ---

func _make_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	# Float32 → 16-bit PCM bytes
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var val := clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes[i * 2] = val & 0xFF
		bytes[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = bytes
	return stream

## 改善172: DoT tick — ジジジというノイズバースト (0.06s)
## fire: pitch_scale=1.4でより高くシャープ、poison: pitch_scale=0.8で低く重い
func _gen_dot() -> AudioStreamWAV:
	var dur := 0.06
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var frac := t / dur
		var env := (1.0 - frac) * (1.0 - frac)  # 急速減衰
		# 基音(480Hz)にノイズを重ねた「ジジ」音
		var base := sin(TAU * 480.0 * t) * 0.4
		var noise := (randf() * 2.0 - 1.0) * 0.6
		samples[i] = env * (base + noise) * 0.45
	return _make_stream(samples)

## Shot: 下降スイープチャープ (0.08s)
func _gen_shot() -> AudioStreamWAV:
	var dur := 0.08
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var freq := 800.0 - 600.0 * (t / dur)
		var env := 1.0 - (t / dur)
		var s := env * 0.5 * sin(TAU * freq * t)
		# ノイズバースト（冒頭）
		if t < 0.01:
			s += 0.3 * (randf() * 2.0 - 1.0) * (1.0 - t / 0.01)
		samples[i] = s
	return _make_stream(samples)

## Hit: 低音インパクト (0.06s)
func _gen_hit() -> AudioStreamWAV:
	var dur := 0.06
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var freq := 150.0 + 100.0 * exp(-t * 30.0)
		var env := exp(-t * 40.0)
		var s := env * 0.6 * sin(TAU * freq * t)
		if t < 0.003:
			s += 0.4 * sin(TAU * 2000.0 * t)
		samples[i] = s
	return _make_stream(samples)

## Kill: ポップ + スパークル (0.2s)
func _gen_kill() -> AudioStreamWAV:
	var dur := 0.2
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var pop := exp(-t * 20.0) * 0.5 * sin(TAU * 300.0 * t)
		var sparkle_freq := 600.0 + 1200.0 * (t / dur)
		var sparkle := 0.3 * sin(TAU * sparkle_freq * t) * exp(-t * 8.0)
		var harm := 0.15 * sin(TAU * sparkle_freq * 2.0 * t) * exp(-t * 10.0)
		# 簡易エンベロープ
		var env := 1.0
		if t < 0.005:
			env = t / 0.005
		elif t > dur - 0.08:
			env = (dur - t) / 0.08
		samples[i] = env * (pop + sparkle + harm)
	return _make_stream(samples)

## UI Select: クリーンなブリップ (0.1s)
func _gen_ui_select() -> AudioStreamWAV:
	var dur := 0.1
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var freq := 880.0
		var env := 1.0
		if t < 0.005:
			env = t / 0.005
		elif t > dur - 0.04:
			env = (dur - t) / 0.04
		var s := env * 0.4 * sin(TAU * freq * t)
		s += env * 0.2 * sin(TAU * freq * 2.0 * t)
		samples[i] = s
	return _make_stream(samples)

## Low HP Warning: 不穏なパルス (0.3s)
func _gen_low_hp() -> AudioStreamWAV:
	var dur := 0.3
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var pulse := 0.5 + 0.5 * sin(TAU * 6.0 * t)
		var env := 1.0
		if t < 0.01:
			env = t / 0.01
		elif t > dur - 0.1:
			env = (dur - t) / 0.1
		var s := env * pulse * 0.5 * sin(TAU * 200.0 * t)
		s += env * pulse * 0.3 * sin(TAU * 100.0 * t)
		samples[i] = s
	return _make_stream(samples)

## Level Up: 上昇アルペジオ C5→E5→G5→C6 (0.35s)
## 「報酬が来た」と即座に脳が認識するファンファーレパターン
func _gen_level_up() -> AudioStreamWAV:
	var dur := 0.35
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	# 4音アルペジオ: 各ノート約0.08s、最後の音は余韻付き
	var notes := [523.25, 659.25, 783.99, 1046.50]  # C5, E5, G5, C6
	var note_dur := 0.08
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var note_idx := mini(int(t / note_dur), 3)
		var note_t := t - note_idx * note_dur
		var freq: float = notes[note_idx]
		# 各ノートのアタック+サステイン
		var note_env := 1.0
		if note_t < 0.005:
			note_env = note_t / 0.005
		# 最後のノート以外は短くカット
		if note_idx < 3 and note_t > note_dur - 0.01:
			note_env = (note_dur - note_t) / 0.01
		# 最後のノートは長い余韻
		if note_idx == 3:
			note_env *= exp(-note_t * 6.0)
		# 全体フェードアウト
		var global_env := 1.0
		if t > dur - 0.05:
			global_env = (dur - t) / 0.05
		var s := global_env * note_env * 0.4 * sin(TAU * freq * t)
		# オクターブ上のハーモニクスで明るさ追加
		s += global_env * note_env * 0.15 * sin(TAU * freq * 2.0 * t)
		samples[i] = s
	return _make_stream(samples)

## XP Pickup: 短い高音ブリップ (0.05s)
## pitch_scaleで連続回収時に上昇させて「報酬チェーン」を演出
func _gen_xp_pickup() -> AudioStreamWAV:
	var dur := 0.05
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var freq := 1200.0
		var env := 1.0
		if t < 0.003:
			env = t / 0.003
		elif t > dur - 0.015:
			env = (dur - t) / 0.015
		var s := env * 0.3 * sin(TAU * freq * t)
		s += env * 0.1 * sin(TAU * freq * 1.5 * t)
		samples[i] = s
	return _make_stream(samples)

## BGM: ダークアンビエントループ (8s)
## Am調のベースドローン + 4音アルペジオパターンで不穏なムードを維持
## ループ再生前提: AudioStreamWAV.loop_mode = LOOP_FORWARD
func _gen_bgm() -> AudioStreamWAV:
	var dur := 8.0
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	# Am系: A2=110, C3=130.81, E3=164.81, A3=220
	var bass_freq := 110.0  # A2 ドローン
	# 4音アルペジオ (Am): A3, C4, E4, A4
	var arp_notes := [220.0, 261.63, 329.63, 440.0]
	var arp_speed := 0.5  # 1ノート0.5s = 2sで1サイクル
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		# ベースドローン: 低周波のうねりを持つサイン波
		var bass_lfo := 1.0 + 0.02 * sin(TAU * 0.3 * t)
		s += 0.25 * sin(TAU * bass_freq * bass_lfo * t)
		# ベースの5度上 (E3) をうっすら
		s += 0.08 * sin(TAU * 164.81 * t)
		# アルペジオ: 時間に応じたノート選択
		var arp_idx := int(t / arp_speed) % 4
		var arp_t := fmod(t, arp_speed)
		var arp_freq: float = arp_notes[arp_idx]
		# ノートごとのエンベロープ（立ち上がり + 減衰）
		var arp_env := 0.0
		if arp_t < 0.02:
			arp_env = arp_t / 0.02
		else:
			arp_env = exp(-(arp_t - 0.02) * 4.0)
		# アルペジオを控えめに + 倍音
		s += 0.12 * arp_env * sin(TAU * arp_freq * t)
		s += 0.04 * arp_env * sin(TAU * arp_freq * 2.0 * t)
		# パッド: フィルタードノイズ風（低周波ノイズの擬似）
		# LFO変調した低いサイン波2つの干渉でパッド感を出す
		var pad_lfo := sin(TAU * 0.1 * t)
		s += 0.06 * sin(TAU * (130.81 + pad_lfo * 2.0) * t)
		s += 0.04 * sin(TAU * (196.0 + pad_lfo * 1.5) * t)  # G3
		# 全体のスロウLFO（呼吸感）
		var breath := 0.85 + 0.15 * sin(TAU * 0.125 * t)  # 8s cycle
		samples[i] = s * breath * 0.6
	var stream := _make_stream(samples)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

## Wave Clear: 勝利の短いファンファーレ (0.4s)
## 上昇5音: C5→D5→E5→G5→C6（メジャー感で達成感）
func _gen_wave_clear() -> AudioStreamWAV:
	var dur := 0.4
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [523.25, 587.33, 659.25, 783.99, 1046.50]
	var note_dur := 0.07
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var note_idx := mini(int(t / note_dur), 4)
		var note_t := t - note_idx * note_dur
		var freq: float = notes[note_idx]
		var note_env := 1.0
		if note_t < 0.003:
			note_env = note_t / 0.003
		if note_idx < 4 and note_t > note_dur - 0.008:
			note_env = (note_dur - note_t) / 0.008
		if note_idx == 4:
			note_env *= exp(-note_t * 5.0)
		var global_env := 1.0
		if t > dur - 0.06:
			global_env = (dur - t) / 0.06
		var s := global_env * note_env * 0.35 * sin(TAU * freq * t)
		s += global_env * note_env * 0.12 * sin(TAU * freq * 2.0 * t)
		# 3度ハーモニー（メジャー感を強調）
		s += global_env * note_env * 0.08 * sin(TAU * freq * 1.25 * t)
		samples[i] = s
	return _make_stream(samples)

## Boss Entrance: ドラマチックな低音インパクト (0.6s)
## 低い轟音 + 金属的なリング + 不穏な下降
func _gen_boss_entrance() -> AudioStreamWAV:
	var dur := 0.6
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		# 低い轟音（指数減衰）
		var rumble := 0.5 * sin(TAU * 55.0 * t) * exp(-t * 3.0)
		rumble += 0.3 * sin(TAU * 82.5 * t) * exp(-t * 4.0)
		# 金属的なリング（高周波、長い減衰）
		var ring := 0.2 * sin(TAU * 1200.0 * t) * exp(-t * 8.0)
		ring += 0.1 * sin(TAU * 1800.0 * t) * exp(-t * 10.0)
		# 不穏な下降スイープ
		var sweep_freq := 400.0 * exp(-t * 5.0) + 80.0
		var sweep := 0.15 * sin(TAU * sweep_freq * t) * exp(-t * 4.0)
		# インパクトの瞬間（最初の20ms）
		var impact := 0.0
		if t < 0.02:
			impact = 0.4 * (1.0 - t / 0.02) * sin(TAU * 3000.0 * t)
		var s := rumble + ring + sweep + impact
		# 全体エンベロープ
		if t > dur - 0.1:
			s *= (dur - t) / 0.1
		samples[i] = s
	return _make_stream(samples)

## Damage Taken: 金属的なクランチ (0.12s)
## 低音インパクト(100-200Hz) + 高音クリック(2kHz) + ノイズバースト
## 被弾を即座に認識できる: 最重要フィードバック音
func _gen_damage_taken() -> AudioStreamWAV:
	var dur := 0.12
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		# 低音インパクト: 急速減衰
		var low := 0.5 * sin(TAU * 120.0 * t) * exp(-t * 25.0)
		low += 0.3 * sin(TAU * 180.0 * t) * exp(-t * 30.0)
		# 高音クリック: 金属的な質感
		var high := 0.25 * sin(TAU * 2000.0 * t) * exp(-t * 50.0)
		high += 0.1 * sin(TAU * 3200.0 * t) * exp(-t * 60.0)
		# ノイズバースト（冒頭10ms）: 衝撃感
		var noise := 0.0
		if t < 0.01:
			noise = 0.35 * (randf() * 2.0 - 1.0) * (1.0 - t / 0.01)
		# エンベロープ
		var env := 1.0
		if t < 0.002:
			env = t / 0.002  # 超短アタック
		elif t > dur - 0.03:
			env = (dur - t) / 0.03
		samples[i] = env * (low + high + noise)
	return _make_stream(samples)

## UI Cancel: ソフトな下降ブリップ (0.08s)
func _gen_ui_cancel() -> AudioStreamWAV:
	var dur := 0.08
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		# 下降周波数（select の逆）
		var freq := 660.0 - 300.0 * (t / dur)
		var env := 1.0
		if t < 0.003:
			env = t / 0.003
		elif t > dur - 0.03:
			env = (dur - t) / 0.03
		var s := env * 0.35 * sin(TAU * freq * t)
		samples[i] = s
	return _make_stream(samples)

## Intense BGM: テンポアップ版ダークアンビエント (8s)
## Wave 16+で切り替え。Dm調、速いアルペジオ + パルスベース + ハイハット風
func _gen_bgm_intense() -> AudioStreamWAV:
	var dur := 8.0
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var bass_freq := 73.42  # D2 ドローン
	var arp_notes := [293.66, 349.23, 440.0, 587.33]  # D4, F4, A4, D5
	var arp_speed := 0.25
	var pulse_interval := 0.125
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		# パルスベース
		var pulse_t := fmod(t, pulse_interval)
		var pulse_env := exp(-pulse_t * 40.0)
		s += 0.3 * pulse_env * sin(TAU * bass_freq * t)
		s += 0.12 * pulse_env * sin(TAU * bass_freq * 2.0 * t)
		# 高速アルペジオ
		var arp_idx := int(t / arp_speed) % 4
		var arp_t := fmod(t, arp_speed)
		var arp_freq: float = arp_notes[arp_idx]
		var arp_env := 0.0
		if arp_t < 0.01:
			arp_env = arp_t / 0.01
		else:
			arp_env = exp(-(arp_t - 0.01) * 6.0)
		s += 0.15 * arp_env * sin(TAU * arp_freq * t)
		s += 0.05 * arp_env * sin(TAU * arp_freq * 2.0 * t)
		# ハイハット風ノイズ
		var hh_t := fmod(t, 0.25)
		if hh_t < 0.02:
			var noise_val := sin(TAU * 7919.0 * t) * sin(TAU * 5101.0 * t)
			s += 0.08 * noise_val * (1.0 - hh_t / 0.02)
		# テンションパッド
		var pad_lfo := sin(TAU * 0.2 * t)
		s += 0.05 * sin(TAU * (174.61 + pad_lfo * 3.0) * t)
		s += 0.04 * sin(TAU * (220.0 + pad_lfo * 2.0) * t)
		var breath := 0.9 + 0.1 * sin(TAU * 0.25 * t)
		samples[i] = s * breath * 0.55
	var stream := _make_stream(samples)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

## Boss BGM: 威圧的な低音ドローン + 緊張感 (8s)
func _gen_bgm_boss() -> AudioStreamWAV:
	var dur := 8.0
	var count := int(SAMPLE_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var drone_freq := 41.2  # E1
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		# 超低音ドローン: E1 + 5度 B1
		var drone_lfo := 1.0 + 0.03 * sin(TAU * 0.15 * t)
		s += 0.35 * sin(TAU * drone_freq * drone_lfo * t)
		s += 0.2 * sin(TAU * 61.74 * t)
		# 心拍パルス
		var heartbeat_t := fmod(t, 0.8)
		var hb_env := 0.0
		if heartbeat_t < 0.05:
			hb_env = heartbeat_t / 0.05
		elif heartbeat_t < 0.15:
			hb_env = exp(-(heartbeat_t - 0.05) * 20.0)
		var hb2_t := heartbeat_t - 0.2
		if hb2_t > 0.0 and hb2_t < 0.1:
			hb_env += exp(-hb2_t * 25.0) * 0.6
		s += 0.25 * hb_env * sin(TAU * 82.41 * t)
		# 不協和パッド: トライトーン
		var dissonance_lfo := sin(TAU * 0.08 * t)
		s += 0.06 * sin(TAU * (116.54 + dissonance_lfo * 2.0) * t)
		s += 0.04 * sin(TAU * (155.56 + dissonance_lfo * 1.5) * t)
		# サイレン的上昇
		var siren_phase := fmod(t, 4.0) / 4.0
		var siren_freq := 200.0 + siren_phase * 400.0
		s += 0.08 * siren_phase * sin(TAU * siren_freq * t)
		# 金属的リバーブ風
		s += 0.03 * sin(TAU * 1500.0 * t) * exp(-fmod(t, 2.0) * 3.0)
		var breath := 0.85 + 0.15 * sin(TAU * 0.125 * t)
		samples[i] = s * breath * 0.5
	var stream := _make_stream(samples)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

## 改善174: コンボティアアップSE生成
## tier 0 (COMBO×3): 短い2音上昇 (E5→A5, 0.12s×2=0.24s) — 「最初の達成」を明るく
## tier 1 (RAMPAGE×8): 力強い和音スタブ (C5+G5同時, 0.3s) — 「危なくなってきた」緊張感
## tier 2 (MASSACRE×15): 3音劇的上昇 (A4→E5→A5, 0.15s×3=0.45s) — 「壊れてる！」の爽快感
## tier 3 (GODLIKE×30): 4音ファンファーレ (C5→G5→C6→E6, 0.1s×4+余韻=0.55s) — 最高の報酬音
func _gen_combo_tier(tier: int) -> AudioStreamWAV:
	match tier:
		0:  # COMBO: E5(659)→A5(880) 2音 短いアクセント
			var dur := 0.24
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			var notes := [659.25, 880.0]
			var nd := dur / 2.0
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var ni := mini(int(t / nd), 1)
				var nt := t - ni * nd
				var freq: float = notes[ni]
				var env := 1.0
				if nt < 0.005: env = nt / 0.005
				elif nt > nd - 0.02: env = (nd - nt) / 0.02
				var s := env * 0.35 * sin(TAU * freq * t)
				s += env * 0.12 * sin(TAU * freq * 2.0 * t)
				samples[i] = s
			return _make_stream(samples)
		1:  # RAMPAGE: C5+G5 同時和音 (0.3s急速減衰) — 力強い一撃感
			var dur := 0.3
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var env := exp(-t * 8.0)
				if t < 0.004: env = t / 0.004
				var s := env * 0.4 * sin(TAU * 523.25 * t)   # C5
				s += env * 0.3 * sin(TAU * 783.99 * t)       # G5
				s += env * 0.15 * sin(TAU * 1046.5 * t)      # C6 (倍音)
				samples[i] = s
			return _make_stream(samples)
		2:  # MASSACRE: A4→E5→A5 3音劇的上昇 (0.45s) — 爽快感
			var dur := 0.45
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			var notes := [440.0, 659.25, 880.0]
			var nd := dur / 3.0
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var ni := mini(int(t / nd), 2)
				var nt := t - ni * nd
				var freq: float = notes[ni]
				var env := 1.0
				if nt < 0.004: env = nt / 0.004
				elif nt > nd - 0.015: env = (nd - nt) / 0.015
				if ni == 2: env *= exp(-nt * 5.0)
				var s := env * 0.38 * sin(TAU * freq * t)
				s += env * 0.14 * sin(TAU * freq * 2.0 * t)
				s += env * 0.06 * sin(TAU * freq * 3.0 * t)
				samples[i] = s
			return _make_stream(samples)
		3:  # GODLIKE: C5→G5→C6→E6 4音ファンファーレ (0.55s) — 最高報酬音
			var dur := 0.55
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			var notes := [523.25, 783.99, 1046.5, 1318.5]  # C5, G5, C6, E6
			var nd := 0.10
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var ni := mini(int(t / nd), 3)
				var nt := t - ni * nd
				var freq: float = notes[ni]
				var env := 1.0
				if nt < 0.004: env = nt / 0.004
				if ni < 3 and nt > nd - 0.012: env = (nd - nt) / 0.012
				if ni == 3: env *= exp(-nt * 4.0)
				var global_env := 1.0
				if t > dur - 0.06: global_env = (dur - t) / 0.06
				var s := global_env * env * 0.42 * sin(TAU * freq * t)
				s += global_env * env * 0.18 * sin(TAU * freq * 2.0 * t)
				s += global_env * env * 0.08 * sin(TAU * freq * 3.0 * t)
				samples[i] = s
			return _make_stream(samples)
	# フォールバック: 空のストリーム
	var samples_fb := PackedFloat32Array()
	samples_fb.resize(100)
	return _make_stream(samples_fb)

## 改善175: 回復SE生成
## small: C5→E5 柔らかい2音上昇 (0.2s) — 優しいlife steal回復感
## large: C5→G5→C6 温かい和音アルペジオ (0.35s) — ボス撃破/shrine大回復の喜び
func _gen_heal(large: bool) -> AudioStreamWAV:
	if large:
		var dur := 0.35
		var cnt := int(SAMPLE_RATE * dur)
		var samples := PackedFloat32Array()
		samples.resize(cnt)
		var notes := [523.25, 783.99, 1046.5]  # C5, G5, C6
		var nd := dur / 3.0
		for i in cnt:
			var t := float(i) / SAMPLE_RATE
			var ni := mini(int(t / nd), 2)
			var nt := t - ni * nd
			var freq: float = notes[ni]
			var env := 1.0
			if nt < 0.006: env = nt / 0.006
			elif nt > nd - 0.018: env = (nd - nt) / 0.018
			if ni == 2: env *= exp(-nt * 4.5)
			var global_env := 1.0
			if t > dur - 0.05: global_env = (dur - t) / 0.05
			var s := global_env * env * 0.38 * sin(TAU * freq * t)
			# 第3倍音でグロッケン風の音色（医療・回復の爽やかさ）
			s += global_env * env * 0.14 * sin(TAU * freq * 2.0 * t)
			s += global_env * env * 0.05 * sin(TAU * freq * 3.0 * t)
			samples[i] = s
		return _make_stream(samples)
	else:
		# small: C5→E5 2音 (0.2s) — 最小限の回復フィードバック
		var dur := 0.2
		var cnt := int(SAMPLE_RATE * dur)
		var samples := PackedFloat32Array()
		samples.resize(cnt)
		var notes := [523.25, 659.25]  # C5, E5
		var nd := dur / 2.0
		for i in cnt:
			var t := float(i) / SAMPLE_RATE
			var ni := mini(int(t / nd), 1)
			var nt := t - ni * nd
			var freq: float = notes[ni]
			var env := 1.0
			if nt < 0.005: env = nt / 0.005
			elif nt > nd - 0.015: env = (nd - nt) / 0.015
			if ni == 1: env *= exp(-nt * 6.0)
			var s := env * 0.28 * sin(TAU * freq * t)
			s += env * 0.10 * sin(TAU * freq * 2.0 * t)
			samples[i] = s
		return _make_stream(samples)

## 改善178: ゲームオーバーSE生成
## 低音下降スイープ (600Hz→80Hz, 0.6s) + 残響シミュ (0.4s)
## Why: BGM停止後の無音は演出機会の損失。下降音で「失墜」を体で感じさせる。
func _gen_game_over() -> AudioStreamWAV:
	var sweep_dur := 0.6
	var echo_dur := 0.4
	var total_dur := sweep_dur + echo_dur
	var cnt := int(SAMPLE_RATE * total_dur)
	var samples := PackedFloat32Array()
	samples.resize(cnt)
	var freq_start := 600.0
	var freq_end := 80.0
	for i in cnt:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		if t < sweep_dur:
			# 指数的に下降（線形より「落下」感が強い）
			var progress := t / sweep_dur
			var freq := freq_start * pow(freq_end / freq_start, progress)
			# エンベロープ: 即アタック、末尾で減衰
			var env := 1.0
			if t < 0.01: env = t / 0.01
			if t > sweep_dur - 0.05: env = (sweep_dur - t) / 0.05
			# 基音 + 低倍音で重厚さを出す
			s = env * 0.55 * sin(TAU * freq * t)
			s += env * 0.20 * sin(TAU * freq * 0.5 * t)
			s += env * 0.12 * sin(TAU * freq * 2.0 * t)
		else:
			# 残響: 80Hzの余韻が静かに消えていく
			var echo_t := t - sweep_dur
			var echo_env := exp(-echo_t * 5.0)
			s = echo_env * 0.18 * sin(TAU * freq_end * t)
			s += echo_env * 0.07 * sin(TAU * freq_end * 0.5 * t)
		samples[i] = s
	return _make_stream(samples)

## 改善179: 勝利ファンファーレSE生成
## C4→E4→G4→C5 上昇アルペジオ (0.5s) + 鐘残響 (0.5s)
## Why: ゲームオーバーの下降音と対称。「上昇」で勝利・達成を身体で感じさせる。
func _gen_victory() -> AudioStreamWAV:
	var fanfare_dur := 0.5
	var ring_dur := 0.5
	var total_dur := fanfare_dur + ring_dur
	var cnt := int(SAMPLE_RATE * total_dur)
	var samples := PackedFloat32Array()
	samples.resize(cnt)
	# C4→E4→G4→C5 (明るい長調の完全終止感)
	var notes := [261.63, 329.63, 392.0, 523.25]
	var nd := fanfare_dur / 4.0
	for i in cnt:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		if t < fanfare_dur:
			var ni := mini(int(t / nd), 3)
			var nt := t - ni * nd
			var freq: float = notes[ni]
			var env := 1.0
			if nt < 0.008: env = nt / 0.008
			if ni < 3 and nt > nd - 0.015: env = (nd - nt) / 0.015
			if ni == 3: env *= exp(-nt * 2.5)  # 最終音はゆっくり減衰
			# 基音 + 明るい倍音（鐘・グロッケン風）
			s = env * 0.50 * sin(TAU * freq * t)
			s += env * 0.22 * sin(TAU * freq * 2.0 * t)
			s += env * 0.10 * sin(TAU * freq * 3.0 * t)
			s += env * 0.05 * sin(TAU * freq * 4.0 * t)
		else:
			# 鐘残響: C5がゆっくり消えていく
			var ring_t := t - fanfare_dur
			var ring_env := exp(-ring_t * 2.8)
			var freq: float = notes[3]
			s = ring_env * 0.30 * sin(TAU * freq * t)
			s += ring_env * 0.12 * sin(TAU * freq * 2.0 * t)
		samples[i] = s
	return _make_stream(samples)

## 改善180: ボス撃破SE生成
## 低音爆発(0.15s) + 上昇フレア G4→B4→D5→G5 (0.5s) + 余韻(0.35s)
## Why: wave_clearの短い音と違い、爆発感+達成感の2段構えで「ボスを倒した」感を確定させる。
func _gen_boss_kill() -> AudioStreamWAV:
	var boom_dur := 0.15
	var flare_dur := 0.5
	var ring_dur := 0.35
	var total_dur := boom_dur + flare_dur + ring_dur
	var cnt := int(SAMPLE_RATE * total_dur)
	var samples := PackedFloat32Array()
	samples.resize(cnt)
	# G4→B4→D5→G5 — 長調勝利コード (booming triumphant)
	var flare_notes := [392.0, 493.88, 587.33, 783.99]
	var fnd := flare_dur / 4.0
	for i in cnt:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		if t < boom_dur:
			# 爆発: 低音ノイズバースト (80Hz + detuned 95Hz)
			var boom_env := exp(-t * 18.0)
			s = boom_env * 0.70 * sin(TAU * 80.0 * t)
			s += boom_env * 0.35 * sin(TAU * 95.0 * t)
			s += boom_env * 0.20 * sin(TAU * 160.0 * t)
		elif t < boom_dur + flare_dur:
			# 上昇フレア: 4音アルペジオ
			var ft := t - boom_dur
			var ni := mini(int(ft / fnd), 3)
			var nt := ft - ni * fnd
			var freq: float = flare_notes[ni]
			var env := 1.0
			if nt < 0.006: env = nt / 0.006
			if ni < 3 and nt > fnd - 0.012: env = (fnd - nt) / 0.012
			if ni == 3: env *= exp(-nt * 3.0)
			# 豊かな倍音構成で「金属的な勝利音」
			s = env * 0.48 * sin(TAU * freq * t)
			s += env * 0.22 * sin(TAU * freq * 2.0 * t)
			s += env * 0.10 * sin(TAU * freq * 3.0 * t)
			s += env * 0.05 * sin(TAU * freq * 4.0 * t)
		else:
			# 余韻: G5が消えていく
			var rt := t - boom_dur - flare_dur
			var renv := exp(-rt * 3.5)
			var freq: float = flare_notes[3]
			s = renv * 0.25 * sin(TAU * freq * t)
			s += renv * 0.10 * sin(TAU * freq * 2.0 * t)
		samples[i] = s
	return _make_stream(samples)

## 改善181: ボスフェーズ移行SE生成
## 不協和スウェル上昇 (0.3s) + 金属打撃インパクト (0.1s) + 残響 (0.3s)
## Why: 「まだ続くのか」という恐怖感。ボス登場(bass_entrance)とは違う脅威感が必要。
func _gen_boss_phase() -> AudioStreamWAV:
	var swell_dur := 0.3
	var hit_dur := 0.1
	var ring_dur := 0.3
	var total_dur := swell_dur + hit_dur + ring_dur
	var cnt := int(SAMPLE_RATE * total_dur)
	var samples := PackedFloat32Array()
	samples.resize(cnt)
	for i in cnt:
		var t := float(i) / SAMPLE_RATE
		var s := 0.0
		if t < swell_dur:
			# 不協和スウェル: tritone (A4 + Eb5) がクレッシェンドで上昇
			var progress := t / swell_dur
			var env := progress  # 徐々に大きくなる
			s = env * 0.35 * sin(TAU * 440.0 * t)      # A4
			s += env * 0.30 * sin(TAU * 622.25 * t)    # Eb5 (tritone — 不協和)
			s += env * 0.15 * sin(TAU * 880.0 * t)     # A5 (overtone)
		elif t < swell_dur + hit_dur:
			# 金属打撃: 短い高域インパクト
			var ht := t - swell_dur
			var henv := exp(-ht * 40.0)
			s = henv * 0.65 * sin(TAU * 220.0 * t)     # A3 — 重い金属感
			s += henv * 0.30 * sin(TAU * 110.0 * t)    # A2 — さらに低い基音
			s += henv * 0.20 * sin(TAU * 440.0 * t)    # A4 — 倍音
		else:
			# 残響: A3が静かに消えていく
			var rt := t - swell_dur - hit_dur
			var renv := exp(-rt * 8.0)
			s = renv * 0.20 * sin(TAU * 220.0 * t)
			s += renv * 0.10 * sin(TAU * 110.0 * t)
		samples[i] = s
	return _make_stream(samples)

## 改善182: ステージ警告SE生成
## level 0=SURGE: 橙色の上昇2音クラクション (0.3s)
## level 1=CRISIS: 赤い3音急速アラーム (0.35s)
## level 2=FINAL PUSH: 4音急速サイレン + ハーシュトランジェント (0.4s)
func _gen_stage_alert(level: int) -> AudioStreamWAV:
	match level:
		0:  # SURGE: 2音上昇クラクション (Bb4→F5)
			var dur := 0.30
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			var notes := [466.16, 698.46]  # Bb4, F5
			var nd := dur / 2.0
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var ni := mini(int(t / nd), 1)
				var nt := t - ni * nd
				var freq: float = notes[ni]
				var env := 1.0
				if nt < 0.005: env = nt / 0.005
				elif nt > nd - 0.02: env = (nd - nt) / 0.02
				samples[i] = env * 0.55 * sin(TAU * freq * t) + env * 0.20 * sin(TAU * freq * 2.0 * t)
			return _make_stream(samples)
		1:  # CRISIS: 3音急速アラーム (A4→C5→A4 反復感)
			var dur := 0.35
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			var notes := [440.0, 523.25, 440.0]  # A4, C5, A4
			var nd := dur / 3.0
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var ni := mini(int(t / nd), 2)
				var nt := t - ni * nd
				var freq: float = notes[ni]
				var env := 1.0
				if nt < 0.004: env = nt / 0.004
				elif nt > nd - 0.015: env = (nd - nt) / 0.015
				samples[i] = env * 0.60 * sin(TAU * freq * t) + env * 0.22 * sin(TAU * freq * 2.0 * t)
			return _make_stream(samples)
		2:  # FINAL PUSH: 4音急速サイレン (D5→A5→D5→A5 急速二重反復)
			var dur := 0.40
			var cnt := int(SAMPLE_RATE * dur)
			var samples := PackedFloat32Array()
			samples.resize(cnt)
			var notes := [587.33, 880.0, 587.33, 880.0]  # D5, A5, D5, A5
			var nd := dur / 4.0
			for i in cnt:
				var t := float(i) / SAMPLE_RATE
				var ni := mini(int(t / nd), 3)
				var nt := t - ni * nd
				var freq: float = notes[ni]
				var env := 1.0
				if nt < 0.003: env = nt / 0.003
				elif nt > nd - 0.01: env = (nd - nt) / 0.01
				# 末尾にわずかな減衰（最後の音が一番大きい）
				var global_boost := 0.8 + 0.2 * (float(ni) / 3.0)
				samples[i] = global_boost * (env * 0.55 * sin(TAU * freq * t) + env * 0.25 * sin(TAU * freq * 2.0 * t))
			return _make_stream(samples)
	# フォールバック
	var fb := PackedFloat32Array()
	fb.resize(100)
	return _make_stream(fb)
