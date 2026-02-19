extends Control

## Title Screen — entry point for the game.
## Start game, open settings, or quit.

var settings_panel: PanelContainer = null
var volume_slider: HSlider = null
var fullscreen_check: CheckBox = null

func _ready() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(PRESET_CENTER)
	vbox.offset_left = -200
	vbox.offset_right = 200
	vbox.offset_top = -180
	vbox.offset_bottom = 180
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Spell Cascade"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = "Build. Survive. Cascade."
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	# Start button
	var start_btn := Button.new()
	start_btn.text = "Start Game"
	start_btn.custom_minimum_size = Vector2(200, 40)
	start_btn.pressed.connect(_on_start)
	vbox.add_child(start_btn)

	# Settings button
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(200, 40)
	settings_btn.pressed.connect(_on_settings)
	vbox.add_child(settings_btn)

	# Quit button
	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(200, 40)
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# Build settings panel (hidden)
	_build_settings_panel()

func _on_start() -> void:
	# change_scene_to_file はwebビルドでスレッドローダーが使われ失敗する場合がある。
	# load() + change_scene_to_packed() を使うと確実に同期ロードされる。
	var scene: PackedScene = load("res://scenes/game.tscn")
	if scene != null:
		get_tree().change_scene_to_packed(scene)
	else:
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
