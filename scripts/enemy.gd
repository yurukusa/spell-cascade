extends CharacterBody2D

## Enemy - 色付き幾何学体。プレイヤーに向かって移動。

@export var speed := 80.0
@export var max_hp := 30.0
@export var damage := 10.0
@export var xp_value := 1

var hp: float
var player: Node2D

signal died(enemy: Node2D)

func _ready() -> void:
	hp = max_hp

func init(target: Node2D, spd: float = 80.0, health: float = 30.0, dmg: float = 10.0) -> void:
	player = target
	speed = spd
	max_hp = health
	hp = max_hp
	damage = dmg

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	var direction := (player.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

func take_damage(amount: float) -> void:
	hp -= amount

	# ヒットフラッシュ
	modulate = Color(2, 2, 2, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)

	if hp <= 0:
		died.emit(self)
		queue_free()
