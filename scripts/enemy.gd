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

	# ヒットフラッシュ
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)

	if hp <= 0:
		died.emit(self)
		queue_free()
