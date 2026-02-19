extends Node2D

## TowerAttack - タワーの各スロットの攻撃処理。
## BuildSystemから計算されたステータスに基づいて弾を生成。
## Attack ChipとSkill Chipで照準と発動条件を制御。

var slot_index: int = 0
var stats: Dictionary = {}
var timer := 0.0
var is_first_strike := true
var build_system: Node

# v0.7.0: GDScriptキャッシュ — 毎弾コンパイルによる7-8分フリーズを防ぐ
# 動的GDScript生成は高コスト。同じスクリプトを使い回す。
var _bullet_gdscript: GDScript = null
var _wisp_gdscript: GDScript = null

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

## --- GDScriptキャッシュゲッター ---
## GDScript.new() + reload() は高コスト。初回のみコンパイルし以降は再利用。

func _get_bullet_gdscript() -> GDScript:
	if _bullet_gdscript == null:
		_bullet_gdscript = GDScript.new()
		_bullet_gdscript.source_code = _build_bullet_script()
		_bullet_gdscript.reload()
	return _bullet_gdscript

func _get_wisp_gdscript() -> GDScript:
	if _wisp_gdscript == null:
		_wisp_gdscript = GDScript.new()
		_wisp_gdscript.source_code = _build_wisp_script()
		_wisp_gdscript.reload()
	return _wisp_gdscript


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

	# マズルフラッシュ（発射の視覚的確認: H-1原則 Make It Pop）
	var tower_node := get_parent()
	if tower_node and is_instance_valid(tower_node):
		var mf := Polygon2D.new()
		mf.polygon = _make_ngon(6, 8.0)
		# チップのタグに応じて色を変える（J-7: 色による区分）
		var flash_tags: Array = stats.get("tags", [])
		if "fire" in flash_tags:
			mf.color = Color(1.0, 0.6, 0.2, 0.85)
		elif "holy" in flash_tags or "light" in flash_tags:
			mf.color = Color(1.0, 0.95, 0.6, 0.85)
		elif "cold" in flash_tags:
			mf.color = Color(0.4, 0.8, 1.0, 0.85)
		elif "lightning" in flash_tags:
			mf.color = Color(0.9, 0.9, 1.0, 0.9)
		else:
			mf.color = Color(0.5, 0.9, 1.0, 0.8)  # シアン（デフォルト）
		mf.z_index = 200
		tower_node.add_child(mf)
		var mf_tween := mf.create_tween()
		mf_tween.set_parallel(true)
		mf_tween.tween_property(mf, "scale", Vector2(2.5, 2.5), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		mf_tween.tween_property(mf, "modulate:a", 0.0, 0.12)
		mf_tween.chain().tween_callback(mf.queue_free)

		# 改善81: fire/lightningタグは2ndリングで「エネルギー放出」を強調（J-7: タグ別視覚分化）
		if "fire" in flash_tags or "lightning" in flash_tags:
			var ring2 := Polygon2D.new()
			ring2.polygon = _make_ngon(6, 5.0)
			ring2.color = Color(mf.color.r, mf.color.g, mf.color.b, 0.45)
			ring2.z_index = 198
			tower_node.add_child(ring2)
			var r2t := ring2.create_tween()
			r2t.set_parallel(true)
			r2t.tween_property(ring2, "scale", Vector2(4.0, 4.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			r2t.tween_property(ring2, "modulate:a", 0.0, 0.18)
			r2t.chain().tween_callback(ring2.queue_free)

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
		_spawn_nova_ring()  # v0.6.0: 毒の波紋エフェクト（弾が飛ぶ前に波が広がる）
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

	wisp.set_script(_get_wisp_gdscript())  # v0.7.0: キャッシュ利用
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

func _spawn_nova_ring() -> void:
	## v0.6.0: Poison Nova発動時に毒の波紋エフェクトを生成。
	## 弾が飛び出す前に「波が広がる」を視覚化 — 「波が広がるもの」という要求に応える。
	var ring_node := Node2D.new()
	ring_node.global_position = global_position
	get_tree().current_scene.add_child(ring_node)

	# 外周リング（Line2Dで円を描く）
	var ring := Line2D.new()
	ring.width = 8.0
	ring.default_color = Color(0.38, 0.92, 0.08, 0.85)
	var ring_pts: PackedVector2Array = []
	for i in range(25):
		var a := float(i) * TAU / 24.0
		ring_pts.append(Vector2(cos(a), sin(a)) * 10.0)
	ring.points = ring_pts
	ring_node.add_child(ring)

	# 内側グロー（半透明塗りつぶし）
	var fill := Polygon2D.new()
	fill.polygon = _make_ngon(24, 10.0)
	fill.color = Color(0.3, 0.85, 0.05, 0.20)
	ring_node.add_child(fill)

	# Tweenで拡大（半径 10→150px）+ フェードアウト（0.55秒）
	# modulate.aを使えば子ノード全体が一括フェードする
	var tw := ring_node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring_node, "scale", Vector2(15.0, 15.0), 0.55)
	tw.tween_property(ring_node, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(ring_node.queue_free)

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

	bullet.set_script(_get_bullet_gdscript())  # v0.7.0: キャッシュ利用
	bullet.set("direction", direction)
	bullet.set("speed", 350.0 * stats.get("speed_mult", 1.0))
	var base_damage: float = stats.get("damage", 10)
	var t := get_parent()
	if t and "damage_mult" in t:
		base_damage *= t.damage_mult
	# 改善164: berserker mod — HP < threshold 時にダメージ倍率適用
	var bz_threshold: float = stats.get("berserker_threshold", 0.0)
	if bz_threshold > 0.0 and t and "hp" in t and "max_hp" in t and t.max_hp > 0:
		var hp_pct: float = t.hp / t.max_hp
		if hp_pct < bz_threshold:
			base_damage *= stats.get("berserker_dmg_mult", 1.8)
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
	# 改善244: splash/leeching mod を弾に伝播
	bullet.set("splash_radius", stats.get("splash_radius", 0.0))
	bullet.set("splash_damage_pct", stats.get("splash_damage_pct", 0.0))
	bullet.set("life_on_hit", stats.get("life_on_hit", 0.0))
	bullet.set("on_hit_slow", stats.get("on_hit_slow", 0.0))
	bullet.set("on_hit_slow_duration", stats.get("on_hit_slow_duration", 0.0))
	bullet.set("life_steal_pct", stats.get("life_steal_pct", 0.0))
	bullet.set("ghost_bullet", randf() < stats.get("ghost_chance", 0.0))
	bullet.set("crit_freeze_duration", stats.get("crit_freeze_duration", 0.0))
	# 改善243: freeze mod（freezing/frostbound）を弾に伝播。on_hitバグと同様の欠落だった
	bullet.set("freeze_chance", stats.get("freeze_chance", 0.0))
	bullet.set("freeze_duration", stats.get("freeze_duration", 0.0))
	bullet.set("synergy_chain_freeze", stats.get("synergy_chain_freeze", 0.0))
	bullet.set("crit_chance", stats.get("crit_chance", 0.0))
	bullet.set("crit_mult", stats.get("crit_mult", 1.0))
	# 改善169: add_dot を弾に伝播（Burning/Toxic/of_Decay mod）
	bullet.set("add_dot", stats.get("add_dot", {}))
	# トレイル色を弾タイプに合わせる（スキル識別性向上: J-7 色による区分）
	var tc := _get_bullet_color()
	bullet.set("trail_color", Color(tc.r, tc.g, tc.b, 0.55))
	# 改善119/120: タグを弾に伝播（インパクト色のタイプ別差別化に使用）
	bullet.set("tags", stats.get("tags", []))

	bullet.collision_layer = 2
	bullet.collision_mask = 4

	# projectile_size_mult: 弾サイズ拡大
	var size_mult: float = stats.get("projectile_size_mult", 1.0)
	if size_mult != 1.0:
		bullet.scale = Vector2(size_mult, size_mult)

	get_tree().current_scene.add_child(bullet)

	# 改善140: 発射時マズルフラッシュ（弾が出た瞬間の「発射感」を空間で演出）
	var mf_color := _get_bullet_color()
	var mf := Polygon2D.new()
	var mf_pts: PackedVector2Array = []
	for i in range(6):
		var a := float(i) * TAU / 6.0
		mf_pts.append(Vector2(cos(a), sin(a)) * 6.0)
	mf.polygon = mf_pts
	mf.color = Color(mf_color.r, mf_color.g, mf_color.b, 0.7)
	mf.global_position = global_position
	mf.z_index = 52
	get_tree().current_scene.add_child(mf)
	var mft := mf.create_tween()
	mft.set_parallel(true)
	mft.tween_property(mf, "scale", Vector2(2.5, 2.5), 0.12).set_trans(Tween.TRANS_QUAD)
	mft.tween_property(mf, "modulate:a", 0.0, 0.12)
	mft.chain().tween_callback(mf.queue_free)

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
		_visual_spark(bullet, color, direction)  # v0.6.0: direction追加
	elif "chaos" in tags:
		_visual_poison(bullet, color)
	elif "holy" in tags:
		_visual_holy(bullet, color, direction)
	else:
		_visual_default(bullet, color)

	# トレイル（スキル別に幅を変える — 稲妻は細く鋭く、聖光は太く）
	var trail := Line2D.new()
	trail.name = "Trail"
	var trail_w := 5.0
	if "holy" in tags:
		trail_w = 14.0
	elif "lightning" in tags:
		trail_w = 2.5
	elif "fire" in tags:
		trail_w = 8.0
	elif "cold" in tags:
		trail_w = 4.0
	trail.width = trail_w
	trail.default_color = Color(color.r, color.g, color.b, 0.5)
	trail.gradient = Gradient.new()
	trail.gradient.set_color(0, Color(color.r, color.g, color.b, 0.5))
	trail.gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	trail.z_index = -1
	trail.top_level = true
	bullet.add_child(trail)

func _visual_fireball(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 火球: 前方に尖った涙滴形 + 揺らめくグロー
	## v0.5.2: projectile_bonusに応じてサイズ拡大（+1弾ごとに+20%、最大2倍）
	var rot := direction.angle()

	# projectile_bonusを取得してスケール倍率を決定
	var bonus := 0
	var tower_ref := get_parent()
	if tower_ref and "projectile_bonus" in tower_ref:
		bonus = tower_ref.projectile_bonus
	var s := 1.0 + minf(float(bonus) * 0.20, 1.0)  # +1→1.2x, +2→1.4x, +5→2.0x上限

	# 外側グロー（bonusで大きく輝く）
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(10, 22.0 * s)
	glow.color = Color(1.0, 0.6, 0.1, 0.15 + minf(float(bonus) * 0.05, 0.25))
	glow.rotation = rot
	bullet.add_child(glow)

	# bonusがあれば外側に追加リング（弾数が増えた視覚的サイン）
	if bonus >= 1:
		var ring := Polygon2D.new()
		ring.polygon = _make_ngon(8, 30.0 * s)
		ring.color = Color(1.0, 0.4, 0.05, 0.12)
		ring.rotation = rot
		bullet.add_child(ring)

	# 涙滴（前方に尖った弾頭）サイズ連動
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(14.0 * s, 0),
		Vector2(-4.0 * s, -8.0 * s),
		Vector2(-10.0 * s, 0),
		Vector2(-4.0 * s, 8.0 * s),
	])
	body.color = color
	body.rotation = rot
	bullet.add_child(body)

	# 内部の明るいコア（bonusで輝度アップ）
	var core := Polygon2D.new()
	core.polygon = _make_ngon(5, (5.0 + float(bonus) * 2.0) * minf(s, 1.5))
	core.color = Color(1.0, 0.9, 0.5, 0.9)
	bullet.add_child(core)

func _visual_ice_shard(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 氷晶爆発: v0.6.0 — 菱形廃止。スノウフレーク型クリスタル。
	## 「飛ぶ氷の塊」ではなく「回転する六角結晶体」として表現。

	# 霜のオーラ（外縁の淡い青）
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(12, 20.0)
	glow.color = Color(0.4, 0.7, 1.0, 0.18)
	bullet.add_child(glow)

	# 主スパイク6本（60度おき）— 氷の尖った結晶腕
	for i in range(6):
		var a := float(i) * TAU / 6.0
		var spike := Polygon2D.new()
		spike.polygon = PackedVector2Array([
			Vector2(0, -2.5),
			Vector2(16, 0),
			Vector2(0, 2.5),
			Vector2(3, 0),
		])
		spike.color = color
		spike.rotation = a
		bullet.add_child(spike)

	# 副スパイク6本（30度オフセット、短め）— 細かい結晶面
	for i in range(6):
		var a := float(i) * TAU / 6.0 + PI / 6.0
		var spike2 := Polygon2D.new()
		spike2.polygon = PackedVector2Array([
			Vector2(0, -1.5),
			Vector2(9, 0),
			Vector2(0, 1.5),
			Vector2(2, 0),
		])
		spike2.color = Color(0.75, 0.92, 1.0, 0.85)
		spike2.rotation = a
		bullet.add_child(spike2)

	# 中心コア（六角形の輝く核）
	var core := Polygon2D.new()
	core.polygon = _make_ngon(6, 4.5)
	core.color = Color(0.88, 0.96, 1.0, 0.95)
	bullet.add_child(core)

func _visual_spark(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 稲妻ボルト: v0.6.0 — 球体廃止。ジグザグ電光が空気を引き裂きながら飛ぶ。
	## 「電流が流れる」ビジュアル体験。前後方向にだけ伸びる稲妻形状。
	var rot := direction.angle()

	# 外縁の電気オーラ（横長の楕円）
	var aura := Polygon2D.new()
	aura.polygon = PackedVector2Array([
		Vector2(24, -11), Vector2(28, 0), Vector2(24, 11),
		Vector2(-24, 8), Vector2(-28, 0), Vector2(-24, -8),
	])
	aura.color = Color(0.65, 0.82, 1.0, 0.20)
	aura.rotation = rot
	bullet.add_child(aura)

	# メイン稲妻ボルト（Line2D ジグザグ — 前方に向かって飛ぶ）
	var bolt := Line2D.new()
	bolt.width = 3.5
	bolt.default_color = Color(0.95, 0.98, 1.0, 1.0)
	bolt.points = PackedVector2Array([
		Vector2(-22, 0),
		Vector2(-12, -9),
		Vector2(-3, 3),
		Vector2(5, -8),
		Vector2(13, 4),
		Vector2(22, 0),
	])
	bolt.rotation = rot
	bullet.add_child(bolt)

	# サブボルト（少しオフセット、青みがかった副放電）
	var bolt2 := Line2D.new()
	bolt2.width = 2.0
	bolt2.default_color = Color(0.5, 0.78, 1.0, 0.75)
	bolt2.points = PackedVector2Array([
		Vector2(-20, 3),
		Vector2(-9, -5),
		Vector2(0, 7),
		Vector2(9, -3),
		Vector2(18, 5),
		Vector2(22, 2),
	])
	bolt2.rotation = rot
	bullet.add_child(bolt2)

	# 先端輝点（稲妻の先端が最も明るい）
	var tip := Polygon2D.new()
	tip.polygon = _make_ngon(4, 4.5)
	tip.color = Color(1.0, 1.0, 1.0, 1.0)
	tip.position = Vector2(cos(rot), sin(rot)) * 22.0
	bullet.add_child(tip)

func _visual_poison(bullet: Area2D, color: Color) -> void:
	## 毒球: v0.6.0 — ノヴァリングが発動の「波」を担うため、弾自体はドクドクした液体感で。
	## 泡立つ毒液として8方向を飛び回る。

	# 毒霧の広がりオーラ（より大きく、濃く）
	var glow := Polygon2D.new()
	glow.polygon = _make_ngon(16, 22.0)
	glow.color = Color(0.25, 0.80, 0.05, 0.18)
	bullet.add_child(glow)

	# ぶよぶよした毒液ボディ（10頂点で有機的な形状）
	var body := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(10):
		var a := float(i) * TAU / 10.0
		var r := 9.5 + randf_range(-2.5, 2.5)
		pts.append(Vector2(cos(a), sin(a)) * r)
	body.polygon = pts
	body.color = color
	bullet.add_child(body)

	# 毒の光沢ハイライト（内部に明るい核）
	var core := Polygon2D.new()
	core.polygon = _make_ngon(8, 5.0)
	core.color = Color(0.55, 1.0, 0.25, 0.75)
	core.position = Vector2(-1.5, -2.0)
	bullet.add_child(core)

	# 泡粒（3つ散りばめる）
	for _i in range(3):
		var dot := Polygon2D.new()
		dot.polygon = _make_ngon(5, randf_range(1.5, 3.0))
		dot.color = Color(0.5, 1.0, 0.2, randf_range(0.5, 0.85))
		dot.position = Vector2(randf_range(-6, 6), randf_range(-6, 6))
		bullet.add_child(dot)

func _visual_holy(bullet: Area2D, color: Color, direction: Vector2) -> void:
	## 聖光レーザー: v0.6.0 — 光の帯廃止。高密度な鋭いレーザービームに変更。
	## 細く長く、中心が白く輝く「神の一矢」的表現。
	var rot := direction.angle()

	# 最外部の光芒（細長い楕円状グロー）
	var outer := Polygon2D.new()
	outer.polygon = PackedVector2Array([
		Vector2(36, -13), Vector2(42, 0), Vector2(36, 13),
		Vector2(-36, 9),  Vector2(-42, 0), Vector2(-36, -9),
	])
	outer.color = Color(1.0, 0.90, 0.45, 0.12)
	outer.rotation = rot
	bullet.add_child(outer)

	# 中間グロー（やや細く、明るく）
	var mid := Polygon2D.new()
	mid.polygon = PackedVector2Array([
		Vector2(32, -7), Vector2(36, 0), Vector2(32, 7),
		Vector2(-32, 5), Vector2(-35, 0), Vector2(-32, -5),
	])
	mid.color = Color(1.0, 0.95, 0.65, 0.28)
	mid.rotation = rot
	bullet.add_child(mid)

	# ビーム本体（細く鋭い金色）
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		Vector2(29, -3), Vector2(33, 0), Vector2(29, 3),
		Vector2(-29, 2.5), Vector2(-31, 0), Vector2(-29, -2.5),
	])
	beam.color = color
	beam.rotation = rot
	bullet.add_child(beam)

	# ビーム中心白線（最輝部）
	var core_beam := Polygon2D.new()
	core_beam.polygon = PackedVector2Array([
		Vector2(27, -1.2), Vector2(29, 0), Vector2(27, 1.2),
		Vector2(-27, 1.2), Vector2(-28, 0), Vector2(-27, -1.2),
	])
	core_beam.color = Color(1.0, 1.0, 0.98, 1.0)
	core_beam.rotation = rot
	bullet.add_child(core_beam)

	# 中心の十字紋章（神聖さの象徴）
	var cross_h := Polygon2D.new()
	cross_h.polygon = PackedVector2Array([
		Vector2(-5, -1.5), Vector2(5, -1.5), Vector2(5, 1.5), Vector2(-5, 1.5),
	])
	cross_h.color = Color(1.0, 1.0, 0.92, 0.95)
	bullet.add_child(cross_h)

	var cross_v := Polygon2D.new()
	cross_v.polygon = PackedVector2Array([
		Vector2(-1.5, -5), Vector2(1.5, -5), Vector2(1.5, 5), Vector2(-1.5, 5),
	])
	cross_v.color = Color(1.0, 1.0, 0.92, 0.95)
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
var splash_radius := 0.0  # 改善244: of_splashing mod — hit時の周囲AoE
var splash_damage_pct := 0.0
var life_on_hit := 0.0  # 改善244: of_leeching mod — hit時のHP回復
var on_hit_slow := 0.0
var on_hit_slow_duration := 0.0
var life_steal_pct := 0.0
var ghost_bullet := false
var crit_freeze_duration := 0.0
var freeze_chance := 0.0  # 改善243: modからの確率凍結（freezing/frostbound）
var synergy_chain_freeze := 0.0  # 改善251: frozen_stormシナジー — 全ヒットで凍結
var freeze_duration := 0.0
var crit_chance := 0.0
var crit_mult := 1.0
var add_dot := {}  # 改善169: DoT設定 {damage, duration, element}
var trail_color := Color(0.9, 0.9, 1.0, 0.65)  # 弾のトレイル色（外部からset可）
var tags := []  # 改善119: タイプタグ（fire/lightning/cold等。インパクト色分けに使用）
var _trail_timer := 0.0  # トレイル間隔タイマー

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
				var pull_dir: Vector2 = (global_position - e.global_position).normalized()
				e.position += pull_dir * gravity_pull * delta

	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		set_deferred(\"monitoring\", false)
		call_deferred(\"queue_free\")
		return

	# スパークトレイル（飛行中のジュース感: H-1 Make it Pop）
	_trail_timer -= delta
	if _trail_timer <= 0:
		_trail_timer = 0.038  # ~26個/秒（改善60: より密なトレイルで弾の軌跡を強調）
		_emit_spark_trail()
		# 改善127: 火属性の余燼エフェクト（火の弾に熱感を付加）
		if \"fire\" in tags and randf() < 0.4:
			_emit_ember_pop()
		# 改善127b: 冷属性の氷結マーク（冷気の漂いを後ろに残す）
		elif \"cold\" in tags and randf() < 0.3:
			_emit_ice_drift()

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
		var d: float = global_position.distance_to(e.global_position)
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

	body.take_damage(final_damage, is_crit)
	hit_enemies.append(body)

	# 改善169: DoT適用（Burning/Toxic/of_Decay mod）
	if not add_dot.is_empty() and body.has_method("apply_dot"):
		body.apply_dot(
			add_dot.get("damage", 0.0),
			add_dot.get("duration", 1.0),
			add_dot.get("element", "fire")
		)

	# インパクトエフェクト（H-6: Hit Marks — ヒット確認の視覚記号）
	# 弾着点に小さなリングを展開して「当たった」感を強化
	var scene_root := get_tree().current_scene
	if scene_root:
		var ring := Polygon2D.new()
		var ring_pts := PackedVector2Array()
		var ring_r := 10.0 if is_crit else 7.0
		var sides := 6
		for _i in range(sides):
			ring_pts.append(Vector2(cos(_i * TAU / sides), sin(_i * TAU / sides)) * ring_r)
		ring.polygon = ring_pts
		# 改善119: 攻撃タイプ別インパクトリング色（タイプの違いを直感で伝える）
		var ring_base: Color
		if is_crit:
			ring_base = Color(1.0, 0.9, 0.2, 0.95)  # クリット: 金
		elif \"fire\" in tags:
			ring_base = Color(1.0, 0.45, 0.1, 0.9)   # 火: 橙
		elif \"lightning\" in tags:
			ring_base = Color(0.3, 0.9, 1.0, 0.9)    # 雷: シアン
		elif \"cold\" in tags:
			ring_base = Color(0.5, 0.75, 1.0, 0.9)   # 冷: 氷青
		else:
			ring_base = Color(1.0, 1.0, 1.0, 0.75)   # デフォルト: 白
		ring.color = ring_base
		ring.global_position = global_position
		ring.z_index = 90
		scene_root.add_child(ring)
		var rt := ring.create_tween()
		rt.set_parallel(true)
		var r_scale := Vector2(3.5, 3.5) if is_crit else Vector2(2.5, 2.5)
		rt.tween_property(ring, \"scale\", r_scale, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.tween_property(ring, \"modulate:a\", 0.0, 0.18)
		rt.chain().tween_callback(ring.queue_free)

	# インパクトバースト: 3つの小粒子が飛散（改善57: 弾着点の「重さ」を強化）
	if scene_root:
		# 改善120: バーストパーティクルもタイプ別色（インパクト全体の一貫性）
		var burst_color: Color
		if is_crit:
			burst_color = Color(1.0, 0.9, 0.4, 0.9)
		elif \"fire\" in tags:
			burst_color = Color(1.0, 0.5, 0.15, 0.85)
		elif \"lightning\" in tags:
			burst_color = Color(0.4, 0.95, 1.0, 0.85)
		elif \"cold\" in tags:
			burst_color = Color(0.55, 0.8, 1.0, 0.85)
		else:
			burst_color = Color(1.0, 1.0, 0.8, 0.7)
		for _bi in range(3):
			var frag := Polygon2D.new()
			frag.polygon = PackedVector2Array([
				Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -3),
			])
			frag.color = burst_color
			frag.global_position = global_position
			frag.z_index = 88
			scene_root.add_child(frag)
			var fang := randf() * TAU
			var fdist := randf_range(12.0, 28.0)
			var ft := frag.create_tween()
			ft.set_parallel(true)
			ft.tween_property(frag, \"global_position\",
				global_position + Vector2(cos(fang), sin(fang)) * fdist, 0.22
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			ft.tween_property(frag, \"modulate:a\", 0.0, 0.22)
			ft.chain().tween_callback(frag.queue_free)

	# 改善141: holyタグの十字スパーク（聖なる弾の「神聖な一撃」を視覚的に強調）
	if \"holy\" in tags and scene_root:
		for _hci in range(4):
			var hc := Polygon2D.new()
			var hc_ang := float(_hci) * PI * 0.5
			hc.polygon = PackedVector2Array([Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -4.0)])
			hc.color = Color(1.0, 0.95, 0.8, 0.9)
			hc.global_position = global_position
			hc.rotation = hc_ang
			hc.z_index = 91
			scene_root.add_child(hc)
			var hct := hc.create_tween()
			hct.set_parallel(true)
			hct.tween_property(hc, \"global_position\", global_position + Vector2(cos(hc_ang), sin(hc_ang)) * 18.0, 0.25)
			hct.tween_property(hc, \"modulate:a\", 0.0, 0.25)
			hct.chain().tween_callback(hc.queue_free)

	# クリット時: タワーにシェイクフィードバック（改善59: クリの「重み」を体全体で感じる）
	if is_crit:
		var tower_node := get_tree().current_scene.get_node_or_null(\"Tower\")
		if tower_node and tower_node.has_method(\"shake\"):
			tower_node.shake(1.5)
		# 改善246: クリット時スローモーション（「特別な一撃」を時間軸で演出）
		# Why: 白フラッシュ+シェイクだけでは高速戦闘でクリが視覚的に埋もれる。
		# 0.06s間だけtime_scale=0.2。長すぎるとテンポが壊れるので60ms上限。
		Engine.time_scale = 0.2
		get_tree().create_timer(0.06, true, false, true).timeout.connect(func():
			Engine.time_scale = 1.0
		)
		# 改善110: クリット時の極薄白フラッシュ（「特別な一撃」を体感させる、Control層に追加）
		var ui_layer2 := get_tree().current_scene.get_node_or_null(\"UI\")
		if ui_layer2:
			var cf := ColorRect.new()
			cf.color = Color(1.0, 1.0, 1.0, 0.07)
			cf.set_anchors_preset(Control.PRESET_FULL_RECT)
			cf.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cf.z_index = 145
			ui_layer2.add_child(cf)
			var cft := cf.create_tween()
			cft.tween_property(cf, \"color:a\", 0.0, 0.18).set_trans(Tween.TRANS_QUAD)
			cft.tween_callback(cf.queue_free)

	# ライフスティール
	if life_steal_pct > 0.0:
		var tower2 := get_tree().current_scene.get_node_or_null(\"Tower\")
		if tower2 and tower2.has_method(\"heal\"):
			tower2.heal(int(float(final_damage) * life_steal_pct))

	# on_hit爆発 + 改善111: 爆発リング（AoE範囲を一瞬可視化してゲームプレイを読みやすく）
	if on_hit_explode_radius > 0.0:
		_do_aoe(global_position, on_hit_explode_radius, int(float(final_damage) * on_hit_explode_dmg_pct))
		var exp_root := get_tree().current_scene
		if exp_root:
			var exp_ring := Polygon2D.new()
			var exp_pts := PackedVector2Array()
			for _ei in range(20):
				exp_pts.append(Vector2(cos(_ei * TAU / 20.0), sin(_ei * TAU / 20.0)) * on_hit_explode_radius * 0.4)
			exp_ring.polygon = exp_pts
			exp_ring.color = Color(1.0, 0.55, 0.1, 0.55)
			exp_ring.global_position = global_position
			exp_ring.z_index = 88
			exp_root.add_child(exp_ring)
			var ert := exp_ring.create_tween()
			ert.set_parallel(true)
			ert.tween_property(exp_ring, \"scale\", Vector2(2.5, 2.5), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			ert.tween_property(exp_ring, \"modulate:a\", 0.0, 0.3)
			ert.chain().tween_callback(exp_ring.queue_free)

	# 改善244: of_splashing — hit時の周囲スプラッシュダメージ（on_hit_explodeの冷静版）
	# Why: on_hit_explodeはオレンジ爆発。splashは水色でより静かなAoE。別ビジュアルで区別。
	if splash_radius > 0.0:
		_do_aoe(global_position, splash_radius, int(float(final_damage) * splash_damage_pct))
		var sp_root := get_tree().current_scene
		if sp_root:
			var sp_ring := Polygon2D.new()
			var sp_pts := PackedVector2Array()
			for _si in range(16):
				sp_pts.append(Vector2(cos(_si * TAU / 16.0), sin(_si * TAU / 16.0)) * splash_radius * 0.35)
			sp_ring.polygon = sp_pts
			sp_ring.color = Color(0.2, 0.7, 1.0, 0.45)
			sp_ring.global_position = global_position
			sp_ring.z_index = 88
			sp_root.add_child(sp_ring)
			var srt := sp_ring.create_tween()
			srt.set_parallel(true)
			srt.tween_property(sp_ring, \"scale\", Vector2(2.2, 2.2), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			srt.tween_property(sp_ring, \"modulate:a\", 0.0, 0.25)
			srt.chain().tween_callback(sp_ring.queue_free)

	# 改善244: of_leeching — hit時のHP回復（2HP/hit）
	# Why: life_steal_pct は最終ダメージ比例。life_on_hit は固定量。性質が異なる別効果。
	if life_on_hit > 0.0 and tower != null and is_instance_valid(tower):
		tower.heal(life_on_hit)

	# on_hitスロー + 氷ブルーティント（スロー中であることを視覚的に示す）
	if on_hit_slow > 0.0 and \"speed\" in body:
		var orig_speed: float = body.speed
		body.speed *= (1.0 - on_hit_slow)
		# 氷ブルーティント（スロー中）
		if body.has_method(\"modulate\") or \"modulate\" in body:
			body.modulate = Color(0.5, 0.8, 1.2, 1.0)  # 氷ブルー
		# 改善147: スロー時の霜パーティクル（「凍った！」を一瞬で伝える）
		if scene_root:
			for _fi in range(5):
				var frost := Polygon2D.new()
				var frost_pts := PackedVector2Array()
				for _fpi in range(6):
					frost_pts.append(Vector2(cos(_fpi * TAU / 6.0), sin(_fpi * TAU / 6.0)) * 3.5)
				frost.polygon = frost_pts
				frost.color = Color(0.6, 0.85, 1.0, 0.85)
				var fa := randf() * TAU
				var fr := randf_range(8.0, 18.0)
				frost.global_position = body.global_position + Vector2(cos(fa), sin(fa)) * fr
				frost.z_index = 94
				scene_root.add_child(frost)
				var ft := frost.create_tween()
				ft.set_parallel(true)
				ft.tween_property(frost, \"scale\", Vector2(2.0, 2.0), 0.4).set_trans(Tween.TRANS_QUAD)
				ft.tween_property(frost, \"modulate:a\", 0.0, 0.4).set_delay(0.1)
				ft.chain().tween_callback(frost.queue_free)
		# タイマーで元に戻す
		get_tree().create_timer(on_hit_slow_duration).timeout.connect(func():
			if is_instance_valid(body):
				body.speed = orig_speed
				body.modulate = Color.WHITE
		)

	# crit時凍結
	if is_crit and crit_freeze_duration > 0.0 and \"speed\" in body:
		var orig_spd: float = body.speed
		body.speed = 0.0
		# 改善168: 凍結ティント＋氷晶パーティクル（スロー同様の視覚フィードバック）
		if \"modulate\" in body:
			body.modulate = Color(0.4, 0.75, 1.3, 1.0)  # 深い氷ブルー（スローより濃い）
		if scene_root:
			for _ci in range(8):
				var crystal := Polygon2D.new()
				var crystal_pts := PackedVector2Array()
				for _cpi in range(6):
					crystal_pts.append(Vector2(cos(_cpi * TAU / 6.0), sin(_cpi * TAU / 6.0)) * 4.5)
				crystal.polygon = crystal_pts
				crystal.color = Color(0.7, 0.9, 1.0, 0.9)
				var ca := randf() * TAU
				var cr := randf_range(10.0, 22.0)
				crystal.global_position = body.global_position + Vector2(cos(ca), sin(ca)) * cr
				crystal.z_index = 95
				scene_root.add_child(crystal)
				var crt := crystal.create_tween()
				crt.set_parallel(true)
				crt.tween_property(crystal, \"scale\", Vector2(2.5, 2.5), 0.5).set_trans(Tween.TRANS_QUAD)
				crt.tween_property(crystal, \"modulate:a\", 0.0, 0.5).set_delay(0.15)
				crt.chain().tween_callback(crystal.queue_free)
		get_tree().create_timer(crit_freeze_duration).timeout.connect(func():
			if is_instance_valid(body):
				body.speed = orig_spd
				if \"modulate\" in body:
					body.modulate = Color.WHITE
		)

	# 改善243: modからの確率凍結（freezing/frostbound）。crit条件なしで発動する確率的凍結。
	# Why: crit_freeze_duration はcrit時のみ発動。freeze_chance は通常hitでも確率凍結できる別枠。
	if freeze_chance > 0.0 and randf() < freeze_chance and "speed" in body:
		var orig_fspd: float = body.speed
		body.speed = 0.0
		if "modulate" in body:
			body.modulate = Color(0.4, 0.75, 1.3, 1.0)  # 深い氷ブルー
		if scene_root:
			for _fzi in range(8):
				var fz_crystal := Polygon2D.new()
				var fz_pts := PackedVector2Array()
				for _fzp in range(6):
					fz_pts.append(Vector2(cos(_fzp * TAU / 6.0), sin(_fzp * TAU / 6.0)) * 4.5)
				fz_crystal.polygon = fz_pts
				fz_crystal.color = Color(0.7, 0.9, 1.0, 0.9)
				var fza := randf() * TAU
				var fzr := randf_range(10.0, 22.0)
				fz_crystal.global_position = body.global_position + Vector2(cos(fza), sin(fza)) * fzr
				fz_crystal.z_index = 95
				scene_root.add_child(fz_crystal)
				var fzt := fz_crystal.create_tween()
				fzt.set_parallel(true)
				fzt.tween_property(fz_crystal, "scale", Vector2(2.5, 2.5), 0.5).set_trans(Tween.TRANS_QUAD)
				fzt.tween_property(fz_crystal, "modulate:a", 0.0, 0.5).set_delay(0.15)
				fzt.chain().tween_callback(fz_crystal.queue_free)
		get_tree().create_timer(freeze_duration).timeout.connect(func():
			if is_instance_valid(body):
				body.speed = orig_fspd
				if "modulate" in body:
					body.modulate = Color.WHITE
		)

	# 改善251: frozen_storm シナジー — chain_remaining > 0 のヒット（チェイン中）で凍結
	# Why: chain中の全ヒットがice_shardのslowではなく完全凍結(speed=0)になる。
	if synergy_chain_freeze > 0.0 and chain_remaining > 0 and "speed" in body:
		var orig_sfspd: float = body.speed
		body.speed = 0.0
		if "modulate" in body:
			body.modulate = Color(0.4, 0.75, 1.3, 1.0)
		get_tree().create_timer(synergy_chain_freeze, true, false, true).timeout.connect(func():
			if is_instance_valid(body):
				body.speed = orig_sfspd
				if "modulate" in body:
					body.modulate = Color.WHITE
		)

	# 雷チェイン（modから。supportのchainとは別系統）
	if lightning_chain_chance > 0.0 and randf() < lightning_chain_chance:
		var lc_target := _find_chain_target(body)
		if lc_target and is_instance_valid(lc_target):
			lc_target.take_damage(int(float(final_damage) * lightning_chain_dmg_pct))
			# 改善176: mod雷チェインの視覚弧（chain supportと同じジグザグ電弧）
			# Why: mod経由の雷チェインは発動が視認できず「chainが機能してるか？」が不明だった
			var lc_root := get_tree().current_scene
			if lc_root:
				var lc_start := global_position
				var lc_end := lc_target.global_position
				var lc_seg := lc_end - lc_start
				var lc_perp := Vector2(-lc_seg.y, lc_seg.x).normalized()
				var lc_pts := PackedVector2Array()
				lc_pts.append(lc_start)
				for _lzi in range(3):
					var lc_t := float(_lzi + 1) / 4.0
					lc_pts.append(lc_start + lc_seg * lc_t + lc_perp * randf_range(-7.0, 7.0))
				lc_pts.append(lc_end)
				# グロー下層
				var lc_glow := Line2D.new()
				lc_glow.default_color = Color(0.6, 0.9, 0.3, 0.45)  # 黄緑（mod由来は色を変えてchainと区別）
				lc_glow.width = 5.0
				lc_glow.points = lc_pts
				lc_glow.z_index = 91
				lc_root.add_child(lc_glow)
				var lgt := lc_glow.create_tween()
				lgt.tween_property(lc_glow, \"modulate:a\", 0.0, 0.20)
				lgt.chain().tween_callback(lc_glow.queue_free)
				# コアライン上層
				var lc_arc := Line2D.new()
				lc_arc.default_color = Color(0.9, 1.0, 0.6, 0.9)  # 黄白コア
				lc_arc.width = 1.5
				lc_arc.points = lc_pts
				lc_arc.z_index = 93
				lc_root.add_child(lc_arc)
				var lat := lc_arc.create_tween()
				lat.tween_property(lc_arc, \"modulate:a\", 0.0, 0.20)
				lat.chain().tween_callback(lc_arc.queue_free)

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
			# 改善109: 強化チェインVFX — ジグザグ雷弧+グロー（雷の「飛んだ！」感を強調）
			var arc_root := get_tree().current_scene
			if arc_root:
				# 下層: 太いグロー
				var arc_glow := Line2D.new()
				arc_glow.default_color = Color(0.3, 0.7, 1.0, 0.4)
				arc_glow.width = 7.0
				# ジグザグ点を生成（5分割で中間点をランダムに±8pxオフセット）
				var start := global_position
				var end := next.global_position
				var seg := end - start
				var perp := Vector2(-seg.y, seg.x).normalized()
				var zz_pts := PackedVector2Array()
				zz_pts.append(start)
				for _zi in range(4):
					var t_val := float(_zi + 1) / 5.0
					var mid := start + seg * t_val + perp * randf_range(-8.0, 8.0)
					zz_pts.append(mid)
				zz_pts.append(end)
				arc_glow.points = zz_pts
				arc_glow.z_index = 93
				arc_root.add_child(arc_glow)
				var glow_tw := arc_glow.create_tween()
				glow_tw.tween_property(arc_glow, \"modulate:a\", 0.0, 0.22)
				glow_tw.chain().tween_callback(arc_glow.queue_free)
				# 上層: 細い白いコアライン
				var arc := Line2D.new()
				arc.default_color = Color(0.75, 0.95, 1.0, 0.95)
				arc.width = 1.8
				arc.points = zz_pts
				arc.z_index = 95
				arc_root.add_child(arc)
				var arc_tw := arc.create_tween()
				arc_tw.tween_property(arc, \"modulate:a\", 0.0, 0.22)
				arc_tw.chain().tween_callback(arc.queue_free)
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
		# 改善150: ピアス貫通時の青い貫通エフェクト（「貫いた！」視覚フィードバック）
		var pierce_root := get_tree().current_scene
		if pierce_root:
			var pr := Polygon2D.new()
			var pr_pts: PackedVector2Array = []
			for _pri in range(6):
				pr_pts.append(Vector2(cos(_pri * TAU / 6.0), sin(_pri * TAU / 6.0)) * 8.0)
			pr.polygon = pr_pts
			pr.color = Color(0.3, 0.7, 1.0, 0.75)
			pr.global_position = global_position
			pr.z_index = 93
			pierce_root.add_child(pr)
			var prt := pr.create_tween()
			prt.set_parallel(true)
			prt.tween_property(pr, \"scale\", Vector2(2.5, 2.5), 0.2).set_trans(Tween.TRANS_QUAD)
			prt.tween_property(pr, \"modulate:a\", 0.0, 0.2)
			prt.chain().tween_callback(pr.queue_free)
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
		var dist: float = global_position.distance_to(enemy.global_position)
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
		get_tree().current_scene.call_deferred(\"add_child\", s_bullet)

func _do_fork(_hit_body):
	# Fork弾を生成（fork_countは0にして無限分裂を防止）
	# 改善149: フォーク分裂時のVフラッシュ（「弾が割れた！」を一瞬で伝える）
	var fork_scene_root := get_tree().current_scene
	if fork_scene_root:
		var fvf := Polygon2D.new()
		var fvf_pts: PackedVector2Array = []
		for _fvi in range(8):
			fvf_pts.append(Vector2(cos(_fvi * TAU / 8.0), sin(_fvi * TAU / 8.0)) * 7.0)
		fvf.polygon = fvf_pts
		fvf.color = Color(0.9, 0.9, 1.0, 0.8)
		fvf.global_position = global_position
		fvf.z_index = 95
		fork_scene_root.add_child(fvf)
		var fvt := fvf.create_tween()
		fvt.set_parallel(true)
		fvt.tween_property(fvf, "scale", Vector2(3.0, 3.0), 0.15).set_trans(Tween.TRANS_QUAD)
		fvt.tween_property(fvf, "modulate:a", 0.0, 0.15)
		fvt.chain().tween_callback(fvf.queue_free)

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

		get_tree().current_scene.call_deferred(\"add_child\", fork_bullet)

func _emit_spark_trail() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var dot := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(4):
		var a := float(i) * TAU / 4.0
		pts.append(Vector2(cos(a), sin(a)) * 2.2)
	dot.polygon = pts
	dot.global_position = global_position + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	dot.color = trail_color
	dot.z_index = 1
	scene_root.add_child(dot)
	var t := dot.create_tween()
	t.set_parallel(true)
	t.tween_property(dot, \"scale\", Vector2(0.1, 0.1), 0.14).set_trans(Tween.TRANS_QUAD)
	t.tween_property(dot, \"modulate:a\", 0.0, 0.14)
	t.chain().tween_callback(dot.queue_free)

func _emit_ember_pop() -> void:
	## 改善127: 火の余燼（大き目のオレンジ丸が上方向にふわりと漂う）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ember := Polygon2D.new()
	ember.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)
	])
	ember.color = Color(1.0, randf_range(0.35, 0.7), 0.1, 0.85)
	ember.global_position = global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
	ember.z_index = 2
	scene_root.add_child(ember)
	var t := ember.create_tween()
	t.set_parallel(true)
	t.tween_property(ember, \"global_position:y\", ember.global_position.y - randf_range(10, 20), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ember, \"modulate:a\", 0.0, 0.45).set_delay(0.1)
	t.chain().tween_callback(ember.queue_free)

func _emit_ice_drift() -> void:
	## 改善127b: 冷気の漂い（水色の小ひし形がゆっくり拡散）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var crystal := Polygon2D.new()
	crystal.polygon = PackedVector2Array([
		Vector2(0, -3), Vector2(2, 0), Vector2(0, 3), Vector2(-2, 0)
	])
	crystal.color = Color(0.5, 0.85, 1.0, 0.7)
	crystal.global_position = global_position + Vector2(randf_range(-5, 5), randf_range(-5, 5))
	crystal.z_index = 2
	scene_root.add_child(crystal)
	var t := crystal.create_tween()
	t.set_parallel(true)
	t.tween_property(crystal, \"scale\", Vector2(2.5, 2.5), 0.4).set_trans(Tween.TRANS_QUAD)
	t.tween_property(crystal, \"modulate:a\", 0.0, 0.4)
	t.chain().tween_callback(crystal.queue_free)

func _simple_bullet_script() -> String:
	return \"extends Area2D\\nvar direction := Vector2.ZERO\\nvar speed := 350.0\\nvar damage := 5\\nvar lifetime := 1.5\\n\\nfunc _ready():\\n\\tbody_entered.connect(func(body):\\n\\t\\tif body.has_method(\\\\\\\"take_damage\\\\\\\"):\\n\\t\\t\\tbody.take_damage(damage)\\n\\t\\tset_deferred(\\\\\\\"monitoring\\\\\\\", false)\\n\\t\\tcall_deferred(\\\\\\\"queue_free\\\\\\\")\\n\\t)\\n\\tcollision_layer = 2\\n\\tcollision_mask = 4\\n\\nfunc _process(delta):\\n\\tposition += direction * speed * delta\\n\\tlifetime -= delta\\n\\tif lifetime <= 0:\\n\\t\\tset_deferred(\\\\\\\"monitoring\\\\\\\", false)\\n\\t\\tcall_deferred(\\\\\\\"queue_free\\\\\\\")\\n\"
"""
