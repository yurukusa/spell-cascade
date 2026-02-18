extends CharacterBody2D

## Tower - プレイヤーアバター。
## Mirror War: 手動WASD操作がデフォルト。AutoMoveチップで自動化を"勝ち取る"。
## 「プログラムが装備品」= 知識は力。

signal module_changed(slot_index: int)
signal tower_damaged(current_hp: float, max_hp: float)
signal tower_destroyed
signal enemy_killed  # Skill chip "on_kill" トリガー用

@export var max_hp := 500.0
@export var max_slots := 3
@export var move_speed := 200.0

var hp: float
var modules: Array = []  # Array of BuildSystem.TowerModule
var build_system: Node

# Move AI state
var orbit_angle := 0.0  # Orbit chip用
var facing_dir := Vector2.UP  # 最後に向いていた方向（弾の方向用）
var distance_traveled := 0.0  # 進行距離（メートル）
var start_y := 0.0  # 開始Y位置

# XP / レベル
var xp := 0
var level := 1
# レベルアップに必要な累計XP（Lv2=10, Lv3=25, ...）
var level_thresholds: Array[int] = [10, 22, 40, 65, 100, 145, 210, 290, 400, 540, 720, 930, 1180, 1500, 1900, 2400, 3000, 3750, 4700, 5900]  # Lv2-21。v0.5.1: Lv14キャップを撤廃（10分ランで到達可能なLv20+まで拡張）
signal xp_gained(total_xp: int, level: int)
signal level_up(new_level: int)

# ステータス乗数（レベルアップで更新）
var damage_mult := 1.0
var cooldown_mult := 1.0
var projectile_bonus := 0  # 追加弾数
var move_speed_mult := 1.0
var attract_range_bonus := 0.0  # オーブ吸引範囲追加

# Crush state（包囲DPS）
var crush_active := false
var crush_count := 0  # 包囲敵数
var crush_tick_timer := 0.0
var crush_invuln_timer := 0.0
var crush_duration := 0.0  # 連続crush秒数（DPS escalation用）
var crush_breakout_ready := false  # breakout burst準備完了
const CRUSH_RADIUS := 48.0
const CRUSH_THRESHOLD := 3
const CRUSH_BASE_DPS := 6.0
const CRUSH_K_DPS := 4.0
const CRUSH_TICK := 0.2
const CRUSH_INVULN := 0.15
const CRUSH_ESCALATION_RATE := 0.5  # 秒あたりDPS増加倍率
const CRUSH_BREAKOUT_TIME := 3.0  # breakout burst発動までの秒数
const CRUSH_BREAKOUT_DAMAGE := 30.0
const CRUSH_BREAKOUT_RADIUS := 120.0
const CRUSH_BREAKOUT_KNOCKBACK := 80.0

var _tower_core_poly: Polygon2D = null  # HPで色変化するコア（改善40）

# Loop 4 追加変数
var _ambient_ring_timer := 0.0  # 改善109: アンビエントパルスリングタイマー
var _trail_timer := 0.0  # 改善113: 移動トレイルタイマー
var _crush_pulse_timer := 0.0  # 改善108: クラッシュ中のパルスリングタイマー
var _hp_crit_ring_timer := 0.0  # 改善115: HP危機のグローリングタイマー

func _ready() -> void:
	hp = max_hp
	start_y = position.y
	for i in range(max_slots):
		modules.append(null)
	build_system = get_node("/root/BuildSystem")
	_install_stylized_visual()
	_setup_camera()

func _install_stylized_visual() -> void:
	# The current sprite pack reads as "placeholder". Replace with a simple stylized silhouette
	# using Polygon2D only (no new external art), per ops/deep-research-report (1).md:
	# - silhouette first
	# - threats/readability > detail
	# - minimal VFX, no clutter
	var legacy := get_node_or_null("Visual")
	if legacy and legacy is CanvasItem:
		legacy.visible = false

	if get_node_or_null("StylizedVisual") != null:
		return

	var root := Node2D.new()
	root.name = "StylizedVisual"
	add_child(root)

	# Palette: 1 base + 2 accents max (locked)
	var base_dark := Color(0.08, 0.09, 0.12, 1.0)
	var accent := Color(0.35, 0.75, 1.0, 1.0)  # cyan
	var accent2 := Color(0.95, 0.35, 0.70, 1.0)  # magenta

	# Body outline (bigger, behind)
	var outline := Polygon2D.new()
	outline.color = Color(0.02, 0.02, 0.03, 1.0)
	outline.polygon = _make_ngon(10, 30.0)
	root.add_child(outline)

	# Body
	var body := Polygon2D.new()
	body.color = base_dark
	body.polygon = _make_ngon(10, 26.0)
	root.add_child(body)

	# "Cape" / hood cue: one strong silhouette feature
	var cape := Polygon2D.new()
	cape.color = accent2.darkened(0.25)
	cape.polygon = PackedVector2Array([
		Vector2(-10, -6),
		Vector2(-34, 6),
		Vector2(-12, 20),
	])
	root.add_child(cape)
	cape.z_index = -1

	# Core glow (small, readable)
	var core_glow := Polygon2D.new()
	core_glow.color = Color(accent.r, accent.g, accent.b, 0.18)
	core_glow.polygon = _make_ngon(8, 18.0)
	root.add_child(core_glow)

	var core := Polygon2D.new()
	core.color = accent
	core.polygon = _make_ngon(8, 12.0)
	root.add_child(core)
	_tower_core_poly = core  # HP色変化用に参照を保持（改善40）

	# Direction hint (front notch) so "where is facing" is readable even in chaos
	var notch := Polygon2D.new()
	notch.color = accent.lightened(0.15)
	notch.polygon = PackedVector2Array([
		Vector2(18, -4),
		Vector2(32, 0),
		Vector2(18, 4),
	])
	root.add_child(notch)

	# Slight idle pulse (very low amplitude to avoid clutter)
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(core, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(core, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _make_ngon(sides: int, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(maxi(sides, 3)):
		var a := float(i) * TAU / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _setup_camera() -> void:
	# Camera2D: プレイヤー追従で縦スクロール実現
	if get_node_or_null("Camera") != null:
		return
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	# X軸は画面中央にロック、Y軸のみ追従（縦スクロール）
	cam.limit_left = 0
	cam.limit_right = 1280
	add_child(cam)
	cam.make_current()

func _physics_process(delta: float) -> void:
	var move_chip: Dictionary = build_system.get_equipped_chip("move")
	var move_id: String = move_chip.get("id", "manual")
	var move_dir := Vector2.ZERO

	var enemies := get_tree().get_nodes_in_group("enemies")

	# v0.2.6: 手入力は常時優先（AutoMove中でもWASDで即オーバーライド）
	var manual_dir := _get_manual_input()
	if manual_dir != Vector2.ZERO:
		# 手入力あり → AI無視、手入力を使う
		move_dir = manual_dir
	else:
		# 手入力なし → AI移動を使う
		match move_id:
			"manual", "":
				move_dir = Vector2.ZERO  # 手入力なし＆手動モード＝停止
			"kite":
				move_dir = _ai_kite(enemies, move_chip.get("params", {}))
			"orbit":
				move_dir = _ai_orbit(enemies, move_chip.get("params", {}), delta)
			"greedy":
				move_dir = _ai_greedy(enemies, move_chip.get("params", {}))
			_:
				move_dir = Vector2.ZERO

	# Aim: mouse position overrides movement direction
	var mouse_pos := get_global_mouse_position()
	var to_mouse := mouse_pos - global_position
	if to_mouse.length() > 10.0:
		facing_dir = to_mouse.normalized()
	elif move_dir != Vector2.ZERO:
		facing_dir = move_dir.normalized()

	velocity = move_dir * move_speed * move_speed_mult
	move_and_slide()

	# Rotate visual to face aiming direction
	var stylized := get_node_or_null("StylizedVisual")
	if stylized:
		stylized.rotation = facing_dir.angle()

	# X軸のみ画面内クランプ（Y軸は無制限 = 縦スクロール）
	position.x = clampf(position.x, 24.0, 1256.0)

	# 進行距離更新（上方向=負のY）
	distance_traveled = maxf(start_y - position.y, distance_traveled)

	# Crush state: 包囲DPS
	_update_crush(enemies, delta)

	# 改善109: アンビエントパルスリング（タワーの「存在感」を漂わせる、低alpha大リング）
	_ambient_ring_timer -= delta
	if _ambient_ring_timer <= 0:
		_ambient_ring_timer = 3.0
		_spawn_ambient_ring()

	# 改善113: 高速移動時の軌跡ドット（kiteや手動での俊敏な動きが視覚的に伝わる）
	if velocity.length() > 120.0:
		_trail_timer -= delta
		if _trail_timer <= 0:
			_trail_timer = 0.09  # 最大11/秒
			_spawn_move_trail_dot()

	# 改善108: クラッシュ中のパルスリング（「包囲されてる！」緊張感を床から演出）
	if crush_active:
		_crush_pulse_timer -= delta
		if _crush_pulse_timer <= 0:
			_crush_pulse_timer = 0.65
			_spawn_crush_pulse_ring()

	# 改善115: HP低下時の赤グローリング（危機感を空間で表現）
	if max_hp > 0 and hp / max_hp < 0.25 and hp > 0:
		_hp_crit_ring_timer -= delta
		if _hp_crit_ring_timer <= 0:
			_hp_crit_ring_timer = 1.5
			_spawn_hp_crit_ring()

func _get_manual_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	return dir.normalized()

# --- Crush state（包囲DPS）---

signal crush_changed(active: bool, count: int)
signal crush_warning(count: int)  # pre-crush: 1-2 enemies in radius
signal crush_breakout  # breakout burst発動

func _update_crush(enemies: Array, delta: float) -> void:
	# 半径内の敵をカウント（凍結中は除外）
	crush_count = 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= CRUSH_RADIUS:
			crush_count += 1

	var was_active := crush_active
	crush_active = crush_count >= CRUSH_THRESHOLD

	# Pre-crush warning（1-2 enemies in radius）
	if not crush_active and crush_count > 0:
		crush_warning.emit(crush_count)
	elif crush_count == 0:
		crush_warning.emit(0)

	if crush_active != was_active:
		crush_changed.emit(crush_active, crush_count)
		if crush_active:
			# Crush開始: 小ノックバック（逃げ道を作る）
			crush_duration = 0.0
			crush_breakout_ready = false
			_crush_knockback(enemies)
		else:
			# Crush終了: duration リセット
			crush_duration = 0.0
			crush_breakout_ready = false

	if not crush_active:
		crush_tick_timer = 0.0
		crush_invuln_timer = 0.0
		return

	# Crush duration追跡（escalation + breakout用）
	crush_duration += delta

	# Breakout burst: 3秒耐えたらburst発動
	if not crush_breakout_ready and crush_duration >= CRUSH_BREAKOUT_TIME:
		crush_breakout_ready = true
		_do_crush_breakout(enemies)

	# 無敵中はダメージスキップ
	if crush_invuln_timer > 0:
		crush_invuln_timer -= delta
		return

	# DPSティック（時間経過でエスカレーション）
	crush_tick_timer += delta
	if crush_tick_timer >= CRUSH_TICK:
		crush_tick_timer -= CRUSH_TICK
		var base_dps := CRUSH_BASE_DPS + CRUSH_K_DPS * float(crush_count - 2)
		# 時間経過で最大2倍までDPS増加（脱出の緊急性）
		var escalation := 1.0 + minf(crush_duration * CRUSH_ESCALATION_RATE, 1.0)
		var tick_dmg := base_dps * escalation * CRUSH_TICK
		take_damage(tick_dmg)
		crush_invuln_timer = CRUSH_INVULN

		# 視覚: 赤フラッシュ（Crush中のみ、長いほど赤く）
		var intensity := minf(1.0 + crush_duration * 0.15, 2.0)
		modulate = Color(intensity, 0.4, 0.3, 1)
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color.WHITE, 0.1)

func _crush_knockback(enemies: Array) -> void:
	# 最も密集している方向の逆にわずかにノックバック
	var push_dir := Vector2.ZERO
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= CRUSH_RADIUS:
			push_dir -= (e.global_position - global_position).normalized()
	if push_dir.length() > 0:
		position += push_dir.normalized() * 3.0

func _do_crush_breakout(enemies: Array) -> void:
	## Crush 3秒耐えたご褒美: 周囲に衝撃波ダメージ+ノックバック
	crush_breakout.emit()
	shake(6.0)
	# 改善111: BURST後の黄金リング（「耐えた！」の爽快感を即時演出）
	var scene_root := get_tree().current_scene
	if scene_root:
		var gold_ring := Polygon2D.new()
		var pts: PackedVector2Array = []
		for i in range(20):
			var a := float(i) * TAU / 20.0
			pts.append(Vector2(cos(a), sin(a)) * 25.0)
		gold_ring.polygon = pts
		gold_ring.color = Color(1.0, 0.85, 0.2, 0.75)
		gold_ring.global_position = global_position
		gold_ring.z_index = 165
		scene_root.add_child(gold_ring)
		var gt := gold_ring.create_tween()
		gt.set_parallel(true)
		gt.tween_property(gold_ring, "scale", Vector2(6.5, 6.5), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		gt.tween_property(gold_ring, "modulate:a", 0.0, 0.55)
		gt.chain().tween_callback(gold_ring.queue_free)

		# 改善139: 2重目の白い衝撃波（「炸裂した！」余韻のシェル）
		var white_shell := Polygon2D.new()
		var ws_pts: PackedVector2Array = []
		for i in range(24):
			var a := float(i) * TAU / 24.0
			ws_pts.append(Vector2(cos(a), sin(a)) * 30.0)
		white_shell.polygon = ws_pts
		white_shell.color = Color(1.0, 1.0, 1.0, 0.55)
		white_shell.global_position = global_position
		white_shell.z_index = 163
		scene_root.add_child(white_shell)
		var wst := white_shell.create_tween()
		wst.set_parallel(true)
		wst.tween_property(white_shell, "scale", Vector2(5.0, 5.0), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.1)
		wst.tween_property(white_shell, "modulate:a", 0.0, 0.45).set_delay(0.1)
		wst.chain().tween_callback(white_shell.queue_free)

	# 範囲内の全敵にダメージ+ノックバック
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var enemy_pos: Vector2 = e.global_position
		var dist: float = global_position.distance_to(enemy_pos)
		if dist <= CRUSH_BREAKOUT_RADIUS:
			if e.has_method("take_damage"):
				e.take_damage(CRUSH_BREAKOUT_DAMAGE * damage_mult)
			# ノックバック（距離に反比例）
			var knockback_dir: Vector2 = (enemy_pos - global_position).normalized()
			var knockback_force: float = CRUSH_BREAKOUT_KNOCKBACK * (1.0 - dist / CRUSH_BREAKOUT_RADIUS)
			e.position += knockback_dir * knockback_force

# --- Move AI パターン ---

func _ai_kite(enemies: Array, params: Dictionary) -> Vector2:
	## 最寄り敵から距離を取る。角に追い込まれないよう中央バイアス付き。
	if enemies.is_empty():
		return Vector2.ZERO
	var safe_dist: float = params.get("safe_distance", 200)
	var nearest := _find_nearest_valid(enemies)
	if nearest == null:
		return Vector2.ZERO
	var to_enemy := nearest.global_position - global_position
	var dist := to_enemy.length()

	var move_dir := Vector2.ZERO
	if dist < safe_dist:
		move_dir = -to_enemy.normalized()
	elif dist < safe_dist * 1.5:
		move_dir = to_enemy.normalized().rotated(PI * 0.5)

	# 画面端バイアス: 端に近いほど中央方向に引っ張る（角逃げ防止）
	var vp := get_viewport_rect().size
	var _center := vp * 0.5
	var edge_margin := 120.0
	var edge_pull := Vector2.ZERO
	if position.x < edge_margin:
		edge_pull.x = 1.0
	elif position.x > vp.x - edge_margin:
		edge_pull.x = -1.0
	if position.y < edge_margin:
		edge_pull.y = 1.0
	elif position.y > vp.y - edge_margin:
		edge_pull.y = -1.0

	if edge_pull != Vector2.ZERO:
		move_dir = (move_dir + edge_pull.normalized() * 0.6).normalized()

	return move_dir

func _ai_orbit(enemies: Array, params: Dictionary, delta: float) -> Vector2:
	## 敵群の重心を周回する。
	if enemies.is_empty():
		return Vector2.ZERO
	var orbit_dist: float = params.get("orbit_distance", 150)
	var orbit_spd: float = params.get("orbit_speed", 120)

	# 敵群の重心
	var center := Vector2.ZERO
	var count := 0
	for e in enemies:
		if is_instance_valid(e):
			center += e.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	center /= float(count)

	# 現在角度を更新
	orbit_angle += orbit_spd * delta / orbit_dist
	var target_pos := center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_dist
	var to_target := target_pos - global_position
	if to_target.length() < 5.0:
		return Vector2.ZERO
	return to_target.normalized()

func _ai_greedy(_enemies: Array, params: Dictionary) -> Vector2:
	## ドロップ品を優先回収。なければkiteにフォールバック。
	var pickup_range: float = params.get("pickup_range", 300)
	var pickups := get_tree().get_nodes_in_group("pickups")
	if not pickups.is_empty():
		var nearest_pickup: Node2D = null
		var nearest_dist := pickup_range
		for p in pickups:
			if is_instance_valid(p):
				var d := global_position.distance_to(p.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest_pickup = p
		if nearest_pickup:
			return (nearest_pickup.global_position - global_position).normalized()
	# フォールバック: kite
	return _ai_kite(_enemies, {"safe_distance": 200})

func _find_nearest_valid(nodes: Array) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest

# --- Module API ---

func get_module(slot: int):
	if slot >= 0 and slot < modules.size():
		return modules[slot]
	return null

func set_module(slot: int, module) -> void:
	if slot >= 0 and slot < modules.size():
		modules[slot] = module
		module_changed.emit(slot)

func get_filled_modules() -> Array:
	var filled := []
	for m in modules:
		if m != null:
			filled.append(m)
	return filled

func take_damage(amount: float) -> void:
	hp -= amount
	tower_damaged.emit(hp, max_hp)

	# ヒットフラッシュ + スクリーンシェイク（H-5原則: ダメージ量に比例した強度）
	var pct := hp / max_hp
	var shake_amt := 2.5
	if amount >= 50.0:
		shake_amt = 6.0
		modulate = Color(2.5, 0.3, 0.3, 1)  # 大ダメージ: 鮮明な赤
	elif amount >= 20.0:
		shake_amt = 4.0
		modulate = Color(2.2, 0.4, 0.4, 1)
	else:
		modulate = Color(2.0, 0.5, 0.5, 1)
	# 残HP低いほどシェイク強化（危機感増幅）
	if pct <= 0.25:
		shake_amt *= 1.5
	shake(shake_amt)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.18)

	# Low HP warning（30%以下で警告音）
	if hp > 0 and hp / max_hp <= 0.3:
		SFX.play_low_hp_warning()

	# 改善138: 大ダメージ時のUI赤フラッシュ（50+ダメージ: 「重い一撃」を全画面で）
	if amount >= 50.0:
		var scene_root := get_tree().current_scene
		if scene_root:
			var ui := scene_root.get_node_or_null("UI") as CanvasLayer
			if ui:
				var big_dmg_flash := ColorRect.new()
				big_dmg_flash.color = Color(0.9, 0.05, 0.05, 0.22)
				big_dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
				big_dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
				big_dmg_flash.z_index = 162
				ui.add_child(big_dmg_flash)
				var bdf := big_dmg_flash.create_tween()
				bdf.tween_property(big_dmg_flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC)
				bdf.tween_callback(big_dmg_flash.queue_free)

	_update_low_hp_glow()
	_update_tower_core_color()

	if hp <= 0:
		hp = 0
		tower_destroyed.emit()

func heal(amount: float) -> void:
	var healed := minf(amount, max_hp - hp)  # 実際に回復した量
	hp = minf(hp + amount, max_hp)
	tower_damaged.emit(hp, max_hp)
	_update_low_hp_glow()
	_update_tower_core_color()
	if healed > 0.5:
		_spawn_heal_vfx(healed)

func _spawn_heal_vfx(amount: float) -> void:
	## 回復時の緑フラッシュ + "+N HP" テキスト（G-10: ダメージモーション回復版）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var label := Label.new()
	label.text = "+%d HP" % int(amount)
	label.add_theme_font_size_override("font_size", 24)  # 改善66: 20→24、回復の視認性向上
	label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.4, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 150
	label.global_position = global_position + Vector2(randf_range(-15, 15), -40)
	scene_root.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y - 55.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
	# タワー緑フラッシュ（回復の知覚）
	modulate = Color(0.4, 2.2, 0.5, 1.0)
	var flash := create_tween()
	flash.tween_property(self, "modulate", Color.WHITE, 0.3)

	# 改善92: 回復時に緑の拡散リング（「回復した！」瞬間を爽快に見せる）
	var ring := Polygon2D.new()
	var ring_pts: PackedVector2Array = []
	for i in range(16):
		var ra := float(i) * TAU / 16.0
		ring_pts.append(Vector2(cos(ra), sin(ra)) * 18.0)
	ring.polygon = ring_pts
	ring.color = Color(0.3, 0.95, 0.4, 0.55)
	ring.global_position = global_position
	ring.z_index = 140
	scene_root.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector2(3.5, 3.5), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring, "modulate:a", 0.0, 0.4)
	ring_tween.chain().tween_callback(ring.queue_free)

func _spawn_level_up_burst() -> void:
	## 改善110: レベルアップ時の放射パーティクル（「強くなった！」を爆発で体感）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in range(10):
		var a := float(i) * TAU / 10.0 + randf() * 0.2
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-2.5, -0.8), Vector2(2.5, 0.0), Vector2(-2.5, 0.8),
		])
		p.color = Color(0.6, 0.95, 1.0, 1.0)  # タワーシアン
		p.rotation = a
		p.global_position = global_position
		p.z_index = 145
		scene_root.add_child(p)
		var t := p.create_tween()
		t.set_parallel(true)
		t.tween_property(p, "global_position", global_position + Vector2(cos(a), sin(a)) * randf_range(45.0, 80.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "modulate:a", 0.0, 0.55).set_delay(0.2)
		t.chain().tween_callback(p.queue_free)
	# 大きな白フラッシュリング
	var glow := Polygon2D.new()
	var glow_pts: PackedVector2Array = []
	for i in range(16):
		var a := float(i) * TAU / 16.0
		glow_pts.append(Vector2(cos(a), sin(a)) * 22.0)
	glow.polygon = glow_pts
	glow.color = Color(0.6, 0.95, 1.0, 0.6)
	glow.global_position = global_position
	glow.z_index = 144
	scene_root.add_child(glow)
	var gt := glow.create_tween()
	gt.set_parallel(true)
	gt.tween_property(glow, "scale", Vector2(4.0, 4.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gt.tween_property(glow, "modulate:a", 0.0, 0.4)
	gt.chain().tween_callback(glow.queue_free)

func _spawn_ambient_ring() -> void:
	## 改善109: 低alpha大リング（タワーのプレゼンス演出。クラッチ感・重みを加える）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ring := Polygon2D.new()
	var ring_pts: PackedVector2Array = []
	for i in range(12):
		var a := float(i) * TAU / 12.0
		ring_pts.append(Vector2(cos(a), sin(a)) * 20.0)
	ring.polygon = ring_pts
	ring.color = Color(0.35, 0.75, 1.0, 0.06)  # タワーのシアンカラー、極低alpha
	ring.global_position = global_position
	ring.z_index = -5
	scene_root.add_child(ring)
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(5.0, 5.0), 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 2.5).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)

func _spawn_move_trail_dot() -> void:
	## 改善113: 移動中の軌跡ドット（俊敏な動きを視覚化）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var dot := Polygon2D.new()
	var dot_pts: PackedVector2Array = []
	for i in range(6):
		var a := float(i) * TAU / 6.0
		dot_pts.append(Vector2(cos(a), sin(a)) * 4.0)
	dot.polygon = dot_pts
	dot.color = Color(0.35, 0.75, 1.0, 0.35)
	dot.global_position = global_position
	dot.z_index = -3
	scene_root.add_child(dot)
	var t := dot.create_tween()
	t.set_parallel(true)
	t.tween_property(dot, "scale", Vector2(2.0, 2.0), 0.28)
	t.tween_property(dot, "modulate:a", 0.0, 0.28)
	t.chain().tween_callback(dot.queue_free)

func _spawn_crush_pulse_ring() -> void:
	## 改善108: クラッシュ中の橙パルスリング（「包囲プレッシャー」を床で示す）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ring := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(16):
		pts.append(Vector2(cos(i * TAU / 16.0), sin(i * TAU / 16.0)) * 20.0)
	ring.polygon = pts
	ring.color = Color(1.0, 0.45, 0.1, 0.45)
	ring.global_position = global_position
	ring.z_index = -4
	scene_root.add_child(ring)
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(CRUSH_RADIUS / 20.0 * 1.15, CRUSH_RADIUS / 20.0 * 1.15), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.55)
	t.chain().tween_callback(ring.queue_free)

func _spawn_hp_crit_ring() -> void:
	## 改善115: HP25%以下時の赤グローリング（空間で危機感を表現）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ring := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(12):
		pts.append(Vector2(cos(i * TAU / 12.0), sin(i * TAU / 12.0)) * 16.0)
	ring.polygon = pts
	ring.color = Color(0.95, 0.1, 0.1, 0.30)
	ring.global_position = global_position
	ring.z_index = -2
	scene_root.add_child(ring)
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(5.0, 5.0), 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(ring, "modulate:a", 0.0, 1.0).set_delay(0.25)
	t.chain().tween_callback(ring.queue_free)

func _update_tower_core_color() -> void:
	## コア色をHP割合でシアン→オレンジ→赤に変化（改善40: タワーの危機感を視覚化）
	if _tower_core_poly == null or not is_instance_valid(_tower_core_poly):
		return
	var pct := clampf(hp / max_hp, 0.0, 1.0)
	var cyan   := Color(0.35, 0.75, 1.0, 1.0)
	var orange := Color(1.0, 0.65, 0.15, 1.0)
	var red    := Color(1.0, 0.22, 0.12, 1.0)
	if pct > 0.5:
		_tower_core_poly.color = cyan.lerp(orange, (1.0 - pct) * 2.0)
	else:
		_tower_core_poly.color = orange.lerp(red, (0.5 - pct) * 2.0)

func add_xp(amount: int) -> void:
	xp += amount
	xp_gained.emit(xp, level)
	# レベルアップ判定（連続レベルアップ対応）
	while level - 1 < level_thresholds.size() and xp >= level_thresholds[level - 1]:
		level += 1
		level_up.emit(level)
		# 改善110: レベルアップ放射パーティクルバースト（達成感の即時フィードバック）
		_spawn_level_up_burst()
		# 改善112: タワー本体スケールポップ（「成長した！」を身体で感じる）
		var lup_tween := create_tween()
		lup_tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.1).set_trans(Tween.TRANS_BACK)
		lup_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC)

func get_xp_for_next_level() -> int:
	if level - 1 < level_thresholds.size():
		return level_thresholds[level - 1]
	# 配列超過: 最後の閾値から25%ずつ増加（天井なし、減速あり）
	var last := level_thresholds[level_thresholds.size() - 1]
	var extra_levels := level - 1 - level_thresholds.size()
	return int(float(last) * pow(1.25, extra_levels + 1))

# --- Screen Shake ---
# Camera2D.offset を揺らして即座に減衰するシンプルなシェイク

var shake_intensity := 0.0
var shake_decay := 8.0  # 減衰速度

# 低HP持続グロー（25%以下で赤いパルスリング）
var _low_hp_glow: Polygon2D = null
var _low_hp_tween: Tween = null

func _update_low_hp_glow() -> void:
	## 低HP時の赤いパルスリング（危機感の持続的可視化: 死の瀬戸際を体感させる）
	var pct := hp / max_hp
	if pct <= 0.25 and hp > 0:
		# 改善91: HP割合で脈動速度を可変。低HPほど速くパルスして「もうダメだ」感を増幅
		var pulse_speed := lerpf(0.16, 0.35, pct / 0.25)  # 0% → 0.16s(高速), 25% → 0.35s(低速)
		if _low_hp_glow == null or not is_instance_valid(_low_hp_glow):
			_low_hp_glow = Polygon2D.new()
			_low_hp_glow.name = "LowHPGlow"
			var pts: PackedVector2Array = []
			for i in range(16):
				var a := float(i) * TAU / 16.0
				pts.append(Vector2(cos(a), sin(a)) * 42.0)
			_low_hp_glow.polygon = pts
			_low_hp_glow.color = Color(1.0, 0.08, 0.08, 0.2)
			_low_hp_glow.z_index = -1
			add_child(_low_hp_glow)
		# HP変化のたびに速度更新（改善91: 常に現在のHPに合ったパルス速度）
		if _low_hp_tween != null:
			_low_hp_tween.kill()
		_low_hp_tween = _low_hp_glow.create_tween()
		_low_hp_tween.set_loops()
		_low_hp_tween.tween_property(_low_hp_glow, "scale", Vector2(1.4, 1.4), pulse_speed).set_trans(Tween.TRANS_SINE)
		_low_hp_tween.tween_property(_low_hp_glow, "scale", Vector2(1.0, 1.0), pulse_speed).set_trans(Tween.TRANS_SINE)
	else:
		if _low_hp_glow != null and is_instance_valid(_low_hp_glow):
			if _low_hp_tween != null:
				_low_hp_tween.kill()
				_low_hp_tween = null
			_low_hp_glow.queue_free()
			_low_hp_glow = null

func shake(intensity: float = 3.0) -> void:
	# 累積ではなく、より強い方を採用（連続ヒットで揺れすぎない）
	shake_intensity = maxf(shake_intensity, intensity)

func _process(delta: float) -> void:
	if shake_intensity > 0.01:
		var cam := get_node_or_null("Camera")
		if cam and cam is Camera2D:
			cam.offset = Vector2(
				randf_range(-shake_intensity, shake_intensity),
				randf_range(-shake_intensity, shake_intensity)
			)
		shake_intensity = lerpf(shake_intensity, 0.0, shake_decay * delta)
	else:
		shake_intensity = 0.0
		var cam := get_node_or_null("Camera")
		if cam and cam is Camera2D:
			cam.offset = Vector2.ZERO
