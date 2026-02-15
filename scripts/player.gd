extends CharacterBody2D

## Player - 発光する多角形。WASD/矢印キーで移動。
## 自動攻撃は別スクリプト(auto_attack.gd)で管理。

const SPEED := 200.0

@export var max_hp := 100.0
var hp: float

# オーブスロット（取得済みオーブのリスト）
var orbs: Array[String] = []

signal hp_changed(current: float, maximum: float)
signal died

func _ready() -> void:
	hp = max_hp
	# 画面中央に配置
	position = get_viewport_rect().size / 2

func _physics_process(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	velocity = input_dir.normalized() * SPEED
	move_and_slide()

	# 画面端クランプ
	var vp_size := get_viewport_rect().size
	position = position.clamp(Vector2(16, 16), vp_size - Vector2(16, 16))

func take_damage(amount: float) -> void:
	hp -= amount
	hp_changed.emit(hp, max_hp)

	if hp <= 0:
		hp = 0
		died.emit()

func add_orb(orb_type: String) -> void:
	orbs.append(orb_type)

func has_orb(orb_type: String) -> bool:
	return orb_type in orbs
