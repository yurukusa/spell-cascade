extends CharacterBody2D

## Enemy - ピクセルアートキャラクター。ターゲット（タワー）に向かって移動。

@export var speed := 80.0
@export var max_hp := 30.0
@export var damage := 10.0
@export var xp_value := 1

var hp: float
var player: Node2D
var attack_timer := 0.0
var attack_cooldown := 1.0  # メレー攻撃間隔
var enemy_type := "normal"  # "normal", "swarmer", "tank", "boss"

# Boss用
var is_boss := false
var boss_state := "chase"  # "chase", "telegraph_burst", "burst", "telegraph_charge", "charge", "cooldown"
var boss_timer := 0.0
var boss_attack_cd := 3.0  # 攻撃間隔
var boss_attack_timer := 0.0
var boss_telegraph_node: Node2D = null
var boss_phase := 1  # 1=100-66%, 2=66-33%, 3=33-0%
var boss_phase_invuln := 0.0  # フェーズ移行中の無敵時間

signal died(enemy: Node2D)
signal boss_phase_changed(phase: int, hp_pct: float)  # game_mainがHPバー更新用
signal boss_hp_changed(current: float, max_val: float)  # ボスHPバー更新用

func _ready() -> void:
	hp = max_hp
	_install_stylized_visual()

func _install_stylized_visual() -> void:
	var legacy := get_node_or_null("Visual")
	if legacy and legacy is CanvasItem:
		legacy.visible = false

	if get_node_or_null("StylizedVisual") != null:
		return

	var root := Node2D.new()
	root.name = "StylizedVisual"
	add_child(root)

	match enemy_type:
		"swarmer":
			_build_swarmer_visual(root)
		"tank":
			_build_tank_visual(root)
		"boss":
			_build_boss_visual(root)
		_:
			_build_normal_visual(root)

func _build_normal_visual(root: Node2D) -> void:
	## 通常敵: 赤ダイヤモンド（中サイズ）
	var outline := Polygon2D.new()
	outline.color = Color(0.02, 0.02, 0.03, 1.0)
	outline.polygon = _make_diamond(34.0)
	root.add_child(outline)

	var body := Polygon2D.new()
	body.color = Color(0.95, 0.22, 0.20, 1.0)
	body.polygon = _make_diamond(30.0)
	root.add_child(body)

	var eye := Polygon2D.new()
	eye.color = Color(1.0, 0.95, 0.6, 1.0)
	eye.polygon = PackedVector2Array([
		Vector2(6, -3), Vector2(18, 0), Vector2(6, 3),
	])
	root.add_child(eye)

	var aura := Polygon2D.new()
	aura.color = Color(1.0, 0.25, 0.25, 0.08)
	aura.polygon = _make_ngon(10, 44.0)
	root.add_child(aura)
	aura.z_index = -1

func _build_swarmer_visual(root: Node2D) -> void:
	## スウォーマー: 緑三角形（小さく速い）
	var outline := Polygon2D.new()
	outline.color = Color(0.02, 0.02, 0.03, 1.0)
	outline.polygon = _make_ngon(3, 22.0)
	root.add_child(outline)

	var body := Polygon2D.new()
	body.color = Color(0.3, 0.85, 0.25, 1.0)
	body.polygon = _make_ngon(3, 18.0)
	root.add_child(body)

	# 小さな目
	var eye := Polygon2D.new()
	eye.color = Color(1.0, 1.0, 0.8, 1.0)
	eye.polygon = PackedVector2Array([
		Vector2(4, -2), Vector2(12, 0), Vector2(4, 2),
	])
	root.add_child(eye)

func _build_tank_visual(root: Node2D) -> void:
	## タンク: 暗赤八角形（大きく遅い）
	var outline := Polygon2D.new()
	outline.color = Color(0.02, 0.02, 0.03, 1.0)
	outline.polygon = _make_ngon(8, 48.0)
	root.add_child(outline)

	var body := Polygon2D.new()
	body.color = Color(0.6, 0.12, 0.10, 1.0)
	body.polygon = _make_ngon(8, 42.0)
	root.add_child(body)

	# 内側の装甲模様
	var armor := Polygon2D.new()
	armor.color = Color(0.45, 0.08, 0.06, 1.0)
	armor.polygon = _make_ngon(8, 30.0)
	root.add_child(armor)

	# 大きな二つ目
	var eye_l := Polygon2D.new()
	eye_l.color = Color(1.0, 0.7, 0.2, 1.0)
	eye_l.polygon = PackedVector2Array([
		Vector2(8, -8), Vector2(22, -5), Vector2(8, -2),
	])
	root.add_child(eye_l)

	var eye_r := Polygon2D.new()
	eye_r.color = Color(1.0, 0.7, 0.2, 1.0)
	eye_r.polygon = PackedVector2Array([
		Vector2(8, 2), Vector2(22, 5), Vector2(8, 8),
	])
	root.add_child(eye_r)

	# 重厚なオーラ
	var aura := Polygon2D.new()
	aura.color = Color(0.8, 0.15, 0.1, 0.12)
	aura.polygon = _make_ngon(8, 58.0)
	root.add_child(aura)
	aura.z_index = -1

func _build_boss_visual(root: Node2D) -> void:
	## ボス: 紫/金の大型十二角形。威圧的、コアが脈動。
	# 外枠（黒）
	var outline := Polygon2D.new()
	outline.color = Color(0.02, 0.02, 0.03, 1.0)
	outline.polygon = _make_ngon(12, 70.0)
	root.add_child(outline)

	# 本体（深紫）
	var body := Polygon2D.new()
	body.color = Color(0.35, 0.1, 0.55, 1.0)
	body.polygon = _make_ngon(12, 64.0)
	root.add_child(body)

	# 内側リング（暗紫）
	var inner := Polygon2D.new()
	inner.color = Color(0.25, 0.06, 0.4, 1.0)
	inner.polygon = _make_ngon(12, 48.0)
	root.add_child(inner)

	# コア（金色、脈動）
	var core := Polygon2D.new()
	core.name = "BossCore"
	core.color = Color(1.0, 0.85, 0.3, 1.0)
	core.polygon = _make_ngon(6, 20.0)
	root.add_child(core)

	# コア脈動アニメーション
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(core, "scale", Vector2(1.3, 1.3), 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(core, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE)

	# 3つの目（三角配置、威圧感）
	for i in range(3):
		var eye := Polygon2D.new()
		eye.color = Color(1.0, 0.9, 0.4, 1.0)
		var a := float(i) * TAU / 3.0 - PI / 2.0
		var ex := cos(a) * 35.0
		var ey := sin(a) * 35.0
		eye.polygon = PackedVector2Array([
			Vector2(ex - 4, ey - 3), Vector2(ex + 8, ey), Vector2(ex - 4, ey + 3),
		])
		root.add_child(eye)

	# ボスオーラ（紫、強め）
	var aura := Polygon2D.new()
	aura.color = Color(0.5, 0.2, 0.8, 0.15)
	aura.polygon = _make_ngon(12, 85.0)
	root.add_child(aura)
	aura.z_index = -1

func _make_diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius, 0),
		Vector2(0, radius),
		Vector2(-radius, 0),
	])

func _make_ngon(sides: int, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(maxi(sides, 3)):
		var a := float(i) * TAU / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func init(target: Node2D, spd: float = 80.0, health: float = 30.0, dmg: float = 10.0, type: String = "normal") -> void:
	player = target
	enemy_type = type

	# タイプ別ステータス乗数
	match enemy_type:
		"swarmer":
			speed = spd * 1.5
			max_hp = health * 0.4
			damage = dmg * 0.5
			xp_value = 1
			attack_cooldown = 0.8
		"tank":
			speed = spd * 0.5
			max_hp = health * 3.0
			damage = dmg * 2.0
			xp_value = 3
			attack_cooldown = 1.5
		"boss":
			speed = spd * 0.6
			max_hp = health * 8.0
			damage = dmg * 1.5
			xp_value = 10
			attack_cooldown = 2.0
			is_boss = true
			boss_attack_cd = 3.0
		_:  # normal
			speed = spd
			max_hp = health
			damage = dmg
			xp_value = 1

	hp = max_hp

	# タイプ変更後にビジュアル再構築
	var old_visual := get_node_or_null("StylizedVisual")
	if old_visual:
		old_visual.queue_free()
	_install_stylized_visual()

func set_texture(tex: Texture2D) -> void:
	var visual := $Visual as Sprite2D
	if visual:
		visual.texture = tex

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	if is_boss:
		_boss_process(delta)
		return

	var dist := global_position.distance_to(player.global_position)

	# メレー範囲外なら接近
	if dist > 30.0:
		var direction := (player.global_position - global_position).normalized()
		velocity = direction * speed
		move_and_slide()
	else:
		# メレー範囲内: 定期的にダメージ（DPS = damage / attack_cooldown）
		velocity = Vector2.ZERO
		attack_timer += delta
		if attack_timer >= attack_cooldown:
			attack_timer -= attack_cooldown
			if player.has_method("take_damage"):
				player.take_damage(damage)

func _check_boss_phase() -> void:
	## HP割合でフェーズ移行を判定
	var pct := hp / max_hp
	var new_phase := 1
	if pct <= 0.33:
		new_phase = 3
	elif pct <= 0.66:
		new_phase = 2

	if new_phase > boss_phase:
		boss_phase = new_phase
		boss_phase_changed.emit(boss_phase, pct)
		_boss_phase_transition()

func _boss_phase_transition() -> void:
	## フェーズ移行演出: 短い無敵 + 視覚バースト + パラメータ強化
	boss_phase_invuln = 1.2
	boss_state = "cooldown"
	boss_timer = 0.0

	# フェーズ移行でパラメータ強化
	match boss_phase:
		2:
			boss_attack_cd = maxf(boss_attack_cd * 0.7, 1.5)
			speed *= 1.2
			# Phase2移行: 全方位バーストで距離を取らせる
			_boss_fire_burst()
		3:
			boss_attack_cd = maxf(boss_attack_cd * 0.5, 0.8)
			speed *= 1.4
			# Phase3移行: 二重バーストで圧をかける
			_boss_fire_burst()
			# 0.3s後に2回目のバースト（微妙にずれた角度）
			var timer := get_tree().create_timer(0.3)
			timer.timeout.connect(_boss_fire_burst)

	# 視覚: 紫のパルスリング
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var ring := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(16):
		var a: float = float(i) * TAU / 16.0
		pts.append(Vector2(cos(a), sin(a)) * 20.0)
	ring.polygon = pts
	ring.color = Color(0.7, 0.2, 1.0, 0.7)
	ring.global_position = global_position
	ring.z_index = 130
	scene_root.add_child(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(6.0, 6.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)

	# 本体フラッシュ
	modulate = Color(2.0, 1.0, 3.0, 1.0)
	var body_tween := create_tween()
	body_tween.tween_property(self, "modulate", Color.WHITE, 0.4)

func _boss_process(delta: float) -> void:
	## ボス専用AI: chase → 攻撃 → cooldown のループ（フェーズ対応）

	# 無敵タイマー減衰
	if boss_phase_invuln > 0:
		boss_phase_invuln -= delta
		return

	boss_attack_timer += delta

	match boss_state:
		"chase":
			# プレイヤーに接近
			var direction := (player.global_position - global_position).normalized()
			velocity = direction * speed
			move_and_slide()

			# メレーダメージ
			var dist := global_position.distance_to(player.global_position)
			if dist <= 50.0:
				attack_timer += delta
				if attack_timer >= attack_cooldown:
					attack_timer -= attack_cooldown
					if player.has_method("take_damage"):
						player.take_damage(damage)

			# 攻撃パターン発動（フェーズで確率変化）
			if boss_attack_timer >= boss_attack_cd:
				boss_attack_timer = 0.0
				var roll := randf()
				if boss_phase >= 3 and roll < 0.3:
					# Phase 3: 30%でburst+charge連続
					_boss_start_telegraph_burst()
					# burst後にcharge予約（_boss_fire_burstから呼ばれる）
				elif roll < 0.5:
					_boss_start_telegraph_burst()
				else:
					_boss_start_telegraph_charge()

		"telegraph_burst":
			velocity = Vector2.ZERO
			boss_timer += delta
			if boss_timer >= 0.5:
				_boss_fire_burst()

		"burst":
			velocity = Vector2.ZERO
			boss_timer += delta
			if boss_timer >= 0.3:
				boss_state = "cooldown"
				boss_timer = 0.0

		"telegraph_charge":
			velocity = Vector2.ZERO
			boss_timer += delta
			if boss_timer >= 0.5:
				_boss_start_charge()

		"charge":
			boss_timer += delta
			move_and_slide()
			# 突進中の接触ダメージ
			var dist := global_position.distance_to(player.global_position)
			if dist <= 60.0 and player.has_method("take_damage"):
				player.take_damage(damage * 2.0)
				boss_state = "cooldown"
				boss_timer = 0.0
			elif boss_timer >= 1.0:
				boss_state = "cooldown"
				boss_timer = 0.0

		"cooldown":
			velocity = Vector2.ZERO
			boss_timer += delta
			if boss_timer >= 1.0:
				boss_state = "chase"
				boss_timer = 0.0

func _boss_start_telegraph_burst() -> void:
	## 放射弾テレグラフ: 赤い拡大リングで警告
	boss_state = "telegraph_burst"
	boss_timer = 0.0

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var telegraph := Polygon2D.new()
	telegraph.color = Color(1.0, 0.2, 0.1, 0.25)
	telegraph.polygon = _make_ngon(16, 10.0)
	telegraph.global_position = global_position
	telegraph.z_index = -1
	scene_root.add_child(telegraph)
	boss_telegraph_node = telegraph

	# テレグラフ拡大アニメーション
	var tween := telegraph.create_tween()
	tween.tween_property(telegraph, "scale", Vector2(20.0, 20.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _boss_fire_burst() -> void:
	## 8方向に弾を発射
	boss_state = "burst"
	boss_timer = 0.0

	# テレグラフを消す
	if is_instance_valid(boss_telegraph_node):
		boss_telegraph_node.queue_free()
		boss_telegraph_node = null

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	# フェーズで弾数が増加: P1=8, P2=12, P3=16
	var bullet_count := 8 + (boss_phase - 1) * 4
	for i in range(bullet_count):
		var angle := float(i) * TAU / float(bullet_count)
		var dir := Vector2(cos(angle), sin(angle))

		var bullet := Area2D.new()
		bullet.name = "BossBullet"
		bullet.global_position = global_position
		bullet.collision_layer = 4  # enemy bullets
		bullet.collision_mask = 1   # player layer

		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		col.shape = shape
		bullet.add_child(col)

		# 紫の弾ビジュアル
		var visual := Polygon2D.new()
		visual.color = Color(0.7, 0.2, 0.9, 0.9)
		visual.polygon = _make_ngon(6, 12.0)
		bullet.add_child(visual)

		var glow := Polygon2D.new()
		glow.color = Color(0.7, 0.2, 0.9, 0.3)
		glow.polygon = _make_ngon(6, 20.0)
		bullet.add_child(glow)

		scene_root.add_child(bullet)

		# 弾スクリプト（シンプルな直進 + プレイヤーダメージ）
		var script := GDScript.new()
		script.source_code = _boss_bullet_script()
		script.reload()
		bullet.set_script(script)
		bullet.set("direction", dir)
		bullet.set("speed", 200.0)
		bullet.set("damage", damage)

func _boss_start_telegraph_charge() -> void:
	## 突進テレグラフ: 赤く光ってから突進
	boss_state = "telegraph_charge"
	boss_timer = 0.0
	modulate = Color(2.0, 0.4, 0.3, 1.0)

func _boss_start_charge() -> void:
	## 突進実行
	boss_state = "charge"
	boss_timer = 0.0
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	var direction := (player.global_position - global_position).normalized()
	velocity = direction * speed * 4.0  # 4倍速で突進

func _boss_bullet_script() -> String:
	return """extends Area2D
var direction := Vector2.ZERO
var speed := 200.0
var damage := 10.0
var lifetime := 4.0

func _ready():
	body_entered.connect(_on_body_entered)

func _process(delta):
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		set_deferred(\"monitoring\", false)
		call_deferred(\"queue_free\")

func _on_body_entered(body):
	if body.has_method(\"take_damage\"):
		body.take_damage(damage)
	set_deferred(\"monitoring\", false)
	call_deferred(\"queue_free\")
"""

func take_damage(amount: float) -> void:
	# フェーズ移行中の無敵
	if boss_phase_invuln > 0:
		return

	hp -= amount
	_spawn_damage_number(amount)
	SFX.play_hit()

	# ボスHPバー更新
	if is_boss:
		boss_hp_changed.emit(hp, max_hp)
		_check_boss_phase()

	# ヒットフラッシュ
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)

func _spawn_damage_number(amount: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	# ダメージ量に応じてサイズ・色・演出を変化
	var dmg_int := int(amount)
	var font_size := 14
	var color := Color(0.9, 0.85, 0.7, 1.0)  # 小ダメージ: 薄い白
	var float_height := 35.0
	var duration := 0.5

	if amount >= 50.0:
		# 大ダメージ: 赤くて大きい
		font_size = 26
		color = Color(1.0, 0.2, 0.1, 1.0)
		float_height = 55.0
		duration = 0.8
	elif amount >= 25.0:
		# 中ダメージ: オレンジ
		font_size = 20
		color = Color(1.0, 0.7, 0.2, 1.0)
		float_height = 45.0
		duration = 0.65
	elif amount >= 10.0:
		# 普通ダメージ: 黄色
		font_size = 16
		color = Color(1.0, 0.9, 0.4, 1.0)
		float_height = 40.0

	var label := Label.new()
	label.text = str(dmg_int)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.global_position = global_position + Vector2(randf_range(-15, 15), -20)
	label.z_index = 100
	scene_root.add_child(label)

	var float_tween := label.create_tween()
	float_tween.set_parallel(true)
	float_tween.tween_property(label, "global_position:y", label.global_position.y - float_height, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(label, "modulate:a", 0.0, duration).set_delay(duration * 0.3)

	# 大ダメージはスケールバウンスで「重い一撃」を演出
	if amount >= 50.0:
		float_tween.tween_property(label, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_BACK)
		float_tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)

	float_tween.chain().tween_callback(label.queue_free)

	if hp <= 0:
		_spawn_death_vfx()
		_spawn_drops()
		died.emit(self)
		queue_free()

func _spawn_drops() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var drop_script := load("res://scripts/drop_orb.gd")

	# XPオーブを1-3個ドロップ
	var orb_count := randi_range(1, 3)
	for i in range(orb_count):
		var orb := Area2D.new()
		orb.set_script(drop_script)
		orb.name = "XPOrb"
		orb.add_to_group("pickups")
		orb.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
		orb.set("target", player)
		orb.set("xp_value", xp_value)
		scene_root.add_child(orb)

	# HPオーブドロップ判定（通常10%、タンク20%）
	var hp_drop_chance := 0.10
	if enemy_type == "tank":
		hp_drop_chance = 0.20
	if randf() < hp_drop_chance:
		var hp_orb := Area2D.new()
		hp_orb.set_script(drop_script)
		hp_orb.name = "HPOrb"
		hp_orb.add_to_group("pickups")
		hp_orb.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		hp_orb.set("target", player)
		hp_orb.set("orb_type", "hp")
		hp_orb.set("xp_value", 0)
		scene_root.add_child(hp_orb)

	# ボス撃破: AutoMoveチップ保証ドロップ
	if is_boss:
		var build_sys2 := get_node_or_null("/root/BuildSystem")
		if build_sys2:
			var move_chip_id: String = build_sys2.equipped_chips.get("move", "manual")
			if move_chip_id == "manual":
				var chip_orb := Area2D.new()
				chip_orb.set_script(drop_script)
				chip_orb.name = "BossChipDrop"
				chip_orb.add_to_group("pickups")
				chip_orb.global_position = global_position
				chip_orb.set("target", player)
				chip_orb.set("orb_type", "chip_move")
				chip_orb.set("xp_value", 0)
				scene_root.add_child(chip_orb)

	# チップドロップ判定（AutoAim: 未所持なら5%、最低15体倒した後）
	var build_sys := get_node_or_null("/root/BuildSystem")
	if build_sys:
		var attack_chip_id: String = build_sys.equipped_chips.get("attack", "manual_aim")
		if attack_chip_id == "manual_aim" and randf() < 0.05:
			var chip_orb := Area2D.new()
			chip_orb.set_script(drop_script)
			chip_orb.name = "ChipDrop"
			chip_orb.add_to_group("pickups")
			chip_orb.global_position = global_position
			chip_orb.set("target", player)
			chip_orb.set("orb_type", "chip")
			chip_orb.set("xp_value", 0)
			scene_root.add_child(chip_orb)

func _spawn_death_vfx() -> void:
	## キル時の爆散エフェクト。敵タイプでスケール。
	## normal: 6片+小flash / swarmer: 4片+小flash / tank: 10片+大flash / boss: 16片+multi-ring
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	# タイプ別パラメータ
	var fragment_count := 6
	var frag_size_min := 3.0
	var frag_size_max := 7.0
	var frag_dist_min := 30.0
	var frag_dist_max := 80.0
	var flash_radius := 20.0
	var flash_scale := 2.0
	var frag_color := Color(1.0, 0.3, 0.2, 0.9)

	match enemy_type:
		"swarmer":
			fragment_count = 4
			frag_size_min = 2.0
			frag_size_max = 5.0
			frag_dist_max = 60.0
			frag_color = Color(0.3, 0.9, 0.3, 0.9)
		"tank":
			fragment_count = 10
			frag_size_min = 4.0
			frag_size_max = 10.0
			frag_dist_min = 40.0
			frag_dist_max = 120.0
			flash_radius = 30.0
			flash_scale = 2.5
			frag_color = Color(0.6, 0.15, 0.1, 0.9)
		"boss":
			fragment_count = 16
			frag_size_min = 5.0
			frag_size_max = 14.0
			frag_dist_min = 50.0
			frag_dist_max = 160.0
			flash_radius = 40.0
			flash_scale = 3.5
			frag_color = Color(0.7, 0.3, 1.0, 0.9)

	# 破片
	for i in range(fragment_count):
		var frag := Polygon2D.new()
		var angle := randf() * TAU
		var size := randf_range(frag_size_min, frag_size_max)
		frag.polygon = PackedVector2Array([
			Vector2(-size, -size * 0.5),
			Vector2(size, 0),
			Vector2(-size, size * 0.5),
		])
		# 色をわずかにランダム化（単調さ防止）
		var color_var := randf_range(-0.1, 0.1)
		frag.color = Color(
			clampf(frag_color.r + color_var, 0.0, 1.0),
			clampf(frag_color.g + color_var * 0.5, 0.0, 1.0),
			clampf(frag_color.b + color_var, 0.0, 1.0),
			frag_color.a
		)
		frag.global_position = global_position
		frag.rotation = angle
		scene_root.add_child(frag)

		var dist := randf_range(frag_dist_min, frag_dist_max)
		var target_pos := global_position + Vector2(cos(angle), sin(angle)) * dist
		var frag_dur := 0.3 if enemy_type != "boss" else 0.5
		var tween := frag.create_tween()
		tween.set_parallel(true)
		tween.tween_property(frag, "global_position", target_pos, frag_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(frag, "modulate:a", 0.0, frag_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(frag, "scale", Vector2(0.3, 0.3), frag_dur)
		tween.chain().tween_callback(frag.queue_free)

	# メインフラッシュ円
	_spawn_flash_ring(scene_root, flash_radius, flash_scale, 0.15)

	# ボス: 追加リング（2段階の遅延爆発）
	if enemy_type == "boss":
		# ディレイ付き第2リング
		var timer := get_tree().create_timer(0.1)
		timer.timeout.connect(func():
			if is_instance_valid(scene_root):
				_spawn_flash_ring_at(scene_root, global_position, flash_radius * 0.7, 3.0, 0.2, Color(1.0, 0.6, 1.0, 0.5))
		)
		# ディレイ付き第3リング
		var timer2 := get_tree().create_timer(0.2)
		timer2.timeout.connect(func():
			if is_instance_valid(scene_root):
				_spawn_flash_ring_at(scene_root, global_position, flash_radius * 0.5, 4.0, 0.25, Color(1.0, 0.9, 0.5, 0.4))
		)

func _spawn_flash_ring(scene_root: Node, radius: float, target_scale: float, duration: float) -> void:
	_spawn_flash_ring_at(scene_root, global_position, radius, target_scale, duration, Color(1.0, 0.8, 0.6, 0.6))

func _spawn_flash_ring_at(scene_root: Node, pos: Vector2, radius: float, target_scale: float, duration: float, color: Color) -> void:
	var flash := Polygon2D.new()
	var flash_pts: PackedVector2Array = []
	for j in range(12):
		var a: float = float(j) * TAU / 12.0
		flash_pts.append(Vector2(cos(a), sin(a)) * radius)
	flash.polygon = flash_pts
	flash.color = color
	flash.global_position = pos
	flash.z_index = 120
	scene_root.add_child(flash)

	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(target_scale, target_scale), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash, "modulate:a", 0.0, duration)
	flash_tween.chain().tween_callback(flash.queue_free)
