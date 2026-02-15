extends CanvasLayer

## BuildUpgradeUI - ビルド判断UI。
## スキル選択、サポートリンク選択、Mod選択の3モードを持つ。
## 選択中はゲーム一時停止。

signal upgrade_chosen(data: Dictionary)

var panel: PanelContainer
var title_label: Label
var buttons_container: VBoxContainer
var build_system: Node

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_system = get_node("/root/BuildSystem")
	_build_ui()
	hide_ui()

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.65)
	add_child(overlay)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_top = -200
	panel.offset_right = 220
	panel.offset_bottom = 200

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.18, 0.95)
	style.border_color = Color(0.5, 0.4, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title_label)

	buttons_container = VBoxContainer.new()
	buttons_container.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons_container)

func _clear_buttons() -> void:
	for child in buttons_container.get_children():
		child.queue_free()

# --- スキル選択 ---

func show_skill_choice(slot: int, skill_ids: Array) -> void:
	_clear_buttons()
	title_label.text = "Choose a Skill (Slot %d)" % (slot + 1)

	for skill_id in skill_ids:
		var skill_data: Dictionary = build_system.skills.get(skill_id, {})
		if skill_data.is_empty():
			continue

		var btn := Button.new()
		var tags_str := ", ".join(PackedStringArray(skill_data.get("tags", [])))
		btn.text = "%s\n%s\nDmg:%d CD:%.1fs [%s]" % [
			skill_data.get("name", "?"),
			skill_data.get("description", ""),
			skill_data.get("base_damage", 0),
			skill_data.get("base_cooldown", 1.0),
			tags_str
		]
		btn.custom_minimum_size = Vector2(400, 70)
		btn.add_theme_font_size_override("font_size", 13)

		var style := _make_button_style(skill_data.get("tags", []))
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

		btn.pressed.connect(_on_skill_chosen.bind(slot, skill_id))
		buttons_container.add_child(btn)

	visible = true
	get_tree().paused = true

func _on_skill_chosen(slot: int, skill_id: String) -> void:
	get_tree().paused = false
	hide_ui()
	upgrade_chosen.emit({"type": "skill", "slot": slot, "skill_id": skill_id})

# --- スキル入れ替え（VS感回避: 追加だけでなく入れ替えも） ---

func show_skill_swap(slot: int, skill_ids: Array) -> void:
	_clear_buttons()
	var tower = get_tree().current_scene.get_node_or_null("Tower")
	var current_name := "?"
	if tower:
		var module: Variant = tower.get_module(slot)
		if module:
			var stats: Dictionary = build_system.calculate_module_stats(module)
			current_name = stats.get("name", "?")
	title_label.text = "Replace %s in Slot %d?" % [current_name, slot + 1]

	for skill_id in skill_ids:
		var skill_data: Dictionary = build_system.skills.get(skill_id, {})
		if skill_data.is_empty():
			continue

		var btn := Button.new()
		var tags_str := ", ".join(PackedStringArray(skill_data.get("tags", [])))
		btn.text = "%s\n%s\nDmg:%d CD:%.1fs [%s]" % [
			skill_data.get("name", "?"),
			skill_data.get("description", ""),
			skill_data.get("base_damage", 0),
			skill_data.get("base_cooldown", 1.0),
			tags_str
		]
		btn.custom_minimum_size = Vector2(400, 70)
		btn.add_theme_font_size_override("font_size", 13)

		var style := _make_button_style(skill_data.get("tags", []))
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

		btn.pressed.connect(_on_skill_chosen.bind(slot, skill_id))
		buttons_container.add_child(btn)

	# スキップ（入れ替えしない）
	var skip_btn := Button.new()
	skip_btn.text = "Keep %s (Skip)" % current_name
	skip_btn.custom_minimum_size = Vector2(400, 40)
	skip_btn.add_theme_font_size_override("font_size", 13)
	skip_btn.pressed.connect(func():
		get_tree().paused = false
		hide_ui()
	)
	buttons_container.add_child(skip_btn)

	visible = true
	get_tree().paused = true

# --- サポート選択 ---

func show_support_choice(support_ids: Array) -> void:
	_clear_buttons()
	title_label.text = "Choose a Support Gem"

	for sup_id in support_ids:
		var sup_data: Dictionary = build_system.supports.get(sup_id, {})
		if sup_data.is_empty():
			continue

		var btn := Button.new()
		btn.text = "%s\n%s\nRequires: [%s]" % [
			sup_data.get("name", "?"),
			sup_data.get("description", ""),
			sup_data.get("requires_tag", "any")
		]
		btn.custom_minimum_size = Vector2(400, 60)
		btn.add_theme_font_size_override("font_size", 13)

		var style := _make_support_style()
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

		btn.pressed.connect(_on_support_chosen.bind(sup_id))
		buttons_container.add_child(btn)

	visible = true
	get_tree().paused = true

func _on_support_chosen(support_id: String) -> void:
	# Step 2: どのスロットにリンクするか選ばせる（PoEの"悩み=力"）
	var tower = get_tree().current_scene.get_node_or_null("Tower")
	if tower == null:
		get_tree().paused = false
		hide_ui()
		return

	var sup_data: Dictionary = build_system.supports.get(support_id, {})
	var req_tag: String = sup_data.get("requires_tag", "")
	var candidates: Array[int] = []

	for i in range(tower.max_slots):
		var module: Variant = tower.get_module(i)
		if module == null or module.support_ids.size() >= 2:
			continue
		# タグ互換性チェック
		if req_tag == "":
			candidates.append(i)
		else:
			var stats: Dictionary = build_system.calculate_module_stats(module)
			if req_tag in stats.get("tags", []):
				candidates.append(i)

	if candidates.is_empty():
		# 互換スロットがない → フォールバック（空きリンクがあるスロット）
		for i in range(tower.max_slots):
			var module: Variant = tower.get_module(i)
			if module != null and module.support_ids.size() < 2:
				candidates.append(i)

	if candidates.is_empty():
		get_tree().paused = false
		hide_ui()
		return

	# スロット選択UIを表示
	_show_slot_choice("Link %s to which slot?" % sup_data.get("name", "?"), tower, candidates,
		func(slot: int) -> void:
			upgrade_chosen.emit({"type": "support", "support_id": support_id, "target_slot": slot})
	)

# --- Mod選択 ---

func show_mod_choice(prefix: Dictionary, suffix: Dictionary) -> void:
	_clear_buttons()
	title_label.text = "Choose a Mod"

	if not prefix.is_empty():
		var btn := Button.new()
		btn.text = "PREFIX: %s\n%s" % [prefix.get("name", "?"), prefix.get("description", "")]
		btn.custom_minimum_size = Vector2(400, 60)
		btn.add_theme_font_size_override("font_size", 13)
		var style := _make_mod_style("prefix")
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)
		btn.pressed.connect(_on_mod_chosen.bind(prefix, "prefix"))
		buttons_container.add_child(btn)

	if not suffix.is_empty():
		var btn := Button.new()
		btn.text = "SUFFIX: %s\n%s" % [suffix.get("name", "?"), suffix.get("description", "")]
		btn.custom_minimum_size = Vector2(400, 60)
		btn.add_theme_font_size_override("font_size", 13)
		var style := _make_mod_style("suffix")
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)
		btn.pressed.connect(_on_mod_chosen.bind(suffix, "suffix"))
		buttons_container.add_child(btn)

	# スキップ選択肢
	var skip_btn := Button.new()
	skip_btn.text = "Skip (Keep current mods)"
	skip_btn.custom_minimum_size = Vector2(400, 40)
	skip_btn.add_theme_font_size_override("font_size", 13)
	skip_btn.pressed.connect(func():
		get_tree().paused = false
		hide_ui()
	)
	buttons_container.add_child(skip_btn)

	visible = true
	get_tree().paused = true

func _on_mod_chosen(mod_data: Dictionary, mod_type: String) -> void:
	var tower = get_tree().current_scene.get_node_or_null("Tower")
	if tower == null:
		get_tree().paused = false
		hide_ui()
		return

	# スキルが入っているスロットを候補にする
	var candidates: Array[int] = []
	for i in range(tower.max_slots):
		if tower.get_module(i) != null:
			candidates.append(i)

	if candidates.is_empty():
		get_tree().paused = false
		hide_ui()
		return

	# スロット選択UIを表示
	var mod_name: String = mod_data.get("name", "?")
	_show_slot_choice("Apply %s to which slot?" % mod_name, tower, candidates,
		func(slot: int) -> void:
			upgrade_chosen.emit({"type": "mod", "mod_data": mod_data, "mod_type": mod_type, "target_slot": slot})
	)

## スロット選択（サポートリンク先 / Mod適用先を選ぶ共通UI）
func _show_slot_choice(prompt: String, tower: Node2D, slots: Array[int], callback: Callable) -> void:
	_clear_buttons()
	title_label.text = prompt

	for slot_idx in slots:
		var module: Variant = tower.get_module(slot_idx)
		if module == null:
			continue
		var stats: Dictionary = build_system.calculate_module_stats(module)
		var skill_name: String = stats.get("name", "?")

		# 現在のリンク状況を表示
		var link_info := ""
		if not module.support_ids.is_empty():
			var sup_names: PackedStringArray = []
			for sup_id in module.support_ids:
				var sup_data: Dictionary = build_system.supports.get(sup_id, {})
				sup_names.append(sup_data.get("name", sup_id))
			link_info = " + " + " + ".join(sup_names)

		var mod_info := ""
		if not module.prefix.is_empty():
			mod_info += module.prefix.get("name", "")
		if not module.suffix.is_empty():
			if mod_info != "":
				mod_info += " "
			mod_info += module.suffix.get("name", "")
		if mod_info != "":
			link_info += " [%s]" % mod_info

		var btn := Button.new()
		btn.text = "Slot %d: %s%s" % [(slot_idx + 1), skill_name, link_info]
		btn.custom_minimum_size = Vector2(400, 50)
		btn.add_theme_font_size_override("font_size", 14)

		var tags: Array = stats.get("tags", [])
		var style := _make_button_style(tags)
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

		btn.pressed.connect(func() -> void:
			get_tree().paused = false
			hide_ui()
			callback.call(slot_idx)
		)
		buttons_container.add_child(btn)

# --- プリセット選択（ゲーム開始時の1画面）---

func show_preset_choice(presets_list: Array[Dictionary]) -> void:
	_clear_buttons()
	title_label.text = "Choose Your Playstyle"

	for preset in presets_list:
		var btn := Button.new()
		btn.text = "%s\n%s" % [
			preset.get("name", "?"),
			preset.get("description", ""),
		]
		btn.custom_minimum_size = Vector2(400, 70)
		btn.add_theme_font_size_override("font_size", 14)

		var style := _make_preset_style(preset.get("id", ""))
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

		var preset_id: String = preset.get("id", "")
		btn.pressed.connect(_on_preset_chosen.bind(preset_id))
		buttons_container.add_child(btn)

	visible = true
	get_tree().paused = true

func _on_preset_chosen(preset_id: String) -> void:
	get_tree().paused = false
	hide_ui()
	upgrade_chosen.emit({"type": "preset", "preset_id": preset_id})

# --- Behavior Chip選択 ---

func show_chip_choice(category_label: String, chip_options: Array[Dictionary]) -> void:
	_clear_buttons()
	title_label.text = "Choose %s" % category_label

	for chip in chip_options:
		var btn := Button.new()
		var rarity: String = chip.get("rarity", "common")
		btn.text = "%s [%s]\n%s" % [
			chip.get("name", "?"),
			rarity.to_upper(),
			chip.get("description", ""),
		]
		btn.custom_minimum_size = Vector2(400, 60)
		btn.add_theme_font_size_override("font_size", 13)

		var style := _make_chip_style(rarity)
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

		var chip_id: String = chip.get("id", "")
		btn.pressed.connect(_on_chip_chosen.bind(chip_id))
		buttons_container.add_child(btn)

	visible = true
	get_tree().paused = true

func _on_chip_chosen(chip_id: String) -> void:
	get_tree().paused = false
	hide_ui()
	upgrade_chosen.emit({"type": "chip", "chip_id": chip_id})

func hide_ui() -> void:
	visible = false

# --- スタイルヘルパー ---

func _make_button_style(tags: Array) -> StyleBoxFlat:
	var color := Color(0.15, 0.12, 0.25, 0.9)
	if "fire" in tags:
		color = Color(0.3, 0.1, 0.05, 0.9)
	elif "cold" in tags:
		color = Color(0.05, 0.15, 0.3, 0.9)
	elif "lightning" in tags:
		color = Color(0.25, 0.25, 0.05, 0.9)
	elif "chaos" in tags:
		color = Color(0.1, 0.25, 0.05, 0.9)
	elif "holy" in tags:
		color = Color(0.25, 0.22, 0.1, 0.9)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style

func _make_support_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.18, 0.12, 0.9)
	style.border_color = Color(0.3, 0.6, 0.3, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style

func _make_mod_style(mod_type: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if mod_type == "prefix":
		style.bg_color = Color(0.2, 0.12, 0.08, 0.9)
		style.border_color = Color(0.6, 0.35, 0.2, 0.8)
	else:
		style.bg_color = Color(0.08, 0.12, 0.2, 0.9)
		style.border_color = Color(0.2, 0.35, 0.6, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style

func _make_preset_style(preset_id: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match preset_id:
		"balanced":
			style.bg_color = Color(0.1, 0.12, 0.2, 0.9)
			style.border_color = Color(0.4, 0.5, 0.7, 0.8)
		"glass_cannon":
			style.bg_color = Color(0.25, 0.08, 0.08, 0.9)
			style.border_color = Color(0.8, 0.3, 0.2, 0.8)
		"chain_master":
			style.bg_color = Color(0.08, 0.18, 0.22, 0.9)
			style.border_color = Color(0.3, 0.7, 0.8, 0.8)
		_:
			style.bg_color = Color(0.15, 0.12, 0.2, 0.9)
			style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	return style

func _make_chip_style(rarity: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match rarity:
		"common":
			style.bg_color = Color(0.12, 0.15, 0.2, 0.9)
			style.border_color = Color(0.4, 0.5, 0.6, 0.8)
		"uncommon":
			style.bg_color = Color(0.08, 0.2, 0.12, 0.9)
			style.border_color = Color(0.3, 0.7, 0.4, 0.8)
		"rare":
			style.bg_color = Color(0.2, 0.12, 0.25, 0.9)
			style.border_color = Color(0.6, 0.3, 0.8, 0.8)
		_:
			style.bg_color = Color(0.15, 0.12, 0.2, 0.9)
			style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style
