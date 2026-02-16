extends Node
## 自動プレイヤースクリプト
## Claude Codeがゲームを自律的にテストするための自動操作
##
## 設計思想:
##   - ユーザー操作なしでゲームを自動プレイ
##   - 様々なシナリオを実行してスクリーンショット取得
##   - Claude Codeが分析→修正→再テストのループを回せる
##
## 使い方:
##   1. このスクリプトをAutoLoadに追加
##   2. godot --path . で起動すると自動プレイ開始
##   3. /tmp/godot_auto_test/ に結果が出力される

const OUTPUT_DIR = "/tmp/godot_auto_test/"
const SCREENSHOT_INTERVAL = 1.0  # スクリーンショット間隔（秒）

# テストシナリオの定義
# 各シナリオは「名前」と「アクションリスト」で構成
var test_scenarios := [
	{
		"name": "idle",
		"description": "何もしない状態を観察",
		"duration": 3.0,
		"actions": []
	},
	{
		"name": "move_around",
		"description": "移動テスト",
		"duration": 5.0,
		"actions": [
			{"type": "key_hold", "key": "ui_right", "duration": 1.0},
			{"type": "key_hold", "key": "ui_left", "duration": 1.0},
			{"type": "key_hold", "key": "ui_up", "duration": 1.0},
			{"type": "key_hold", "key": "ui_down", "duration": 1.0},
		]
	},
	{
		"name": "interaction",
		"description": "インタラクションテスト",
		"duration": 3.0,
		"actions": [
			{"type": "key_press", "key": "ui_accept"},
			{"type": "wait", "duration": 0.5},
			{"type": "key_press", "key": "ui_cancel"},
		]
	},
	{
		"name": "rapid_input",
		"description": "高速入力テスト（バグ検出用）",
		"duration": 2.0,
		"actions": [
			{"type": "key_press", "key": "ui_accept"},
			{"type": "key_press", "key": "ui_right"},
			{"type": "key_press", "key": "ui_accept"},
			{"type": "key_press", "key": "ui_left"},
		]
	},
]

# 状態
var current_scenario_index := 0
var scenario_start_time := 0.0
var action_index := 0
var action_start_time := 0.0
var is_running := false
var screenshots_taken := 0
var screenshot_timer := 0.0
var test_results := []
var held_keys := {}

# シグナル
signal scenario_started(scenario_name: String)
signal scenario_completed(scenario_name: String)
signal all_tests_completed(results: Array)
signal screenshot_taken(path: String)

func _ready() -> void:
	# 出力ディレクトリ作成
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	# 古いファイルをクリア
	_clear_output_dir()

	print("[AutoPlayer] Ready. Starting automated test in 2 seconds...")

	# 少し待ってから開始（ゲームの初期化を待つ）
	await get_tree().create_timer(2.0).timeout
	start_tests()

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

func start_tests() -> void:
	## テスト開始
	print("[AutoPlayer] Starting automated tests...")
	current_scenario_index = 0
	is_running = true
	_start_scenario()

func stop_tests() -> void:
	## テスト停止
	is_running = false
	_release_all_keys()
	print("[AutoPlayer] Tests stopped.")

func _start_scenario() -> void:
	## 現在のシナリオを開始
	if current_scenario_index >= test_scenarios.size():
		_complete_all_tests()
		return

	var scenario = test_scenarios[current_scenario_index]
	print("[AutoPlayer] Starting scenario: %s" % scenario.name)

	scenario_start_time = Time.get_unix_time_from_system()
	action_index = 0
	action_start_time = scenario_start_time
	screenshot_timer = 0.0

	# 開始時スクリーンショット
	await _take_screenshot(scenario.name, "start")

	scenario_started.emit(scenario.name)

func _process(delta: float) -> void:
	if not is_running:
		return
	# _complete_scenario()のawait中にインデックスが進むためガード
	if current_scenario_index >= test_scenarios.size():
		return

	var scenario = test_scenarios[current_scenario_index]
	var elapsed = Time.get_unix_time_from_system() - scenario_start_time

	# 定期スクリーンショット
	screenshot_timer += delta
	if screenshot_timer >= SCREENSHOT_INTERVAL:
		screenshot_timer = 0.0
		_take_screenshot(scenario.name, "%.1fs" % elapsed)

	# シナリオ終了チェック
	if elapsed >= scenario.duration:
		_complete_scenario()
		return

	# アクション実行
	_process_actions(scenario, delta)

func _process_actions(scenario: Dictionary, delta: float) -> void:
	## アクションを順次実行
	if action_index >= scenario.actions.size():
		return

	var action = scenario.actions[action_index]
	var action_elapsed = Time.get_unix_time_from_system() - action_start_time

	match action.type:
		"key_press":
			_simulate_key_press(action.key)
			action_index += 1
			action_start_time = Time.get_unix_time_from_system()

		"key_hold":
			if action_elapsed == 0.0:
				_simulate_key_down(action.key)
			elif action_elapsed >= action.get("duration", 0.5):
				_simulate_key_up(action.key)
				action_index += 1
				action_start_time = Time.get_unix_time_from_system()

		"wait":
			if action_elapsed >= action.get("duration", 1.0):
				action_index += 1
				action_start_time = Time.get_unix_time_from_system()

		"mouse_click":
			_simulate_mouse_click(action.get("position", Vector2.ZERO))
			action_index += 1
			action_start_time = Time.get_unix_time_from_system()

func _simulate_key_press(action_name: String) -> void:
	## キー押下をシミュレート
	var event_down = InputEventAction.new()
	event_down.action = action_name
	event_down.pressed = true
	Input.parse_input_event(event_down)

	# 少し遅延してリリース
	await get_tree().create_timer(0.05).timeout

	var event_up = InputEventAction.new()
	event_up.action = action_name
	event_up.pressed = false
	Input.parse_input_event(event_up)

func _simulate_key_down(action_name: String) -> void:
	## キー押下開始
	if held_keys.has(action_name):
		return

	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = true
	Input.parse_input_event(event)
	held_keys[action_name] = true

func _simulate_key_up(action_name: String) -> void:
	## キーリリース
	if not held_keys.has(action_name):
		return

	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = false
	Input.parse_input_event(event)
	held_keys.erase(action_name)

func _simulate_mouse_click(position: Vector2) -> void:
	## マウスクリックをシミュレート
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	Input.parse_input_event(event)

	await get_tree().create_timer(0.05).timeout

	event.pressed = false
	Input.parse_input_event(event)

func _release_all_keys() -> void:
	## 全てのキーをリリース
	for action_name in held_keys.keys():
		var event = InputEventAction.new()
		event.action = action_name
		event.pressed = false
		Input.parse_input_event(event)
	held_keys.clear()

func _take_screenshot(scenario_name: String, label: String) -> void:
	## スクリーンショット撮影
	await RenderingServer.frame_post_draw

	var viewport := get_viewport()
	var image := viewport.get_texture().get_image()

	var filename := "%s_%s_%03d.png" % [scenario_name, label, screenshots_taken]
	var full_path := OUTPUT_DIR + filename

	var error := image.save_png(full_path)
	if error == OK:
		screenshots_taken += 1
		screenshot_taken.emit(full_path)

		# 最新をコピー（Claude Codeからアクセスしやすく）
		image.save_png("/tmp/godot_latest_autotest.png")
	else:
		push_error("[AutoPlayer] Failed to save screenshot: %s" % full_path)

func _complete_scenario() -> void:
	## シナリオ完了
	_release_all_keys()

	var scenario = test_scenarios[current_scenario_index]
	print("[AutoPlayer] Completed scenario: %s" % scenario.name)

	# 終了時スクリーンショット
	await _take_screenshot(scenario.name, "end")

	# 結果記録
	test_results.append({
		"scenario": scenario.name,
		"description": scenario.description,
		"screenshots": screenshots_taken,
	})

	scenario_completed.emit(scenario.name)

	# 次のシナリオへ
	current_scenario_index += 1

	# 少し待ってから次を開始
	await get_tree().create_timer(0.5).timeout
	_start_scenario()

func _complete_all_tests() -> void:
	## 全テスト完了
	is_running = false

	print("[AutoPlayer] All tests completed!")
	print("[AutoPlayer] Total screenshots: %d" % screenshots_taken)
	print("[AutoPlayer] Output: %s" % OUTPUT_DIR)

	# 結果をJSONで保存
	var result_file = FileAccess.open(OUTPUT_DIR + "results.json", FileAccess.WRITE)
	if result_file:
		result_file.store_string(JSON.stringify(test_results, "\t"))
		result_file.close()

	all_tests_completed.emit(test_results)

	# 自動終了
	print("[AutoPlayer] Quitting in 1 second...")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

## 外部からシナリオを追加
func add_scenario(scenario: Dictionary) -> void:
	test_scenarios.append(scenario)

## 特定のシナリオのみ実行
func run_scenario(scenario_name: String) -> void:
	for i in range(test_scenarios.size()):
		if test_scenarios[i].name == scenario_name:
			current_scenario_index = i
			is_running = true
			_start_scenario()
			return
	push_error("[AutoPlayer] Scenario not found: %s" % scenario_name)
