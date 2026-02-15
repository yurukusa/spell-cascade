extends Node2D

## TowerAttack - タワーの各スロットの攻撃処理。
## BuildSystemから計算されたステータスに基づいて弾を生成。
## Attack ChipとSkill Chipで照準と発動条件を制御。

var slot_index: int = 0
var stats: Dictionary = {}
var timer := 0.0
var is_first_strike := true
var build_system: Node

# Skill chip state
var pending_on_kill := false  # on_kill チップ: キル後に発動待ち

func setup(idx: int, calculated_stats: Dictionary) -> void:
	slot_index = idx
	stats = calculated_stats
	timer = 0.0
	is_first_strike = true
	build_system = get_node("/root/BuildSystem")

	# on_killトリガー接続
	var tower_node := get_parent()
	if tower_node and tower_node.has_signal("enemy_killed"):
		if not tower_node.enemy_killed.is_connected(_on_enemy_killed):
			tower_node.enemy_killed.connect(_on_enemy_killed)

func _process(delta: float) -> void:
	if stats.is_empty():
		return

	var cooldown: float = stats.get("cooldown", 1.0)
	var skill_chip: Dictionary = build_system.get_equipped_chip("skill")
	var skill_id: String = skill_chip.get("id", "auto_cast")

	# first_strike_instant: アイドル後の最初の攻撃は即発動
	if is_first_strike and stats.get("first_strike_instant", false):
		is_first_strike = false
		_fire()
		return

	# Skill chipによる発動条件分岐
	match skill_id:
		"auto_cast":
			# CD毎に自動発射
			timer += delta
			if timer >= cooldown:
				timer -= cooldown
				is_first_strike = false
				_fire()

		"on_kill":
			# キル後にバースト発射
			timer += delta
			if pending_on_kill and timer >= cooldown:
				timer -= cooldown
				is_first_strike = false
				var burst: int = skill_chip.get("params", {}).get("burst_count", 2)
				for i in range(burst):
					_fire()
				pending_on_kill = false

		"panic":
			# HP低下時にCD短縮して連射
			var tower_node := get_parent()
			var hp_pct := 1.0
			if tower_node and "hp" in tower_node and "max_hp" in tower_node:
				hp_pct = tower_node.hp / tower_node.max_hp
			var threshold: float = skill_chip.get("params", {}).get("hp_threshold", 0.3)
			var cd_mult: float = skill_chip.get("params", {}).get("cooldown_mult", 0.5)
			var effective_cd := cooldown
			if hp_pct < threshold:
				effective_cd = cooldown * cd_mult  # パニック時はCD半分
			timer += delta
			if timer >= effective_cd:
				timer -= effective_cd
				is_first_strike = false
				_fire()

		_:
			# フォールバック: auto_cast
			timer += delta
			if timer >= cooldown:
				timer -= cooldown
				_fire()

func _on_enemy_killed() -> void:
	pending_on_kill = true

func _fire() -> void:
	# misfire判定
	if stats.get("misfire_chance", 0) > 0:
		if randf() < stats["misfire_chance"]:
			return  # 不発

	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	# spread挙動: 全方向に撃つ
	for behavior in stats.get("behaviors", []):
		if behavior.get("type", "") == "spread":
			_fire_spread(behavior.get("directions", 8))
			return

	# areaスキル: 8方向に拡散（Poison Nova等）
	var area_radius: float = stats.get("area_radius", 0)
	if area_radius > 0:
		_fire_spread(8)
		return

	# Attack chipで方向決定
	var direction := _get_aim_direction(enemies)
	if direction == Vector2.ZERO:
		return
	var proj_count: int = stats.get("projectile_count", 1)
	var spread_angle: float = stats.get("spread_angle", 0)

	if proj_count <= 1:
		_create_projectile(direction)
	else:
		# 複数弾: spread_angleの範囲で均等配置
		var start_angle := direction.angle() - deg_to_rad(spread_angle / 2.0)
		var step: float = deg_to_rad(spread_angle) / maxf(float(proj_count - 1), 1.0)
		for i in range(proj_count):
			var angle: float = start_angle + step * float(i)
			var dir := Vector2(cos(angle), sin(angle))
			_create_projectile(dir)

func _fire_spread(directions: int) -> void:
	for i in range(directions):
		var angle := i * TAU / directions
		var dir := Vector2(cos(angle), sin(angle))
		_create_projectile(dir)

func _get_aim_direction(enemies: Array) -> Vector2:
	## Attack chipに基づいてターゲット方向を決定
	var attack_chip: Dictionary = build_system.get_equipped_chip("attack")
	var attack_id: String = attack_chip.get("id", "aim_nearest")

	match attack_id:
		"aim_nearest":
			var nearest := _find_nearest_enemy(enemies)
			if nearest:
				return (nearest.global_position - global_position).normalized()

		"aim_highest_hp":
			var target := _find_highest_hp_enemy(enemies)
			if target:
				return (target.global_position - global_position).normalized()

		"aim_cluster":
			var cluster_pos := _find_cluster_center(enemies, attack_chip.get("params", {}).get("cluster_radius", 100))
			if cluster_pos != Vector2.ZERO:
				return (cluster_pos - global_position).normalized()

		_:
			var nearest := _find_nearest_enemy(enemies)
			if nearest:
				return (nearest.global_position - global_position).normalized()

	return Vector2.ZERO

func _find_nearest_enemy(enemies: Array) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	var attack_range: float = stats.get("range", 200)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist and dist <= attack_range:
			nearest_dist = dist
			nearest = enemy

	return nearest

func _find_highest_hp_enemy(enemies: Array) -> Node2D:
	var target: Node2D = null
	var highest_hp := -1.0
	var attack_range: float = stats.get("range", 200)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist > attack_range:
			continue
		var enemy_hp: float = enemy.get("hp") if "hp" in enemy else 0.0
		if enemy_hp > highest_hp:
			highest_hp = enemy_hp
			target = enemy

	return target

func _find_cluster_center(enemies: Array, cluster_radius: float) -> Vector2:
	## 最も密集している場所の重心を返す
	var attack_range: float = stats.get("range", 200)
	var best_center := Vector2.ZERO
	var best_count := 0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) > attack_range:
			continue
		# この敵の周りにどれだけ敵がいるか
		var count := 0
		var center := Vector2.ZERO
		for other in enemies:
			if not is_instance_valid(other):
				continue
			if enemy.global_position.distance_to(other.global_position) <= cluster_radius:
				count += 1
				center += other.global_position
		if count > best_count:
			best_count = count
			best_center = center / float(count)

	return best_center

func _create_projectile(direction: Vector2) -> void:
	var bullet := Area2D.new()
	bullet.name = "Bullet"
	bullet.add_to_group("bullets")
	bullet.global_position = global_position

	# コリジョン
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	col.shape = shape
	bullet.add_child(col)

	# ビジュアル（Design Lock: 10px core + 18px glow, 3:1 contrast vs BG）
	var color := _get_bullet_color()

	# 外側グロー（形状認識 + 存在感）
	var glow := Polygon2D.new()
	var glow_points: PackedVector2Array = []
	for i in range(8):
		var angle := i * TAU / 8
		glow_points.append(Vector2(cos(angle), sin(angle)) * 18.0)
	glow.polygon = glow_points
	glow.color = Color(color.r, color.g, color.b, 0.3)
	bullet.add_child(glow)

	# 本体（六角形コア）
	var visual := Polygon2D.new()
	var points: PackedVector2Array = []
	for i in range(6):
		var angle := i * TAU / 6
		points.append(Vector2(cos(angle), sin(angle)) * 10.0)
	visual.polygon = points
	visual.color = color
	bullet.add_child(visual)

	# ホットスポット（中心の明るい点 — 弾道の視認性向上）
	var hotspot := Polygon2D.new()
	var hs_points: PackedVector2Array = []
	for i in range(4):
		var angle := i * TAU / 4
		hs_points.append(Vector2(cos(angle), sin(angle)) * 3.0)
	hotspot.polygon = hs_points
	hotspot.color = Color(minf(color.r + 0.4, 1.0), minf(color.g + 0.4, 1.0), minf(color.b + 0.4, 1.0), 0.9)
	bullet.add_child(hotspot)

	# 弾スクリプト
	var script := GDScript.new()
	script.source_code = _build_bullet_script()
	script.reload()
	bullet.set_script(script)
	bullet.set("direction", direction)
	bullet.set("speed", 350.0)
	bullet.set("damage", stats.get("damage", 10))
	bullet.set("lifetime", 3.0)
	bullet.set("behaviors", stats.get("behaviors", []))
	bullet.set("pierce_remaining", _get_pierce_count())
	bullet.set("chain_remaining", _get_chain_count())
	bullet.set("chain_range", _get_chain_range())
	bullet.set("fork_count", _get_fork_count())
	bullet.set("fork_angle", _get_fork_angle())

	bullet.collision_layer = 2
	bullet.collision_mask = 4

	get_tree().current_scene.add_child(bullet)

	# self_damage_per_attack
	if stats.get("self_damage_per_attack", 0) > 0:
		var tower := get_parent()
		if tower and tower.has_method("take_damage"):
			tower.take_damage(stats["self_damage_per_attack"])

func _get_bullet_color() -> Color:
	var tags: Array = stats.get("tags", [])
	if "fire" in tags:
		return Color(1.0, 0.4, 0.1, 0.9)
	elif "cold" in tags:
		return Color(0.3, 0.7, 1.0, 0.9)
	elif "lightning" in tags:
		return Color(1.0, 1.0, 0.3, 0.9)
	elif "chaos" in tags:
		return Color(0.4, 0.9, 0.2, 0.9)
	elif "holy" in tags:
		return Color(1.0, 0.95, 0.7, 0.9)
	return Color(0.8, 0.8, 0.9, 0.9)

func _get_pierce_count() -> int:
	if stats.get("pierce", false):
		return 3  # スキル自体がpierceの場合
	for b in stats.get("behaviors", []):
		if b.get("type", "") == "pierce":
			return b.get("pierce_count", 3)
	return 0

func _get_chain_count() -> int:
	for b in stats.get("behaviors", []):
		if b.get("type", "") == "chain":
			return b.get("chain_count", 2)
	return 0

func _get_chain_range() -> float:
	for b in stats.get("behaviors", []):
		if b.get("type", "") == "chain":
			return b.get("chain_range", 150.0)
	return 0.0

func _get_fork_count() -> int:
	for b in stats.get("behaviors", []):
		if b.get("type", "") == "fork":
			return b.get("fork_count", 2)
	return 0

func _get_fork_angle() -> float:
	for b in stats.get("behaviors", []):
		if b.get("type", "") == "fork":
			return b.get("fork_angle", 30.0)
	return 30.0

func _build_bullet_script() -> String:
	# 弾の挙動を動的に生成
	return """extends Area2D

var direction := Vector2.ZERO
var speed := 350.0
var damage := 10
var lifetime := 3.0
var behaviors := []
var pierce_remaining := 0
var chain_remaining := 0
var chain_range := 150.0
var fork_count := 0
var fork_angle := 30.0
var hit_enemies := []

func _ready():
	body_entered.connect(_on_body_entered)
	collision_layer = 2
	collision_mask = 4

func _process(delta):
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

func _on_body_entered(body):
	if not body.has_method(\"take_damage\"):
		return
	if body in hit_enemies:
		return

	body.take_damage(damage)
	hit_enemies.append(body)

	# enemy_killed シグナル（on_killチップ用）
	if \"hp\" in body and body.hp <= 0:
		var tower := get_tree().current_scene.get_node_or_null(\"Tower\")
		if tower and tower.has_signal(\"enemy_killed\"):
			tower.enemy_killed.emit()

	# Chain: 次の敵にバウンス
	if chain_remaining > 0:
		chain_remaining -= 1
		var next := _find_chain_target(body)
		if next:
			direction = (next.global_position - global_position).normalized()
			return  # 弾は消えない

	# Fork: 分裂
	if fork_count > 0:
		_do_fork(body)

	# Pierce: 貫通
	if pierce_remaining > 0:
		pierce_remaining -= 1
		return  # 弾は消えない

	queue_free()

func _find_chain_target(exclude_body) -> Node2D:
	var enemies := get_tree().get_nodes_in_group(\"enemies\")
	var nearest: Node2D = null
	var nearest_dist := chain_range

	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy == exclude_body or enemy in hit_enemies:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest

func _do_fork(_hit_body):
	# Fork弾を生成（fork_countは0にして無限分裂を防止）
	var base_angle := direction.angle()
	for i in range(2):
		var offset := deg_to_rad(fork_angle) * (i * 2 - 1) * 0.5
		var fork_dir := Vector2(cos(base_angle + offset), sin(base_angle + offset))

		var fork_bullet := Area2D.new()
		fork_bullet.name = \"ForkBullet\"
		fork_bullet.add_to_group(\"bullets\")
		fork_bullet.global_position = global_position

		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		fork_bullet.add_child(col)

		var visual := Polygon2D.new()
		var points: PackedVector2Array = []
		for j in range(6):
			var angle := j * TAU / 6
			points.append(Vector2(cos(angle), sin(angle)) * 3.0)
		visual.polygon = points
		visual.color = Color(0.9, 0.9, 1.0, 0.8)
		fork_bullet.add_child(visual)

		# 簡易スクリプト（fork弾はこれ以上分裂しない）
		var s := GDScript.new()
		s.source_code = \"\"\"extends Area2D
var direction := Vector2.ZERO
var speed := 350.0
var damage := 5
var lifetime := 1.5

func _ready():
	body_entered.connect(func(body):
		if body.has_method(\\\"take_damage\\\"):
			body.take_damage(damage)
		queue_free()
	)
	collision_layer = 2
	collision_mask = 4

func _process(delta):
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
\"\"\"
		s.reload()
		fork_bullet.set_script(s)
		fork_bullet.set(\"direction\", fork_dir)
		fork_bullet.set(\"damage\", int(damage * 0.6))

		get_tree().current_scene.add_child(fork_bullet)
"""
