extends Node2D

## AutoAttack - 最寄りの敵に自動で弾を発射する。

@export var fire_rate := 0.5  # 秒間隔
@export var bullet_speed := 400.0
@export var bullet_damage := 10.0

var timer := 0.0

func _process(delta: float) -> void:
	timer += delta
	if timer >= fire_rate:
		timer = 0.0
		_fire_at_nearest()

func _fire_at_nearest() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	# 最寄りの敵を探す
	var nearest: Node2D = null
	var nearest_dist := INF

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	if nearest == null or nearest_dist > 600:
		return

	_create_bullet(nearest)

func _create_bullet(target: Node2D) -> void:
	var bullet := Area2D.new()
	bullet.name = "Bullet"
	bullet.add_to_group("bullets")
	bullet.global_position = global_position

	# コリジョン
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	bullet.add_child(col)

	# ビジュアル（発光する小さい円）
	var visual := _create_bullet_visual()
	bullet.add_child(visual)

	# 方向
	var direction := (target.global_position - global_position).normalized()

	# スクリプトをインラインで
	var script := GDScript.new()
	script.source_code = """extends Area2D

var direction := Vector2.ZERO
var speed := 400.0
var damage := 10.0
var lifetime := 3.0

func _ready():
	# 敵との当たり判定
	body_entered.connect(_on_body_entered)
	# レイヤー設定: 弾はレイヤー2、敵を検出
	collision_layer = 2
	collision_mask = 4

func _process(delta):
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

func _on_body_entered(body):
	if body.has_method(\"take_damage\"):
		body.take_damage(damage)
	queue_free()
"""
	script.reload()
	bullet.set_script(script)
	bullet.set("direction", direction)
	bullet.set("speed", bullet_speed)
	bullet.set("damage", bullet_damage)

	get_tree().current_scene.add_child(bullet)

func _create_bullet_visual() -> Node2D:
	# 発光する小さな円
	var draw_node := Node2D.new()

	# Polygon2Dで円を近似
	var polygon := Polygon2D.new()
	var points: PackedVector2Array = []
	for i in range(8):
		var angle := i * TAU / 8
		points.append(Vector2(cos(angle), sin(angle)) * 4.0)
	polygon.polygon = points
	polygon.color = Color(0.8, 0.9, 1.0, 0.9)
	draw_node.add_child(polygon)

	return draw_node
