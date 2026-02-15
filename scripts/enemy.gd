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

signal died(enemy: Node2D)

func _ready() -> void:
	hp = max_hp
	_install_stylized_visual()

func _install_stylized_visual() -> void:
	# Replace placeholder sprite with a readable threat silhouette.
	var legacy := get_node_or_null("Visual")
	if legacy and legacy is CanvasItem:
		legacy.visible = false

	if get_node_or_null("StylizedVisual") != null:
		return

	var root := Node2D.new()
	root.name = "StylizedVisual"
	add_child(root)

	# Threat layer: higher contrast/value than player body
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
		Vector2(6, -3),
		Vector2(18, 0),
		Vector2(6, 3),
	])
	root.add_child(eye)

	# Subtle "danger aura" ring (short-lived by default; kept always-on but low alpha)
	var aura := Polygon2D.new()
	aura.color = Color(1.0, 0.25, 0.25, 0.08)
	aura.polygon = _make_ngon(10, 44.0)
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

func init(target: Node2D, spd: float = 80.0, health: float = 30.0, dmg: float = 10.0) -> void:
	player = target
	speed = spd
	max_hp = health
	hp = max_hp
	damage = dmg

func set_texture(tex: Texture2D) -> void:
	var visual := $Visual as Sprite2D
	if visual:
		visual.texture = tex

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
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

func take_damage(amount: float) -> void:
	hp -= amount
	_spawn_damage_number(amount)

	# ヒットフラッシュ
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)

func _spawn_damage_number(amount: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var label := Label.new()
	label.text = str(int(amount))
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.global_position = global_position + Vector2(randf_range(-15, 15), -20)
	label.z_index = 100
	scene_root.add_child(label)

	var float_tween := label.create_tween()
	float_tween.set_parallel(true)
	float_tween.tween_property(label, "global_position:y", label.global_position.y - 40.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
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
	# キル時の爆散エフェクト: 赤い破片が放射状に飛ぶ（PoE的「画面が光る」快感）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var fragment_count := 6
	for i in range(fragment_count):
		var frag := Polygon2D.new()
		var angle := randf() * TAU
		var size := randf_range(3.0, 7.0)
		frag.polygon = PackedVector2Array([
			Vector2(-size, -size * 0.5),
			Vector2(size, 0),
			Vector2(-size, size * 0.5),
		])
		frag.color = Color(1.0, 0.3, 0.2, 0.9)
		frag.global_position = global_position
		frag.rotation = angle
		scene_root.add_child(frag)

		# 飛散アニメーション
		var dist := randf_range(30.0, 80.0)
		var target_pos := global_position + Vector2(cos(angle), sin(angle)) * dist
		var tween := frag.create_tween()
		tween.set_parallel(true)
		tween.tween_property(frag, "global_position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(frag, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(frag, "scale", Vector2(0.3, 0.3), 0.3)
		tween.chain().tween_callback(frag.queue_free)

	# 白フラッシュ円（瞬間的な満足感）
	var flash := Polygon2D.new()
	var flash_pts: PackedVector2Array = []
	for j in range(8):
		var a := j * TAU / 8
		flash_pts.append(Vector2(cos(a), sin(a)) * 20.0)
	flash.polygon = flash_pts
	flash.color = Color(1.0, 0.8, 0.6, 0.6)
	flash.global_position = global_position
	scene_root.add_child(flash)

	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.15)
	flash_tween.chain().tween_callback(flash.queue_free)
