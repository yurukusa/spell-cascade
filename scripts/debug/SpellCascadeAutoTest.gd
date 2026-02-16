extends Node
## Spell Cascade自動テスト
## godot-testから読み込まれ、AutoPlayer.gdの代わりに使用する。
## タイトル画面通過→ゲームプレイ→テレメトリ検証→スクショ→結果出力の一連のフロー。

const OUTPUT_DIR = "/tmp/godot_auto_test/"
const SCREENSHOT_INTERVAL = 10.0
const GAME_DURATION = 60.0  # テスト時間（秒）

# テスト結果
var results := {
	"pass": true,
	"checks": {},
	"screenshots": [],
	"telemetry": {
		"skills_fired": {},
		"total_fires": 0,
		"level_ups": 0,
		"enemies_killed": 0,
	},
	"errors": [],
}

var test_start_time := 0.0
var screenshot_timer := 0.0
var screenshots_taken := 0
var in_game := false
var pressed_start := false
var upgrade_auto_pick_timer := 0.0
var log_lines: PackedStringArray = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_clear_output_dir()
	print("[AutoTest] Spell Cascade自動テスト開始")
	print("[AutoTest] Duration: %.0fs" % GAME_DURATION)
	# タイトル画面を通過するため少し待つ
	await get_tree().create_timer(1.0).timeout
	_press_start()

func _clear_output_dir() -> void:
	var dir = DirAccess.open(OUTPUT_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

func _press_start() -> void:
	# Enterキーでゲーム開始
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	event.physical_keycode = KEY_ENTER
	Input.parse_input_event(event)
	pressed_start = true
	print("[AutoTest] Start pressed")
	await get_tree().create_timer(0.1).timeout
	event.pressed = false
	Input.parse_input_event(event)

func _process(delta: float) -> void:
	if not pressed_start:
		return

	# ゲーム画面に遷移したか検出
	if not in_game:
		var tower = get_tree().current_scene.get_node_or_null("Tower")
		if tower:
			in_game = true
			test_start_time = Time.get_ticks_msec() / 1000.0
			print("[AutoTest] Game started - Tower detected")
			_take_screenshot("game_start")
		return

	var elapsed := Time.get_ticks_msec() / 1000.0 - test_start_time

	# 定期スクショ
	screenshot_timer += delta
	if screenshot_timer >= SCREENSHOT_INTERVAL:
		screenshot_timer = 0.0
		_take_screenshot("gameplay_%.0fs" % elapsed)

	# アップグレード画面の自動選択（ゲームがpause中なら）
	if get_tree().paused:
		upgrade_auto_pick_timer += delta
		if upgrade_auto_pick_timer > 0.5:
			_auto_pick_upgrade()
			upgrade_auto_pick_timer = 0.0
	else:
		upgrade_auto_pick_timer = 0.0

	# テレメトリ収集（towerのfire_count等を読む）
	_collect_telemetry()

	# 終了判定
	if elapsed >= GAME_DURATION:
		_finish_test()

func _auto_pick_upgrade() -> void:
	# アップグレードUI上の最初のボタンを自動クリック
	var upgrade_ui = get_tree().current_scene.get_node_or_null("UpgradeUI")
	if upgrade_ui == null:
		# BuildUpgradeUI を探す
		for child in get_tree().current_scene.get_children():
			if child.has_method("hide_ui"):
				upgrade_ui = child
				break
	if upgrade_ui and upgrade_ui.visible:
		# ボタンコンテナからの最初のボタンを探す
		var buttons := upgrade_ui.get_node_or_null("Panel/VBox/Buttons")
		if buttons == null:
			# 名前が違う場合、再帰的にButtonを探す
			buttons = _find_first_button_container(upgrade_ui)
		if buttons:
			for child in buttons.get_children():
				if child is Button:
					child.emit_signal("pressed")
					print("[AutoTest] Auto-picked upgrade: %s" % child.text.get_slice("\n", 0))
					results.telemetry.level_ups += 1
					return
		# ボタンコンテナが見つからない場合、直接Buttonを探す
		var btn := _find_first_button(upgrade_ui)
		if btn:
			btn.emit_signal("pressed")
			print("[AutoTest] Auto-picked upgrade (fallback): %s" % btn.text.get_slice("\n", 0))
			results.telemetry.level_ups += 1

func _find_first_button_container(node: Node) -> Node:
	for child in node.get_children():
		if child.get_child_count() > 0:
			for grandchild in child.get_children():
				if grandchild is Button:
					return child
		var found := _find_first_button_container(child)
		if found:
			return found
	return null

func _find_first_button(node: Node) -> Button:
	if node is Button:
		return node
	for child in node.get_children():
		var found := _find_first_button(child)
		if found:
			return found
	return null

func _collect_telemetry() -> void:
	var tower = get_tree().current_scene.get_node_or_null("Tower")
	if not tower:
		return

	# TowerAttackノードからfire_countを収集
	for child in tower.get_children():
		if child.is_in_group("tower_attacks") and "fire_count" in child:
			var skill_name: String = child.stats.get("name", "slot_%d" % child.slot_index)
			results.telemetry.skills_fired[skill_name] = child.fire_count
			results.telemetry.total_fires = maxi(results.telemetry.total_fires, child.fire_count)

	# 敵の数を追跡
	var enemies := get_tree().get_nodes_in_group("enemies")
	# projectile_bonus も記録
	if "projectile_bonus" in tower:
		results.telemetry["projectile_bonus"] = tower.projectile_bonus
	if "level" in tower:
		results.telemetry["player_level"] = tower.level

func _take_screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var viewport := get_viewport()
	var image := viewport.get_texture().get_image()
	var filename := "sc_%s_%03d.png" % [label, screenshots_taken]
	var full_path := OUTPUT_DIR + filename
	var error := image.save_png(full_path)
	if error == OK:
		screenshots_taken += 1
		results.screenshots.append(full_path)
		# 最新をコピー
		image.save_png("/tmp/godot_latest_autotest.png")
		print("[AutoTest] Screenshot: %s" % filename)

func _finish_test() -> void:
	print("[AutoTest] === TEST RESULTS ===")

	# チェック1: スキルが発射されたか
	var any_fired := results.telemetry.total_fires > 0
	results.checks["skills_fired"] = any_fired
	if not any_fired:
		results.pass = false
		results.errors.append("No skills fired during test")
	print("[AutoTest] Skills fired: %s (total: %d)" % [str(any_fired), results.telemetry.total_fires])

	# チェック2: 個別スキル発射状況
	for skill_name in results.telemetry.skills_fired:
		var count: int = results.telemetry.skills_fired[skill_name]
		print("[AutoTest]   %s: %d fires" % [skill_name, count])

	# チェック3: レベルアップが発生したか
	var leveled := results.telemetry.level_ups > 0
	results.checks["level_ups_occurred"] = leveled
	print("[AutoTest] Level ups: %d" % results.telemetry.level_ups)

	# チェック4: プレイヤーレベル
	var player_level: int = results.telemetry.get("player_level", 1)
	results.checks["player_level"] = player_level
	print("[AutoTest] Player level: %d" % player_level)

	# チェック5: Projectile bonus
	var proj_bonus: int = results.telemetry.get("projectile_bonus", 0)
	results.checks["projectile_bonus"] = proj_bonus
	print("[AutoTest] Projectile bonus: %d" % proj_bonus)

	# 全体判定
	print("[AutoTest] PASS: %s" % str(results.pass))
	print("[AutoTest] Screenshots: %d" % screenshots_taken)
	print("[AutoTest] === END RESULTS ===")

	# JSON保存
	var result_file = FileAccess.open(OUTPUT_DIR + "results.json", FileAccess.WRITE)
	if result_file:
		result_file.store_string(JSON.stringify(results, "\t"))
		result_file.close()

	# 自動終了
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
