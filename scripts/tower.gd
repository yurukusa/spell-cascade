extends CharacterBody2D

## Tower - プレイヤーアバター兼装備台。
## Behavior Chipsで制御されるAI移動。操作機序そのものが装備。
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

func _ready() -> void:
	hp = max_hp
	for i in range(max_slots):
		modules.append(null)
	build_system = get_node("/root/BuildSystem")

func _physics_process(delta: float) -> void:
	var move_chip: Dictionary = build_system.get_equipped_chip("move")
	var move_id: String = move_chip.get("id", "kite")
	var move_dir := Vector2.ZERO

	var enemies := get_tree().get_nodes_in_group("enemies")

	match move_id:
		"kite":
			move_dir = _ai_kite(enemies, move_chip.get("params", {}))
		"orbit":
			move_dir = _ai_orbit(enemies, move_chip.get("params", {}), delta)
		"greedy":
			move_dir = _ai_greedy(enemies, move_chip.get("params", {}))
		_:
			move_dir = _ai_kite(enemies, {})

	velocity = move_dir * move_speed
	move_and_slide()

	# 画面外に出ないようクランプ
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, 24.0, vp.x - 24.0)
	position.y = clampf(position.y, 24.0, vp.y - 24.0)

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
	var center := vp * 0.5
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

	if hp <= 0:
		hp = 0
		tower_destroyed.emit()

func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	tower_damaged.emit(hp, max_hp)
