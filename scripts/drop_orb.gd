extends Area2D

## DropOrb - 敵撃破時に出現するXPオーブ。
## プレイヤーに向かって加速し、接触で回収。
## 将来: AutoAimチップ、装備ドロップもこの仕組みで。

var target: Node2D  # プレイヤー（タワー）
var speed := 50.0  # 初速（即座に動き出す感触）
var max_speed := 500.0
var acceleration := 800.0
var attract_range := 200.0  # この距離以内で吸い寄せ開始
var lifetime := 6.0  # 短めにして早めにauto-attract
var xp_value := 1
var orb_type := "xp"  # "xp", "chip", "item"

func _ready() -> void:
	# コリジョン設定
	collision_layer = 8
	collision_mask = 1

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	add_child(col)

	body_entered.connect(_on_body_entered)

	# ビジュアル: 小さな輝くオーブ
	_create_visual()

func _create_visual() -> void:
	var color := Color(0.3, 0.9, 0.4, 0.9)  # 緑XPオーブ
	if orb_type == "chip":
		color = Color(0.9, 0.7, 0.2, 0.9)  # 金色チップドロップ

	# 外側グロー
	var glow := Polygon2D.new()
	var glow_pts: PackedVector2Array = []
	for i in range(6):
		var a := i * TAU / 6
		glow_pts.append(Vector2(cos(a), sin(a)) * 10.0)
	glow.polygon = glow_pts
	glow.color = Color(color.r, color.g, color.b, 0.25)
	add_child(glow)

	# コア
	var core := Polygon2D.new()
	var core_pts: PackedVector2Array = []
	for i in range(6):
		var a := i * TAU / 6
		core_pts.append(Vector2(cos(a), sin(a)) * 5.0)
	core.polygon = core_pts
	core.color = color
	add_child(core)

	# パルスアニメーション
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(core, "scale", Vector2(1.2, 1.2), 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(core, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return

	if not is_instance_valid(target):
		return

	var dist := global_position.distance_to(target.global_position)

	# ターゲットのattract_range_bonusを加算
	var effective_range := attract_range
	if "attract_range_bonus" in target:
		effective_range += target.attract_range_bonus

	# 吸い寄せ範囲内か、2秒後は常に吸い寄せ
	if dist < effective_range or lifetime < 4.0:
		speed = minf(speed + acceleration * delta, max_speed)
		var dir := (target.global_position - global_position).normalized()
		position += dir * speed * delta
	else:
		# 範囲外: ゆっくり浮遊
		position.y += sin(lifetime * 3.0) * 0.3

func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_on_collected()

func _on_collected() -> void:
	if orb_type == "chip":
		_equip_auto_aim()
	elif is_instance_valid(target) and target.has_method("add_xp"):
		target.add_xp(xp_value)

	# 回収エフェクト
	var flash := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(8):
		var a := i * TAU / 8
		pts.append(Vector2(cos(a), sin(a)) * 8.0)
	flash.polygon = pts
	flash.color = Color(1.0, 1.0, 0.8, 0.7)
	flash.global_position = global_position

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(flash)
		var tween := flash.create_tween()
		tween.set_parallel(true)
		tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.15)
		tween.tween_property(flash, "modulate:a", 0.0, 0.15)
		tween.chain().tween_callback(flash.queue_free)

	queue_free()

func _equip_auto_aim() -> void:
	var build_sys := get_node_or_null("/root/BuildSystem")
	if build_sys:
		build_sys.equip_chip("attack", "aim_nearest")

	# 大きなピックアップエフェクト（ゲームが変わる瞬間）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	# "AUTO AIM ACQUIRED!" 表示
	var label := Label.new()
	label.text = "AUTO AIM ACQUIRED!"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.global_position = global_position + Vector2(-120, -50)
	label.z_index = 200
	scene_root.add_child(label)

	var announce_tween := label.create_tween()
	announce_tween.set_parallel(true)
	announce_tween.tween_property(label, "global_position:y", label.global_position.y - 60.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	announce_tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.8)
	announce_tween.chain().tween_callback(label.queue_free)

	# 金色の大きな閃光
	var big_flash := Polygon2D.new()
	var big_pts: PackedVector2Array = []
	for i in range(12):
		var a := i * TAU / 12
		big_pts.append(Vector2(cos(a), sin(a)) * 30.0)
	big_flash.polygon = big_pts
	big_flash.color = Color(1.0, 0.9, 0.3, 0.8)
	big_flash.global_position = global_position
	scene_root.add_child(big_flash)

	var flash_tween := big_flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(big_flash, "scale", Vector2(3.0, 3.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(big_flash, "modulate:a", 0.0, 0.3)
	flash_tween.chain().tween_callback(big_flash.queue_free)
