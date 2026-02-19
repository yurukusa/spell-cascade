extends CanvasLayer

## UpgradeUI - Wave Clear時に3択のオーブ選択を表示。
## 選択中はゲームを一時停止。

signal orb_selected(orb_type: int)

var panel: PanelContainer
var title_label: Label
var buttons_container: VBoxContainer
var current_choices: Array = []

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # pause中もUI操作可能
	_build_ui()
	hide_ui()

func _build_ui() -> void:
	# 半透明の暗幕
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	add_child(overlay)

	# 中央パネル
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_top = -180
	panel.offset_right = 200
	panel.offset_bottom = 180

	# パネルスタイル（プレースホルダ、design.md後に差し替え）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.2, 0.95)
	style.border_color = Color(0.4, 0.3, 0.8, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# タイトル
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "Choose an Orb"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title_label)

	# ボタンコンテナ
	buttons_container = VBoxContainer.new()
	buttons_container.name = "Buttons"
	buttons_container.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons_container)

func show_choices(orb_types: Array) -> void:
	current_choices = orb_types

	# 既存ボタンを削除
	for child in buttons_container.get_children():
		child.queue_free()

	# オーブごとにボタン生成
	for orb_type in orb_types:
		var info = OrbData.get_orb(orb_type)
		if info == null:
			continue

		var btn := Button.new()
		btn.text = "%s\n%s" % [info.name, info.description]
		btn.custom_minimum_size = Vector2(350, 60)

		# ボタンスタイル（プレースホルダ）
		var style := StyleBoxFlat.new()
		style.bg_color = Color(info.color.r * 0.3, info.color.g * 0.3, info.color.b * 0.3, 0.9)
		style.border_color = info.color
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", style)

		var hover_style := style.duplicate()
		hover_style.bg_color = Color(info.color.r * 0.5, info.color.g * 0.5, info.color.b * 0.5, 0.95)
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.pressed.connect(_on_orb_chosen.bind(orb_type))
		buttons_container.add_child(btn)

	# 改善207: パネルポップイン（Wave Clear の達成感をオーブ選択UIの登場でさらに高める）
	# Why: visible=trueの瞬間表示は「急に止まった」という断絶感。
	# scale pop + ボタン千鳥入場で「特別な選択の瞬間」を演出。
	# TWEEN_PAUSE_PROCESS: paused=true後もtweenが動くように明示指定。
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0
	visible = true
	get_tree().paused = true
	var pop := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pop.set_parallel(true)
	pop.tween_property(panel, "modulate:a", 1.0, 0.12)
	pop.tween_property(panel, "scale", Vector2(1.08, 1.08), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.chain().tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)
	var btns := buttons_container.get_children()
	for i in range(btns.size()):
		btns[i].modulate.a = 0.0
		var bt := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		bt.tween_interval(0.12 + i * 0.05)
		bt.tween_property(btns[i], "modulate:a", 1.0, 0.1)

func hide_ui() -> void:
	# 改善216: #207ポップインと対になる縮小フェードアウト退場演出
	# Why: show_choices()は0.7→1.08→1.0のポップインを持つのにhide_ui()はvisible=falseの
	# 即時消滅で「断絶感」があった。対称的な退場で「選択が完了した」感を演出。
	# _on_orb_chosen()でget_tree().paused=falseした後に呼ばれるので通常tweenで問題ない。
	var overlay_node := get_node_or_null("Overlay")
	for btn in buttons_container.get_children():
		if btn is Control:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ht := create_tween()
	ht.set_parallel(true)
	ht.tween_property(panel, "scale", Vector2(0.82, 0.82), 0.14).set_trans(Tween.TRANS_QUAD)
	ht.tween_property(panel, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD)
	if overlay_node:
		ht.tween_property(overlay_node, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD)
	ht.chain().tween_callback(func() -> void:
		visible = false
		panel.scale = Vector2(1.0, 1.0)
		panel.modulate.a = 1.0
		if overlay_node and is_instance_valid(overlay_node):
			overlay_node.modulate.a = 1.0
	)

func _on_orb_chosen(orb_type: int) -> void:
	get_tree().paused = false
	hide_ui()
	orb_selected.emit(orb_type)
