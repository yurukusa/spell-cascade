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

	# 被弾フィードバック: 画面フラッシュ + ヒットフリーズ + シェイク
	_hit_feedback(amount)

	if hp <= 0:
		hp = 0
		died.emit()

func _hit_feedback(amount: float) -> void:
	# 画面赤フラッシュ（ダメージ量でα強度変化）
	var flash_alpha := clampf(amount / max_hp * 3.0, 0.1, 0.4)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.1, 0.05, flash_alpha)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 200
	# CanvasLayerに追加して確実にUIの上に表示
	var ui_layer := get_tree().current_scene.get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(flash)
	else:
		get_tree().current_scene.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.15)
	tween.tween_callback(flash.queue_free)

	# ヒットフリーズ（50ms）— 大ダメージほど長い
	var freeze_ms := 30 if amount < 15.0 else 50
	Engine.time_scale = 0.05
	if not is_inside_tree():
		Engine.time_scale = 1.0
		return
	await get_tree().create_timer(freeze_ms * 0.001 * 0.05).timeout  # real time
	Engine.time_scale = 1.0

	# スクリーンシェイク（Tower経由）
	var tower := get_node_or_null("../Tower")
	if tower and tower.has_method("shake"):
		var intensity := clampf(amount / 5.0, 2.0, 8.0)
		tower.shake(intensity)

	# 被弾SE
	SFX.play_damage()

func add_orb(orb_type: String) -> void:
	orbs.append(orb_type)

func has_orb(orb_type: String) -> bool:
	return orb_type in orbs
