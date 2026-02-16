extends Node

## SFX — ランタイム生成サウンドエフェクトマネージャー（Autoload）
## WAVファイルのインポート不要。AudioStreamWAVでPCMデータを直接生成。

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

var _bgm_player: AudioStreamPlayer
var _wave_clear_player: AudioStreamPlayer
var _boss_entrance_player: AudioStreamPlayer
var _ui_cancel_player: AudioStreamPlayer

var _low_hp_cooldown := 0.0
const LOW_HP_INTERVAL := 2.0
var _bgm_playing := false

const SAMPLE_RATE := 22050

func _ready() -> void:
	var shot_stream := _gen_shot()
	for i in SHOT_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = shot_stream
		p.volume_db = -6.0
		add_child(p)
		_shot_players.append(p)

	var hit_stream := _gen_hit()
	for i in HIT_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = hit_stream
		p.volume_db = -8.0
		add_child(p)
		_hit_players.append(p)

	_kill_player = AudioStreamPlayer.new()
	_kill_player.stream = _gen_kill()
	_kill_player.volume_db = -3.0
	add_child(_kill_player)

	_ui_select_player = AudioStreamPlayer.new()
	_ui_select_player.stream = _gen_ui_select()
	_ui_select_player.volume_db = -2.0
	add_child(_ui_select_player)

	_low_hp_player = AudioStreamPlayer.new()
	_low_hp_player.stream = _gen_low_hp()
	_low_hp_player.volume_db = -4.0
	add_child(_low_hp_player)

	_level_up_player = AudioStreamPlayer.new()
	_level_up_player.stream = _gen_level_up()
	_level_up_player.volume_db = -2.0
	add_child(_level_up_player)

	var xp_stream := _gen_xp_pickup()
	for i in XP_PICKUP_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = xp_stream
		p.volume_db = -10.0
		add_child(p)
		_xp_pickup_players.append(p)

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.stream = _gen_bgm()
	_bgm_player.volume_db = -12.0  # BGMは控えめに（SE優先）
	add_child(_bgm_player)

	_wave_clear_player = AudioStreamPlayer.new()
	_wave_clear_player.stream = _gen_wave_clear()
	_wave_clear_player.volume_db = -3.0
	add_child(_wave_clear_player)

	_boss_entrance_player = AudioStreamPlayer.new()
	_boss_entrance_player.stream = _gen_boss_entrance()
	_boss_entrance_player.volume_db = -2.0
	add_child(_boss_entrance_player)

	_ui_cancel_player = AudioStreamPlayer.new()
	_ui_cancel_player.stream = _gen_ui_cancel()
	_ui_cancel_player.volume_db = -4.0
	add_child(_ui_cancel_player)

func _process(delta: float) -> void:
	if _low_hp_cooldown > 0.0:
		_low_hp_cooldown -= delta
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
	if not _bgm_playing:
		_bgm_player.play()
		_bgm_playing = true

func stop_bgm() -> void:
	_bgm_player.stop()
	_bgm_playing = false

func play_wave_clear() -> void:
	_wave_clear_player.pitch_scale = randf_range(0.95, 1.05)
	_wave_clear_player.play()

func play_boss_entrance() -> void:
	_boss_entrance_player.play()

func play_ui_cancel() -> void:
	_ui_cancel_player.play()

func play_low_hp_warning() -> void:
	if _low_hp_cooldown <= 0.0:
		_low_hp_player.play()
		_low_hp_cooldown = LOW_HP_INTERVAL

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
