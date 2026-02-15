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
var level_thresholds: Array[int] = [10, 25, 50, 80, 120, 170, 230, 300, 380, 470, 570, 680, 800]
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

	match move_id:
		"manual", "":
			# デフォルト: WASD手動操作
			move_dir = _get_manual_input()
		"kite":
			move_dir = _ai_kite(enemies, move_chip.get("params", {}))
		"orbit":
			move_dir = _ai_orbit(enemies, move_chip.get("params", {}), delta)
		"greedy":
			move_dir = _ai_greedy(enemies, move_chip.get("params", {}))
		_:
			move_dir = _get_manual_input()

	if move_dir != Vector2.ZERO:
		facing_dir = move_dir.normalized()

	velocity = move_dir * move_speed * move_speed_mult
	move_and_slide()

	# X軸のみ画面内クランプ（Y軸は無制限 = 縦スクロール）
	position.x = clampf(position.x, 24.0, 1256.0)

	# 進行距離更新（上方向=負のY）
	distance_traveled = maxf(start_y - position.y, distance_traveled)

	# Crush state: 包囲DPS
	_update_crush(enemies, delta)

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

	# ヒットフラッシュ
	modulate = Color(2, 0.5, 0.5, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)

	# Low HP warning（30%以下で警告音）
	if hp > 0 and hp / max_hp <= 0.3:
		SFX.play_low_hp_warning()

	if hp <= 0:
		hp = 0
		tower_destroyed.emit()

func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	tower_damaged.emit(hp, max_hp)

func add_xp(amount: int) -> void:
	xp += amount
	xp_gained.emit(xp, level)
	# レベルアップ判定（連続レベルアップ対応）
	while level - 1 < level_thresholds.size() and xp >= level_thresholds[level - 1]:
		level += 1
		level_up.emit(level)

func get_xp_for_next_level() -> int:
	if level - 1 < level_thresholds.size():
		return level_thresholds[level - 1]
	return 9999  # 上限到達

# --- Screen Shake ---
# Camera2D.offset を揺らして即座に減衰するシンプルなシェイク

var shake_intensity := 0.0
var shake_decay := 8.0  # 減衰速度

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
