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
var _trail_timer := 0.0  # トレイル発生タイマー

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

	# スポーンポップ演出（H-1: Make it Pop — 「拾えるものが出た」を一瞬で知覚させる）
	scale = Vector2(0.1, 0.1)
	var spawn_tween := create_tween()
	spawn_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_visual() -> void:
	var color := Color(0.3, 0.9, 0.4, 0.9)  # 緑XPオーブ
	if orb_type == "chip":
		color = Color(0.9, 0.7, 0.2, 0.9)  # 金色チップドロップ
	elif orb_type == "chip_move":
		color = Color(0.6, 0.3, 1.0, 0.9)  # 紫のAutoMoveチップ
	elif orb_type == "hp":
		color = Color(1.0, 0.25, 0.3, 0.9)  # 赤のHP回復オーブ

	# 外側グロー（HPオーブは4角ダイヤ、その他は6角）
	# HPオーブは大きめ（改善46: 「回復チャンス」を見逃さないよう視認性向上）
	# 改善143: 高XP値オーブ（xp_value>=3）は1.5倍サイズ＋8角形（ボスや強敵のXPドロップを目立たせる）
	var sides := 4 if orb_type == "hp" else (8 if xp_value >= 3 else 6)
	var size_mult := 1.5 if (orb_type == "xp" and xp_value >= 3) else 1.0
	var glow_radius := 14.0 if orb_type == "hp" else 10.0 * size_mult
	var core_radius := 7.0 if orb_type == "hp" else 5.0 * size_mult
	var glow := Polygon2D.new()
	var glow_pts: PackedVector2Array = []
	for i in range(sides):
		var a := i * TAU / sides
		glow_pts.append(Vector2(cos(a), sin(a)) * glow_radius)
	glow.polygon = glow_pts
	glow.color = Color(color.r, color.g, color.b, 0.25)
	add_child(glow)

	# コア
	var core := Polygon2D.new()
	var core_pts: PackedVector2Array = []
	for i in range(sides):
		var a := i * TAU / sides
		core_pts.append(Vector2(cos(a), sin(a)) * core_radius)
	core.polygon = core_pts
	core.color = color
	add_child(core)

	# パルスアニメーション（改善70: チップオーブは高速パルスで「特別感」を強調）
	var pulse_speed := 0.25 if orb_type in ["chip", "chip_move"] else 0.4
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(core, "scale", Vector2(1.2, 1.2), pulse_speed).set_trans(Tween.TRANS_SINE)
	tween.tween_property(core, "scale", Vector2(1.0, 1.0), pulse_speed).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0:
		set_deferred("monitoring", false)
		call_deferred("queue_free")
		set_process(false)
		return

	# 改善69: 有効期限が近いXPオーブの点滅（「急いで拾え」の視覚的合図）
	if orb_type == "xp" and lifetime < 1.5:
		var flicker: float = abs(sin(lifetime * TAU * 4.0))  # 改善144: 型推論警告修正
		modulate.a = 0.3 + flicker * 0.7

	# 改善142: HPオーブの高速点滅（タワーHP30%未満時: 「今すぐ拾え」の緊急シグナル）
	if orb_type == "hp" and is_instance_valid(target) and "max_hp" in target and "hp" in target:
		var hp_ratio: float = float(target.hp) / float(target.max_hp)
		if hp_ratio < 0.3:
			var pulse_freq := 6.0 + (1.0 - hp_ratio / 0.3) * 6.0  # HP低いほど高速（6〜12Hz）
			var flicker_hp: float = abs(sin(lifetime * TAU * pulse_freq))  # 改善144: 型推論警告修正
			modulate.a = 0.45 + flicker_hp * 0.55

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
		# スピードが一定以上のとき: トレイルスパーク（ジュース感 H-1）
		if speed > 120.0:
			_trail_timer -= delta
			if _trail_timer <= 0:
				_trail_timer = 0.06  # 最大16/秒
				_emit_trail_dot()
	else:
		# 範囲外: ゆっくり浮遊
		position.y += sin(lifetime * 3.0) * 0.3

func _emit_trail_dot() -> void:
	## 吸引中のトレイル点（オーブが飛ぶ感触を強化: H-1 Make it Pop）
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var dot := Polygon2D.new()
	var sides := 4 if orb_type == "hp" else 6
	var dot_pts: PackedVector2Array = []
	for i in range(sides):
		var a := float(i) * TAU / sides
		dot_pts.append(Vector2(cos(a), sin(a)) * 2.5)
	dot.polygon = dot_pts
	dot.global_position = global_position
	var dot_color := Color(0.3, 0.9, 0.4, 0.55)  # XP: 緑
	if orb_type == "hp":
		dot_color = Color(1.0, 0.28, 0.3, 0.55)  # HP: 赤
	elif orb_type in ["chip", "chip_move"]:
		dot_color = Color(1.0, 0.85, 0.3, 0.55)  # Chip: 金
	dot.color = dot_color
	dot.z_index = 5
	scene_root.add_child(dot)
	var tween := dot.create_tween()
	tween.set_parallel(true)
	tween.tween_property(dot, "scale", Vector2(2.5, 2.5), 0.18)
	tween.tween_property(dot, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(dot.queue_free)

func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_on_collected()

func _on_collected() -> void:
	if orb_type == "chip":
		_equip_auto_aim()
	elif orb_type == "chip_move":
		_equip_auto_move()
	elif orb_type == "hp":
		# HP回復: 最大HPの13%を回復（v0.3.4: 15%→13%、Run Desire改善）
		if is_instance_valid(target) and target.has_method("heal"):
			var heal_amount: float = target.max_hp * 0.13
			target.heal(heal_amount)
	elif is_instance_valid(target) and target.has_method("add_xp"):
		target.add_xp(xp_value)
		SFX.play_xp_pickup()

	# 改善128: タイプ別色の回収エフェクト（XP=緑, HP=赤, Chip=金）
	var collect_color: Color
	if orb_type == "hp":
		collect_color = Color(1.0, 0.3, 0.35, 0.8)
	elif orb_type in ["chip", "chip_move"]:
		collect_color = Color(1.0, 0.88, 0.25, 0.8)
	else:
		collect_color = Color(0.4, 1.0, 0.55, 0.8)  # XP: 緑

	var flash := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(8):
		var a := i * TAU / 8
		pts.append(Vector2(cos(a), sin(a)) * 8.0)
	flash.polygon = pts
	flash.color = collect_color
	flash.global_position = global_position

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(flash)
		var tween := flash.create_tween()
		tween.set_parallel(true)
		tween.tween_property(flash, "scale", Vector2(2.5, 2.5), 0.2)
		tween.tween_property(flash, "modulate:a", 0.0, 0.2)
		tween.chain().tween_callback(flash.queue_free)
		# 改善129: 回収時スパークル（3粒の輝く粒子）
		for _si in range(3):
			var sp := Polygon2D.new()
			sp.polygon = PackedVector2Array([
				Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -3.0)
			])
			sp.color = collect_color
			sp.global_position = global_position
			sp.z_index = 110
			scene_root.add_child(sp)
			var sa := randf() * TAU
			var sd := randf_range(12.0, 24.0)
			var st := sp.create_tween()
			st.set_parallel(true)
			st.tween_property(sp, "global_position",
				global_position + Vector2(cos(sa), sin(sa)) * sd, 0.3
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			st.tween_property(sp, "modulate:a", 0.0, 0.3)
			st.chain().tween_callback(sp.queue_free)

	# physics callback中のarea_set_shape_disabledエラー防止: monitoring無効化→遅延free
	set_deferred("monitoring", false)
	call_deferred("queue_free")

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

func _equip_auto_move() -> void:
	var build_sys := get_node_or_null("/root/BuildSystem")
	if build_sys:
		build_sys.equip_chip("move", "kite")

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	# "AUTO MOVE ACQUIRED!" 表示（紫テーマ）
	var label := Label.new()
	label.text = "AUTO MOVE ACQUIRED!"
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.global_position = global_position + Vector2(-140, -60)
	label.z_index = 200
	scene_root.add_child(label)

	var announce_tween := label.create_tween()
	announce_tween.set_parallel(true)
	announce_tween.tween_property(label, "global_position:y", label.global_position.y - 80.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	announce_tween.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(1.0)
	announce_tween.chain().tween_callback(label.queue_free)

	# 紫の大きな閃光
	var big_flash := Polygon2D.new()
	var big_pts: PackedVector2Array = []
	for i in range(12):
		var a := i * TAU / 12
		big_pts.append(Vector2(cos(a), sin(a)) * 40.0)
	big_flash.polygon = big_pts
	big_flash.color = Color(0.6, 0.3, 1.0, 0.8)
	big_flash.global_position = global_position
	scene_root.add_child(big_flash)

	var flash_tween := big_flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(big_flash, "scale", Vector2(4.0, 4.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(big_flash, "modulate:a", 0.0, 0.4)
	flash_tween.chain().tween_callback(big_flash.queue_free)
