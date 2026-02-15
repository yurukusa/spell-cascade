extends CharacterBody2D

## Tower - プレイヤーアバター兼装備台。
## WASD移動 + モジュールスロット。攻撃はアバターから発射。
## PoEの「自分のビルドで自分が暴れる」を体現。

signal module_changed(slot_index: int)
signal tower_damaged(current_hp: float, max_hp: float)
signal tower_destroyed

@export var max_hp := 500.0
@export var max_slots := 3
@export var move_speed := 200.0

var hp: float
var modules: Array = []  # Array of BuildSystem.TowerModule

func _ready() -> void:
	hp = max_hp
	for i in range(max_slots):
		modules.append(null)

func _physics_process(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1

	velocity = input_dir.normalized() * move_speed
	move_and_slide()

	# 画面外に出ないようクランプ
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, 24.0, vp.x - 24.0)
	position.y = clampf(position.y, 24.0, vp.y - 24.0)

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
