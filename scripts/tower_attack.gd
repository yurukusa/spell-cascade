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
var _echo_firing := false     # echo再帰防止

# テレメトリ（自動テスト用）
var fire_count := 0
var last_fire_time := 0.0

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
	# レベルアップ乗数適用
	var tower_node := get_parent()
	if tower_node and "cooldown_mult" in tower_node:
		cooldown *= tower_node.cooldown_mult
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

	# v0.2.6: 敵不在でも発射する（facing方向に撃つ）
	var enemies := get_tree().get_nodes_in_group("enemies")

	SFX.play_shot()

	# echo: 30%追加発動（再帰防止フラグ付き）
	if not _echo_firing and stats.get("echo_chance", 0.0) > 0:
		if randf() < stats["echo_chance"]:
			_echo_firing = true
			call_deferred("_fire")
			_echo_firing = false
	fire_count += 1
	last_fire_time = Time.get_ticks_msec() / 1000.0
	if fire_count <= 3 or fire_count % 10 == 0:
		var skill_name: String = stats.get("name", "?")
		var tags: Array = stats.get("tags", [])
		print("[TELEMETRY] slot=%d skill=%s tags=%s fire_count=%d" % [slot_index, skill_name, str(tags), fire_count])

	# Summon Wisp: 追従ウィスプ召喚（通常projectileではない）
	var skill_id_str: String = stats.get("skill_id", "")
	if skill_id_str == "summon_wisp":
		_summon_wisp()
		return

	# Meteor: 遅延AoE落下（通常projectileではない）
	if skill_id_str == "meteor":
		_fire_meteor(enemies)
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

	# Attack chipで方向決定（v0.2.6: 敵不在時はfacing方向にフォールバック）
	var direction := _get_aim_direction(enemies)
	if direction == Vector2.ZERO:
		var tower_ref2 := get_parent()
		if tower_ref2 and "facing_dir" in tower_ref2:
			direction = tower_ref2.facing_dir
		else:
			direction = Vector2.UP
	var proj_count: int = stats.get("projectile_count", 1)
	# レベルアップの追加弾数
	var tower_ref := get_parent()
	if tower_ref and "projectile_bonus" in tower_ref:
		proj_count += tower_ref.projectile_bonus
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

func _summon_wisp() -> void:
	## 追従ウィスプを召喚。10秒間タワー周囲を周回しながら自動攻撃。
	## 通常projectileとは別系統 — 独立したNode2Dとして生成。
	var wisp := Area2D.new()
	wisp.name = "Wisp"
	wisp.add_to_group("wisps")
	wisp.global_position = global_position + Vector2(30, 0)

	# コリジョン（敵検知用）
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	wisp.add_child(col)
	wisp.collision_layer = 2
	wisp.collision_mask = 4

	# ビジュアル: シアンの球体 + グロー
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(10, 16.0)
	glow.color = Color(0.2, 0.9, 1.0, 0.2)
	wisp.add_child(glow)

	var body := Polygon2D.new()
	body.polygon = _make_ngon(8, 8.0)
	body.color = Color(0.3, 0.95, 1.0, 0.85)
	wisp.add_child(body)

	var core := Polygon2D.new()
	core.polygon = _make_ngon(5, 3.0)
	core.color = Color(0.8, 1.0, 1.0, 0.95)
	wisp.add_child(core)

	# ウィスプの挙動スクリプト
	var base_dmg: float = stats.get("damage", 6)
	var t := get_parent()
	if t and "damage_mult" in t:
		base_dmg *= t.damage_mult
	var attack_cd: float = stats.get("summon_attack_cd", 0.8)
	var duration: float = stats.get("summon_duration", 10.0)
	var atk_range: float = stats.get("range", 250)

	var script := GDScript.new()
	script.source_code = _build_wisp_script()
	script.reload()
	wisp.set_script(script)
	wisp.set("damage", int(base_dmg))
	wisp.set("attack_cooldown", attack_cd)
	wisp.set("duration", duration)
	wisp.set("attack_range", atk_range)
	wisp.set("orbit_center", global_position)
	wisp.set("orbit_radius", 40.0)

	get_tree().current_scene.add_child(wisp)

func _build_wisp_script() -> String:
	# ウィスプAI: タワー周囲を周回 + 最寄り敵に自動攻撃
	return """extends Area2D

var damage := 6
var attack_cooldown := 0.8
var duration := 10.0
var attack_range := 250.0
var orbit_center := Vector2.ZERO
var orbit_radius := 40.0
var _orbit_angle := 0.0
var _attack_timer := 0.0
var _lifetime := 0.0

func _process(delta):
	_lifetime += delta
	if _lifetime >= duration:
		queue_free()
		return

	# フェードアウト（残り2秒で透明化開始）
	if duration - _lifetime < 2.0:
		modulate.a = (duration - _lifetime) / 2.0

	# タワー追従（タワーが動いた場合に対応）
	var tower := get_tree().current_scene.get_node_or_null(\"Tower\")
	if tower:
		orbit_center = tower.global_position

	# 周回運動（毎秒1.5rad = 約14秒で一周、ゆったり）
	_orbit_angle += 1.5 * delta
	global_position = orbit_center + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * orbit_radius

	# 自動攻撃
	_attack_timer += delta
	if _attack_timer >= attack_cooldown:
		var target := _find_nearest()
		if target:
			_attack_timer = 0.0
			_fire_at(target)

func _find_nearest() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := attack_range
	for e in get_tree().get_nodes_in_group(\"enemies\"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

func _fire_at(target: Node2D):
	# シンプルな追尾弾
	var b := Area2D.new()
	b.name = \"WispBolt\"
	b.add_to_group(\"bullets\")
	b.global_position = global_position

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	b.add_child(col)

	# 小さなシアンの弾
	var vis := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(5):
		var a := float(i) * TAU / 5.0
		pts.append(Vector2(cos(a), sin(a)) * 4.0)
	vis.polygon = pts
	vis.color = Color(0.3, 0.95, 1.0, 0.8)
	b.add_child(vis)

	b.collision_layer = 2
	b.collision_mask = 4

	var dir := (target.global_position - global_position).normalized()
	var s := GDScript.new()
	s.source_code = \"extends Area2D\\nvar direction := Vector2.ZERO\\nvar speed := 400.0\\nvar damage := 6\\nvar lifetime := 2.0\\n\\nfunc _ready():\\n\\tbody_entered.connect(func(body):\\n\\t\\tif body.has_method(\\\\\\\"take_damage\\\\\\\"):\\n\\t\\t\\tbody.take_damage(damage)\\n\\t\\tset_deferred(\\\\\\\"monitoring\\\\\\\", false)\\n\\t\\tcall_deferred(\\\\\\\"queue_free\\\\\\\")\\n\\t)\\n\\tcollision_layer = 2\\n\\tcollision_mask = 4\\n\\nfunc _process(delta):\\n\\tposition += direction * speed * delta\\n\\tlifetime -= delta\\n\\tif lifetime <= 0:\\n\\t\\tset_deferred(\\\\\\\"monitoring\\\\\\\", false)\\n\\t\\tcall_deferred(\\\\\\\"queue_free\\\\\\\")\\n\"
	s.reload()
	b.set_script(s)
	b.set(\"direction\", dir)
	b.set(\"damage\", damage)
	get_tree().current_scene.add_child(b)
"""

func _fire_meteor(enemies: Array) -> void:
	## Meteor: 敵が最も密集した場所に遅延AoE落下。
	## 0.8秒の予告表示後に爆発 — 大ダメージ・広範囲。
	var target_pos := _find_cluster_center(enemies, 80.0)
	if target_pos == Vector2.ZERO:
		# 敵がいない場合、タワー前方に落とす
		var t := get_parent()
		if t and "facing_dir" in t:
			target_pos = global_position + t.facing_dir * 150.0
		else:
			target_pos = global_position + Vector2.UP * 150.0

	var base_dmg: float = stats.get("damage", 60)
	var t := get_parent()
	if t and "damage_mult" in t:
		base_dmg *= t.damage_mult
	var area_r: float = stats.get("area_radius", 80)
	var delay: float = stats.get("meteor_delay", 0.8)

	# 予告マーカー（赤い円が縮小→爆発）
	var marker := Node2D.new()
	marker.name = "MeteorMarker"
	marker.global_position = target_pos
	get_tree().current_scene.add_child(marker)

	# 外周警告円
	var ring := Polygon2D.new()
	ring.polygon = _make_ngon(20, area_r)
	ring.color = Color(1.0, 0.3, 0.1, 0.2)
	marker.add_child(ring)

	# 内側ターゲット
	var inner := Polygon2D.new()
	inner.polygon = _make_ngon(12, 10.0)
	inner.color = Color(1.0, 0.5, 0.1, 0.5)
	marker.add_child(inner)

	# 縮小アニメーション（ring → 中心へ）
	var tween := marker.create_tween()
	tween.tween_property(ring, "scale", Vector2(0.1, 0.1), delay)
	tween.tween_callback(func():
		# 爆発ダメージ
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and target_pos.distance_to(e.global_position) <= area_r:
				e.take_damage(int(base_dmg))

		# 爆発VFX
		_spawn_meteor_explosion(target_pos, area_r)

		# enemy_killedシグナル（on_killチップ用）
		var tower := get_tree().current_scene.get_node_or_null("Tower")
		if tower and tower.has_signal("enemy_killed"):
			for e2 in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e2) and "hp" in e2 and e2.hp <= 0:
					tower.enemy_killed.emit()

		marker.queue_free()
	)

func _spawn_meteor_explosion(pos: Vector2, radius: float) -> void:
	## Meteor着弾VFX: オレンジ→赤のフラッシュ + 拡散パーティクル
	var vfx := Node2D.new()
	vfx.global_position = pos
	get_tree().current_scene.add_child(vfx)

	# 爆発フラッシュ（大きな円）
	var flash := Polygon2D.new()
	flash.polygon = _make_ngon(16, radius * 0.8)
	flash.color = Color(1.0, 0.6, 0.1, 0.8)
	vfx.add_child(flash)

	# 内部の白いコア
	var core := Polygon2D.new()
	core.polygon = _make_ngon(10, radius * 0.3)
	core.color = Color(1.0, 0.95, 0.7, 0.9)
	vfx.add_child(core)

	# フェードアウト
	var tw := vfx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(1.5, 1.5), 0.4)
	tw.tween_property(flash, "color:a", 0.0, 0.4)
	tw.tween_property(core, "scale", Vector2(2.0, 2.0), 0.3)
	tw.tween_property(core, "color:a", 0.0, 0.3)
	tw.chain().tween_callback(vfx.queue_free)

	# 破片パーティクル（8個の小さなオレンジ片が飛散）
	for i in range(8):
		var frag := Polygon2D.new()
		frag.polygon = _make_ngon(4, randf_range(3.0, 6.0))
		frag.color = Color(1.0, randf_range(0.3, 0.6), 0.1, 0.9)
		frag.global_position = pos
		get_tree().current_scene.add_child(frag)
		var angle := float(i) * TAU / 8.0 + randf_range(-0.2, 0.2)
		var dist := randf_range(radius * 0.5, radius * 1.2)
		var target := pos + Vector2(cos(angle), sin(angle)) * dist
		var ftw := frag.create_tween()
		ftw.set_parallel(true)
		ftw.tween_property(frag, "global_position", target, 0.5)
		ftw.tween_property(frag, "color:a", 0.0, 0.5)
		ftw.tween_property(frag, "scale", Vector2(0.2, 0.2), 0.5)
		ftw.chain().tween_callback(frag.queue_free)

	SFX.play_shot()  # 爆発音（将来的にplay_explosion等に差し替え）

func _fire_spread(directions: int) -> void:
	# projectile_bonusを反映（spread/areaパスでも+1 Projectileが効くように）
	var total := directions
	var tower_ref := get_parent()
	if tower_ref and "projectile_bonus" in tower_ref:
		total += tower_ref.projectile_bonus
	for i in range(total):
		var angle := i * TAU / total
		var dir := Vector2(cos(angle), sin(angle))
		_create_projectile(dir)

func _get_aim_direction(enemies: Array) -> Vector2:
	## Attack chipに基づいてターゲット方向を決定
	var attack_chip: Dictionary = build_system.get_equipped_chip("attack")
	var attack_id: String = attack_chip.get("id", "manual_aim")
	var tower_ref := get_parent()

	match attack_id:
		"manual_aim", "":
			# 手動: プレイヤーの向いている方向に発射
			if tower_ref and "facing_dir" in tower_ref:
				return tower_ref.facing_dir
			return Vector2.UP  # デフォルト: 上方向

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
			# フォールバック: 手動照準
			if tower_ref and "facing_dir" in tower_ref:
				return tower_ref.facing_dir
			return Vector2.UP

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

	# スキル別ビジュアル（タグで分岐）
	_build_skill_visual(bullet, direction)

	# 弾スクリプト
	var script := GDScript.new()
	script.source_code = _build_bullet_script()
	script.reload()
	bullet.set_script(script)
	bullet.set("direction", direction)
	bullet.set("speed", 350.0 * stats.get("speed_mult", 1.0))
	var base_damage: float = stats.get("damage", 10)
	var t := get_parent()
	if t and "damage_mult" in t:
		base_damage *= t.damage_mult
	bullet.set("damage", int(base_damage))
	bullet.set("lifetime", 3.0)
	bullet.set("behaviors", stats.get("behaviors", []))
	bullet.set("pierce_remaining", _get_pierce_count())
	bullet.set("chain_remaining", _get_chain_count())
	bullet.set("chain_range", _get_chain_range())
	bullet.set("fork_count", _get_fork_count())
	bullet.set("fork_angle", _get_fork_angle())
	# v0.4 新mod属性を弾に伝播
	bullet.set("homing_strength", stats.get("homing_strength", 0.0))
	bullet.set("gravity_pull", stats.get("gravity_pull", 0.0))
	bullet.set("split_count", stats.get("split_count", 0))
	bullet.set("split_dmg_pct", stats.get("split_dmg_pct", 0.5))
	bullet.set("lightning_chain_chance", stats.get("lightning_chain_chance", 0.0))
	bullet.set("lightning_chain_range", stats.get("lightning_chain_range", 60.0))
	bullet.set("lightning_chain_dmg_pct", stats.get("lightning_chain_dmg_pct", 0.5))
	bullet.set("on_hit_explode_radius", stats.get("on_hit_explode_radius", 0.0))
	bullet.set("on_hit_explode_dmg_pct", stats.get("on_hit_explode_dmg_pct", 0.0))
	bullet.set("on_hit_slow", stats.get("on_hit_slow", 0.0))
	bullet.set("on_hit_slow_duration", stats.get("on_hit_slow_duration", 0.0))
	bullet.set("life_steal_pct", stats.get("life_steal_pct", 0.0))
	bullet.set("ghost_bullet", randf() < stats.get("ghost_chance", 0.0))
	bullet.set("crit_freeze_duration", stats.get("crit_freeze_duration", 0.0))
	bullet.set("crit_chance", stats.get("crit_chance", 0.0))
	bullet.set("crit_mult", stats.get("crit_mult", 1.0))

	bullet.collision_layer = 2
	bullet.collision_mask = 4

	# projectile_size_mult: 弾サイズ拡大
	var size_mult: float = stats.get("projectile_size_mult", 1.0)
	if size_mult != 1.0:
		bullet.scale = Vector2(size_mult, size_mult)

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

func _build_skill_visual(bullet: Area2D, direction: Vector2) -> void:
	## タグに基づいてスキル固有の弾ビジュアルを構築
	var tags: Array = stats.get("tags", [])
	var color := _get_bullet_color()

	if "fire" in tags:
		_visual_fireball(bullet, color, direction)
	elif "cold" in tags:
		_visual_ice_shard(bullet, color, direction)
	elif "lightning" in tags:
		_visual_spark(bullet, color)
	elif "chaos" in tags:
		_visual_poison(bullet, color)
	elif "holy" in tags:
		_visual_holy(bullet, color, direction)
	else:
		_visual_default(bullet, color)

	# トレイル（全スキル共通、色だけ変化）
	var trail := Line2D.new()
	trail.name = "Trail"
	trail.width = 5.0 if "holy" not in tags else 10.0
	trail.default_color = Color(color.r, color.g, color.b, 0.5)
	trail.gradient = Gradient.new()
	trail.gradient.set_color(0, Color(color.r, color.g, color.b, 0.5))
	trail.gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	trail.z_index = -1
	trail.top_level = true
	bullet.add_child(trail)

func _visual_fireball(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 火球: 前方に尖った涙滴形 + 揺らめくグロー
	var rot := direction.angle()

	# 外側グロー（暖色の大きなぼかし）
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(10, 22.0)
	glow.color = Color(1.0, 0.6, 0.1, 0.2)
	glow.rotation = rot
	bullet.add_child(glow)

	# 涙滴（前方に尖った弾頭）
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(14, 0),    # 先端
		Vector2(-4, -8),   # 左後方
		Vector2(-10, 0),   # 後端
		Vector2(-4, 8),    # 右後方
	])
	body.color = color
	body.rotation = rot
	bullet.add_child(body)

	# 内部の明るいコア
	var core := Polygon2D.new()
	core.polygon = _make_ngon(5, 5.0)
	core.color = Color(1.0, 0.9, 0.5, 0.9)
	bullet.add_child(core)

func _visual_ice_shard(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 氷の破片: 鋭角な菱形、結晶感
	var rot := direction.angle()

	# 霜のオーラ
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(6, 20.0)
	glow.color = Color(0.5, 0.8, 1.0, 0.15)
	bullet.add_child(glow)

	# 鋭い菱形（前後に長く、横に薄い）
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(16, 0),    # 前端（鋭い）
		Vector2(0, -5),    # 上辺
		Vector2(-12, 0),   # 後端
		Vector2(0, 5),     # 下辺
	])
	body.color = color
	body.rotation = rot
	bullet.add_child(body)

	# 結晶ハイライト線
	var highlight := Polygon2D.new()
	highlight.polygon = PackedVector2Array([
		Vector2(12, 0),
		Vector2(0, -2),
		Vector2(-8, 0),
		Vector2(0, 2),
	])
	highlight.color = Color(0.7, 0.95, 1.0, 0.7)
	highlight.rotation = rot
	bullet.add_child(highlight)

func _visual_spark(bullet: Area2D, color: Color) -> void:
	## スパーク: 電気球 + 稲妻の腕（視認性強化版）
	# 電気オーラ（大きめ、明るめ）
	var glow := Polygon2D.new()
	var glow_pts: PackedVector2Array = []
	for i in range(8):
		var a := i * TAU / 8
		var r := randf_range(16.0, 26.0)
		glow_pts.append(Vector2(cos(a), sin(a)) * r)
	glow.polygon = glow_pts
	glow.color = Color(1.0, 1.0, 0.4, 0.35)
	bullet.add_child(glow)

	# 電気コア（大きめ）
	var core := Polygon2D.new()
	core.polygon = _make_ngon(5, 10.0)
	core.color = color
	bullet.add_child(core)

	# 中心のホットスポット
	var hot := Polygon2D.new()
	hot.polygon = _make_ngon(4, 4.0)
	hot.color = Color(1.0, 1.0, 0.9, 1.0)
	bullet.add_child(hot)

	# 稲妻の腕（3本のジグザグ線で電気感を強調）
	for j in range(3):
		var bolt := Line2D.new()
		bolt.width = 2.0
		bolt.default_color = Color(1.0, 1.0, 0.5, 0.7)
		var base_angle := float(j) * TAU / 3.0
		var pts: PackedVector2Array = [Vector2.ZERO]
		var pos := Vector2.ZERO
		for k in range(2):
			pos += Vector2(cos(base_angle), sin(base_angle)) * randf_range(6.0, 10.0)
			pos += Vector2(randf_range(-3, 3), randf_range(-3, 3))
			pts.append(pos)
		bolt.points = pts
		bullet.add_child(bolt)

func _visual_poison(bullet: Area2D, color: Color) -> void:
	## 毒弾: 不定形のぶよぶよした球体
	# 毒霧オーラ
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(12, 20.0)
	glow.color = Color(0.3, 0.8, 0.1, 0.15)
	bullet.add_child(glow)

	# ぶよぶよボディ（不規則な多角形）
	var body := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(8):
		var a := i * TAU / 8
		var r := 8.0 + randf_range(-2.0, 2.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	body.polygon = pts
	body.color = color
	bullet.add_child(body)

	# 泡のアクセント
	var bubble := Polygon2D.new()
	bubble.polygon = _make_ngon(6, 3.5)
	bubble.color = Color(0.6, 1.0, 0.4, 0.6)
	bubble.position = Vector2(randf_range(-3, 3), randf_range(-3, 3))
	bullet.add_child(bubble)

func _visual_holy(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 聖光ビーム: 細長い光の帯 + 金色パーティクル
	var rot := direction.angle()

	# 広がるオーラ
	var glow := Polygon2D.new()
	glow.polygon = PackedVector2Array([
		Vector2(20, -8),
		Vector2(24, 0),
		Vector2(20, 8),
		Vector2(-20, 4),
		Vector2(-24, 0),
		Vector2(-20, -4),
	])
	glow.color = Color(1.0, 0.95, 0.7, 0.2)
	glow.rotation = rot
	bullet.add_child(glow)

	# 細長いビーム本体
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(18, -3),
		Vector2(22, 0),
		Vector2(18, 3),
		Vector2(-18, 2),
		Vector2(-20, 0),
		Vector2(-18, -2),
	])
	body.color = color
	body.rotation = rot
	bullet.add_child(body)

	# 中心のクロス（十字架モチーフ）
	var cross_h := Polygon2D.new()
	cross_h.polygon = PackedVector2Array([
		Vector2(-4, -1), Vector2(4, -1), Vector2(4, 1), Vector2(-4, 1),
	])
	cross_h.color = Color(1.0, 1.0, 0.9, 0.8)
	bullet.add_child(cross_h)

	var cross_v := Polygon2D.new()
	cross_v.polygon = PackedVector2Array([
		Vector2(-1, -4), Vector2(1, -4), Vector2(1, 4), Vector2(-1, 4),
	])
	cross_v.color = Color(1.0, 1.0, 0.9, 0.8)
	bullet.add_child(cross_v)

func _visual_default(bullet: Area2D, color: Color) -> void:
	## フォールバック: 基本六角形
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(8, 18.0)
	glow.color = Color(color.r, color.g, color.b, 0.3)
	bullet.add_child(glow)

	var visual := Polygon2D.new()
	visual.polygon = _make_ngon(6, 10.0)
	visual.color = color
	bullet.add_child(visual)

	var hotspot := Polygon2D.new()
	hotspot.polygon = _make_ngon(4, 3.0)
	hotspot.color = Color(minf(color.r + 0.4, 1.0), minf(color.g + 0.4, 1.0), minf(color.b + 0.4, 1.0), 0.9)
	bullet.add_child(hotspot)

func _make_ngon(sides: int, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(maxi(sides, 3)):
		var a := float(i) * TAU / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _get_pierce_count() -> int:
	var count := 0
	if stats.get("pierce", false):
		count = 3  # スキル自体がpierceの場合
	for b in stats.get("behaviors", []):
		if b.get("type", "") == "pierce":
			count = maxi(count, b.get("pierce_count", 3))
	# bonus_pierce from mods
	count += stats.get("bonus_pierce", 0)
	return count

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
	# 弾の挙動を動的に生成（v0.4: ホーミング、重力、分裂、雷チェイン、爆発、スロー、ライフスティール対応）
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
const TRAIL_LENGTH := 8
# v0.4 新mod変数
var homing_strength := 0.0
var gravity_pull := 0.0
var split_count := 0
var split_dmg_pct := 0.5
var lightning_chain_chance := 0.0
var lightning_chain_range := 60.0
var lightning_chain_dmg_pct := 0.5
var on_hit_explode_radius := 0.0
var on_hit_explode_dmg_pct := 0.0
var on_hit_slow := 0.0
var on_hit_slow_duration := 0.0
var life_steal_pct := 0.0
var ghost_bullet := false
var crit_freeze_duration := 0.0
var crit_chance := 0.0
var crit_mult := 1.0

func _ready():
	body_entered.connect(_on_body_entered)
	collision_layer = 2
	collision_mask = 4

func _process(delta):
	# ホーミング: 最寄り敵に向かって方向を微調整
	if homing_strength > 0.0:
		var nearest := _find_nearest_alive()
		if nearest:
			var to_enemy := (nearest.global_position - global_position).normalized()
			direction = direction.lerp(to_enemy, homing_strength * delta).normalized()

	# 重力: 弾の周囲の敵を引き寄せる
	if gravity_pull > 0.0:
		for e in get_tree().get_nodes_in_group(\"enemies\"):
			if is_instance_valid(e) and global_position.distance_to(e.global_position) < 100.0:
				var pull_dir := (global_position - e.global_position).normalized()
				e.position += pull_dir * gravity_pull * delta

	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		set_deferred(\"monitoring\", false)
		call_deferred(\"queue_free\")
		return

	# トレイル更新
	var trail := get_node_or_null(\"Trail\")
	if trail and trail is Line2D:
		trail.add_point(global_position)
		while trail.get_point_count() > TRAIL_LENGTH:
			trail.remove_point(0)

func _find_nearest_alive() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := 300.0
	for e in get_tree().get_nodes_in_group(\"enemies\"):
		if not is_instance_valid(e) or e in hit_enemies:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

func _on_body_entered(body):
	if not body.has_method(\"take_damage\"):
		return
	if body in hit_enemies:
		return

	# crit判定
	var final_damage := damage
	var is_crit := false
	if crit_chance > 0.0 and randf() < crit_chance:
		final_damage = int(float(damage) * crit_mult)
		is_crit = true

	body.take_damage(final_damage)
	hit_enemies.append(body)

	# ライフスティール
	if life_steal_pct > 0.0:
		var tower2 := get_tree().current_scene.get_node_or_null(\"Tower\")
		if tower2 and tower2.has_method(\"heal\"):
			tower2.heal(int(float(final_damage) * life_steal_pct))

	# on_hit爆発
	if on_hit_explode_radius > 0.0:
		_do_aoe(global_position, on_hit_explode_radius, int(float(final_damage) * on_hit_explode_dmg_pct))

	# on_hitスロー
	if on_hit_slow > 0.0 and \"speed\" in body:
		var orig_speed: float = body.speed
		body.speed *= (1.0 - on_hit_slow)
		# タイマーで元に戻す
		get_tree().create_timer(on_hit_slow_duration).timeout.connect(func():
			if is_instance_valid(body):
				body.speed = orig_speed
		)

	# crit時凍結
	if is_crit and crit_freeze_duration > 0.0 and \"speed\" in body:
		var orig_spd: float = body.speed
		body.speed = 0.0
		get_tree().create_timer(crit_freeze_duration).timeout.connect(func():
			if is_instance_valid(body):
				body.speed = orig_spd
		)

	# 雷チェイン（modから。supportのchainとは別系統）
	if lightning_chain_chance > 0.0 and randf() < lightning_chain_chance:
		var lc_target := _find_chain_target(body)
		if lc_target and is_instance_valid(lc_target):
			lc_target.take_damage(int(float(final_damage) * lightning_chain_dmg_pct))

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

	# Split（mod由来、forkとは別）
	if split_count > 0:
		_do_split(body)

	# Pierce: 貫通
	if pierce_remaining > 0:
		pierce_remaining -= 1
		return  # 弾は消えない

	# ゴースト弾は壁を貫通して消えない（敵のみ貫通）
	if ghost_bullet:
		return

	set_deferred(\"monitoring\", false)
	call_deferred(\"queue_free\")

func _do_aoe(center: Vector2, radius: float, aoe_damage: int):
	for e in get_tree().get_nodes_in_group(\"enemies\"):
		if is_instance_valid(e) and e not in hit_enemies:
			if center.distance_to(e.global_position) <= radius:
				e.take_damage(aoe_damage)

func _find_chain_target(exclude_body) -> Node2D:
	var enemies := get_tree().get_nodes_in_group(\"enemies\")
	var nearest: Node2D = null
	var nearest_dist := chain_range
	if lightning_chain_range > 0:
		nearest_dist = maxf(nearest_dist, lightning_chain_range)

	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy == exclude_body or enemy in hit_enemies:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest

func _do_split(_hit_body):
	# split弾を生成（split_countは0にして無限分裂を防止）
	var base_angle := direction.angle()
	for i in range(split_count):
		var offset := deg_to_rad(45.0) * (float(i) - float(split_count - 1) / 2.0)
		var s_dir := Vector2(cos(base_angle + offset), sin(base_angle + offset))
		var s_bullet := Area2D.new()
		s_bullet.name = \"SplitBullet\"
		s_bullet.add_to_group(\"bullets\")
		s_bullet.global_position = global_position
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		s_bullet.add_child(col)
		var visual := Polygon2D.new()
		var points: PackedVector2Array = []
		for j in range(5):
			var angle := j * TAU / 5
			points.append(Vector2(cos(angle), sin(angle)) * 3.0)
		visual.polygon = points
		visual.color = Color(0.8, 0.8, 1.0, 0.7)
		s_bullet.add_child(visual)
		var s := GDScript.new()
		s.source_code = _simple_bullet_script()
		s.reload()
		s_bullet.set_script(s)
		s_bullet.set(\"direction\", s_dir)
		s_bullet.set(\"damage\", int(float(damage) * split_dmg_pct))
		get_tree().current_scene.add_child(s_bullet)

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

		var s := GDScript.new()
		s.source_code = _simple_bullet_script()
		s.reload()
		fork_bullet.set_script(s)
		fork_bullet.set(\"direction\", fork_dir)
		fork_bullet.set(\"damage\", int(damage * 0.6))

		get_tree().current_scene.add_child(fork_bullet)

func _simple_bullet_script() -> String:
	return \"extends Area2D\\nvar direction := Vector2.ZERO\\nvar speed := 350.0\\nvar damage := 5\\nvar lifetime := 1.5\\n\\nfunc _ready():\\n\\tbody_entered.connect(func(body):\\n\\t\\tif body.has_method(\\\\\\\"take_damage\\\\\\\"):\\n\\t\\t\\tbody.take_damage(damage)\\n\\t\\tset_deferred(\\\\\\\"monitoring\\\\\\\", false)\\n\\t\\tcall_deferred(\\\\\\\"queue_free\\\\\\\")\\n\\t)\\n\\tcollision_layer = 2\\n\\tcollision_mask = 4\\n\\nfunc _process(delta):\\n\\tposition += direction * speed * delta\\n\\tlifetime -= delta\\n\\tif lifetime <= 0:\\n\\t\\tset_deferred(\\\\\\\"monitoring\\\\\\\", false)\\n\\t\\tcall_deferred(\\\\\\\"queue_free\\\\\\\")\\n\"
"""
