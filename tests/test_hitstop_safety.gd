extends SceneTree

## Hitstop time_scale 安全性テスト（単体テスト版）
## game_main.gdのautoload依存を回避し、hitstopロジックのみを検証
## Usage: godot --headless --script tests/test_hitstop_safety.gd

var _pass := 0
var _fail := 0

# _do_hitstop と同一アルゴリズムをテスト用に再現
var _hitstop_depth := 0

func do_hitstop(duration: float) -> void:
	_hitstop_depth += 1
	Engine.time_scale = 0.05
	create_timer(duration, true).timeout.connect(func():
		_hitstop_depth -= 1
		if _hitstop_depth <= 0:
			_hitstop_depth = 0
			Engine.time_scale = 1.0
	)

func reset_time_scale() -> void:
	_hitstop_depth = 0
	Engine.time_scale = 1.0

func exit_tree_sim() -> void:
	Engine.time_scale = 1.0
	_hitstop_depth = 0

func _init() -> void:
	print("=== Hitstop Safety Test ===\n")

	# フレーム初期化待ち
	await process_frame

	# --- Case 1: 被弾+LvUp同時（連続hitstop呼び出し） ---
	print("Case 1: Concurrent hitstop (damage + level-up)")
	do_hitstop(0.15)
	do_hitstop(0.5)
	_assert_eq(_hitstop_depth, 2, "depth=2 after 2 calls")
	_assert_eq(Engine.time_scale, 0.05, "frozen at 0.05")

	# 短い方(0.15s)のタイマー完了を待つ
	await create_timer(0.25, true).timeout
	_assert_eq(_hitstop_depth, 1, "depth=1 after first expires")
	_assert_eq(Engine.time_scale, 0.05, "still frozen (one active)")

	# 長い方(0.5s)のタイマー完了を待つ
	await create_timer(0.4, true).timeout
	_assert_eq(_hitstop_depth, 0, "depth=0 after all expire")
	_assert_eq(Engine.time_scale, 1.0, "restored to 1.0")
	print("")

	# --- Case 2: hitstop中にgame over (_reset_time_scale) ---
	print("Case 2: Game over during hitstop")
	Engine.time_scale = 1.0
	_hitstop_depth = 0
	do_hitstop(0.5)
	_assert_eq(Engine.time_scale, 0.05, "frozen at 0.05")
	reset_time_scale()
	_assert_eq(Engine.time_scale, 1.0, "restored by reset_time_scale")
	_assert_eq(_hitstop_depth, 0, "depth=0 after reset")
	# 残タイマーが発火しても問題ないことを確認
	await create_timer(0.6, true).timeout
	_assert_eq(Engine.time_scale, 1.0, "still 1.0 after orphan timer fires")
	print("")

	# --- Case 3: hitstop中にscene遷移 (_exit_tree) ---
	print("Case 3: Scene transition during hitstop")
	Engine.time_scale = 1.0
	_hitstop_depth = 0
	do_hitstop(0.5)
	do_hitstop(0.3)
	_assert_eq(_hitstop_depth, 2, "depth=2")
	_assert_eq(Engine.time_scale, 0.05, "frozen at 0.05")
	exit_tree_sim()
	_assert_eq(Engine.time_scale, 1.0, "restored by _exit_tree")
	_assert_eq(_hitstop_depth, 0, "depth=0 after _exit_tree")
	print("")

	# --- Results ---
	print("=== Results: %d PASS / %d FAIL ===" % [_pass, _fail])
	if _fail > 0:
		print("OVERALL: FAIL")
	else:
		print("OVERALL: PASS")

	Engine.time_scale = 1.0
	quit(1 if _fail > 0 else 0)

func _assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual == expected:
		print("  PASS: %s (got %s)" % [msg, str(actual)])
		_pass += 1
	else:
		print("  FAIL: %s (expected %s, got %s)" % [msg, str(expected), str(actual)])
		_fail += 1
