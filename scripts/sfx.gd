extends Node

## SFX — ランタイム生成サウンドエフェクトマネージャー（Autoload）
## WAVファイルのインポート不要。AudioStreamWAVでPCMデータを直接生成。

# プレイヤープール
var _shot_players: Array[AudioStreamPlayer] = []
var _hit_players: Array[AudioStreamPlayer] = []
var _kill_player: AudioStreamPlayer
var _ui_select_player: AudioStreamPlayer
var _low_hp_player: AudioStreamPlayer

const SHOT_POOL_SIZE := 4
const HIT_POOL_SIZE := 6
var _shot_idx := 0
var _hit_idx := 0

var _low_hp_cooldown := 0.0
const LOW_HP_INTERVAL := 2.0

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

func _process(delta: float) -> void:
	if _low_hp_cooldown > 0.0:
		_low_hp_cooldown -= delta

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
