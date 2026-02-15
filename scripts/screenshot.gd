extends Node

## テストプレイ観察モード（Mirror War対応）。
## 自動でW押下をシミュレートし、縦スクロールを進行させる。
## 複数タイミングでスクショを撮り、ゲーム進行を記録。

var timer := 0.0
var phase := 0  # 0=init, 1=gameplay
var screenshot_times: Array[float] = [3.0, 10.0, 20.0, 35.0, 60.0, 90.0]
var screenshot_index := 0
var gameplay_timer := 0.0
var auto_dismiss_interval := 0.5
var auto_dismiss_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	timer += delta

	if phase == 0 and timer >= 0.3:
		phase = 1
		gameplay_timer = 0.0

	elif phase == 1:
		gameplay_timer += delta

		# 自動で上移動をシミュレート（テスト用）
		_simulate_move_up()

		# 定期的にアップグレードUIを自動処理
		auto_dismiss_timer += delta
		if auto_dismiss_timer >= auto_dismiss_interval:
			auto_dismiss_timer = 0.0
			if get_tree().paused:
				_auto_select_first_button()

		if screenshot_index < screenshot_times.size():
			if gameplay_timer >= screenshot_times[screenshot_index]:
				_take_screenshot(screenshot_index)
				screenshot_index += 1
				if screenshot_index >= screenshot_times.size():
					await get_tree().create_timer(0.1).timeout
					get_tree().quit()

func _simulate_move_up() -> void:
	# テスト用: タワーを直接上に移動させる（WASDシミュレート）
	var tower := get_tree().current_scene.get_node_or_null("Tower")
	if tower and is_instance_valid(tower):
		tower.position.y -= 200.0 * get_process_delta_time()  # 200px/s上昇
		tower.distance_traveled = maxf(tower.start_y - tower.position.y, tower.distance_traveled)

func _auto_select_first_button() -> void:
	var upgrade_ui := get_tree().current_scene.get_node_or_null("UpgradeUI")
	if upgrade_ui == null:
		get_tree().paused = false
		return
	_find_and_press_button(upgrade_ui)

func _find_and_press_button(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.pressed.emit()
			return
		_find_and_press_button(child)

func _take_screenshot(idx: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "/home/namakusa/screenshots/spell-cascade-test-%02d-t%ds.png" % [idx, int(gameplay_timer)]
	var err := img.save_png(path)
	if err == OK:
		print("SCREENSHOT_%d_SAVED: %s (gameplay: %.1fs)" % [idx, path, gameplay_timer])
	else:
		print("SCREENSHOT_%d_FAILED: error code %d" % [idx, err])
