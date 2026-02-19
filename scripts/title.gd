extends Control

## Title Screen — entry point for the game.
## Start game, open settings, or quit.
## 改善185: タイトルアニメーション（呼吸するタイトル + カスケードパーティクル）

var settings_panel: PanelContainer = null
var volume_slider: HSlider = null
var fullscreen_check: CheckBox = null
var _title_label: Label = null
var _particle_timer := 0.0
var _transitioning := false  # Web環境でのダブルクリック/連打による二重シーン遷移を防止

func _ready() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# 改善185: カスケードパーティクル背景（魔法的な雰囲気を演出）
	_spawn_background_particles()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(PRESET_CENTER)
	vbox.offset_left = -200
	vbox.offset_right = 200
	vbox.offset_top = -180
	vbox.offset_bottom = 180
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)

	# Title — 改善185: スケールイン + 継続的な「呼吸」アニメーション
	var title := Label.new()
	title.text = "Spell Cascade"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate.a = 0.0
	title.scale = Vector2(0.7, 0.7)
	vbox.add_child(title)
	_title_label = title
	# 登場アニメーション: スケールイン + フェードイン
	var title_tween := title.create_tween()
	title_tween.set_parallel(true)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD)
	title_tween.tween_property(title, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	title_tween.chain().tween_callback(_start_title_breathing)

	# 改善219: サブタイトル＋ボタンの千鳥フェードイン（タイトルアニメーション完了後に順次登場）
	# Why: タイトルが0.5sのスケールイン演出を持つのに、サブタイトルとボタンは即時表示で
	# 「タイトルだけ演出があって残りは雑」という断絶感があった。
	# サブタイトル0.55s→Start 0.75s→Settings 0.90s→Quit 1.05sで
	# 画面全体が「開幕のロール」として統一感を持って登場するようにする。

	# Subtitle
	var sub := Label.new()
	sub.text = "Build. Survive. Cascade."
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.0
	vbox.add_child(sub)
	var sub_tw := sub.create_tween()
	sub_tw.tween_interval(0.55)
	sub_tw.tween_property(sub, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	# Start button — styled with dungeon-themed panel
	var start_btn := Button.new()
	start_btn.text = "Start Game"
	start_btn.custom_minimum_size = Vector2(220, 48)
	start_btn.pressed.connect(_on_start)
	start_btn.modulate.a = 0.0
	_style_menu_button(start_btn, Color(0.2, 0.55, 0.85, 1.0))  # Cyan accent
	vbox.add_child(start_btn)
	var s_tw := start_btn.create_tween()
	s_tw.tween_interval(0.75)
	s_tw.tween_property(start_btn, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD)

	# Settings button
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(220, 48)
	settings_btn.pressed.connect(_on_settings)
	settings_btn.modulate.a = 0.0
	_style_menu_button(settings_btn, Color(0.4, 0.4, 0.55, 1.0))  # Neutral grey
	vbox.add_child(settings_btn)
	var set_tw := settings_btn.create_tween()
	set_tw.tween_interval(0.9)
	set_tw.tween_property(settings_btn, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD)

	# Quit button
	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(220, 48)
	quit_btn.pressed.connect(_on_quit)
	quit_btn.modulate.a = 0.0
	_style_menu_button(quit_btn, Color(0.5, 0.3, 0.3, 1.0))  # Muted red
	vbox.add_child(quit_btn)
	var q_tw := quit_btn.create_tween()
	q_tw.tween_interval(1.05)
	q_tw.tween_property(quit_btn, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD)

	# Build settings panel (hidden)
	_build_settings_panel()

func _process(delta: float) -> void:
	# 改善185: 継続的にカスケードパーティクルを生成
	_particle_timer -= delta
	if _particle_timer <= 0:
		_particle_timer = 0.15 + randf() * 0.2  # 0.15〜0.35s間隔
		_emit_cascade_particle()

func _start_title_breathing() -> void:
	## タイトルの呼吸アニメーション（ループ）
	if _title_label == null or not is_instance_valid(_title_label):
		return
	var breath := _title_label.create_tween()
	breath.set_loops()  # 永久ループ
	breath.tween_property(_title_label, "scale", Vector2(1.03, 1.03), 1.8).set_trans(Tween.TRANS_SINE)
	breath.tween_property(_title_label, "scale", Vector2(0.97, 0.97), 1.8).set_trans(Tween.TRANS_SINE)

func _spawn_background_particles() -> void:
	## 初期バースト: 20個のパーティクルをランダム配置でフェードイン
	for i in 20:
		_emit_cascade_particle(true)

func _emit_cascade_particle(initial: bool = false) -> void:
	## カスケード魔法パーティクル: 上から下に落ちる輝く点
	var dot := Polygon2D.new()
	var sides := 4 + randi() % 3  # 4〜6角形
	var radius := 2.0 + randf() * 5.0
	var pts := PackedVector2Array()
	for j in sides:
		var a := float(j) * TAU / sides
		pts.append(Vector2(cos(a), sin(a)) * radius)
	dot.polygon = pts
	# カラー: 青系〜紫系〜シアン系をランダム
	var hue := randf_range(0.55, 0.75)  # 青〜紫の範囲
	dot.color = Color.from_hsv(hue, 0.6, 1.0, 0.0)
	var start_x := randf() * 1280.0
	var start_y := -20.0 if not initial else randf() * 720.0
	dot.position = Vector2(start_x, start_y)
	dot.z_index = -1  # 背景より後ろ、でも見える
	add_child(dot)
	# 落下アニメーション
	var fall_dur := randf_range(3.0, 7.0)
	var fall_tween := dot.create_tween()
	fall_tween.set_parallel(true)
	# フェードイン → フェードアウト
	fall_tween.tween_property(dot, "color:a", 0.4 + randf() * 0.4, 0.3)
	fall_tween.tween_property(dot, "color:a", 0.0, 0.8).set_delay(fall_dur - 0.8)
	# Y軸落下
	fall_tween.tween_property(dot, "position:y", start_y + 720.0 + 40.0, fall_dur).set_trans(Tween.TRANS_QUAD)
	# 微妙なX揺れ
	fall_tween.tween_property(dot, "position:x", start_x + randf_range(-40.0, 40.0), fall_dur).set_trans(Tween.TRANS_SINE)
	fall_tween.chain().tween_callback(dot.queue_free)

func _style_menu_button(btn: Button, accent: Color) -> void:
	## Dungeon-themed button style using StyleBoxFlat panels.
	## Why not NinePatchRect: Button has built-in stylebox support, simpler this way.
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)

	# Normal state
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.06, 0.14, 0.9)
	normal.border_color = accent.darkened(0.2)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	# Hover state: lighter border + slight bg shift
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.1, 0.2, 0.95)
	hover.border_color = accent.lightened(0.1)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed state: invert brightness
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = accent.darkened(0.5)
	pressed.border_color = accent.lightened(0.3)
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(4)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Focus style (keyboard nav)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.1, 0.08, 0.18, 0.95)
	focus.border_color = accent.lightened(0.2)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	focus.set_content_margin_all(8)
	btn.add_theme_stylebox_override("focus", focus)

func _on_start() -> void:
	if _transitioning:
		return
	_transitioning = true
	# change_scene_to_file はwebビルドでスレッドローダーが使われ失敗する場合がある。
	# load() + change_scene_to_packed() を使うと確実に同期ロードされる。
	var scene: PackedScene = load("res://scenes/game.tscn")
	if scene != null:
		get_tree().change_scene_to_packed(scene)
	else:
		_transitioning = false
		push_error("Failed to load game.tscn")

func _on_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		# Sync UI with current state
		var vol_db: float = AudioServer.get_bus_volume_db(0)
		volume_slider.value = db_to_linear(vol_db) * 100.0
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_quit() -> void:
	get_tree().quit()

func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	settings_panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	settings_panel.offset_left = -180
	settings_panel.offset_right = 180
	settings_panel.offset_top = -100
	settings_panel.offset_bottom = 100
	add_child(settings_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.14, 0.95)
	panel_style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(16)
	settings_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	settings_panel.add_child(vbox)

	# Settings title
	var lbl := Label.new()
	lbl.text = "Settings"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	# Volume
	var vol_hbox := HBoxContainer.new()
	vol_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(vol_hbox)

	var vol_lbl := Label.new()
	vol_lbl.text = "Volume"
	vol_lbl.add_theme_font_size_override("font_size", 14)
	vol_lbl.custom_minimum_size = Vector2(80, 0)
	vol_hbox.add_child(vol_lbl)

	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.value = 80
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(_on_volume_changed)
	vol_hbox.add_child(volume_slider)

	# Fullscreen
	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.add_theme_font_size_override("font_size", 14)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(fullscreen_check)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): settings_panel.visible = false)
	vbox.add_child(close_btn)

func _on_volume_changed(value: float) -> void:
	# Convert 0-100 linear to dB
	var linear := value / 100.0
	if linear <= 0.01:
		AudioServer.set_bus_volume_db(0, -80.0)
	else:
		AudioServer.set_bus_volume_db(0, linear_to_db(linear))

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _unhandled_input(event: InputEvent) -> void:
	# Space or Enter also starts the game
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if not settings_panel.visible:
				_on_start()
		elif event.keycode == KEY_ESCAPE:
			if settings_panel.visible:
				settings_panel.visible = false
