extends Node
## Spell Cascade自動テスト
## godot-testから読み込まれ、AutoPlayer.gdの代わりに使用する。
## タイトル画面通過→ゲームプレイ→テレメトリ検証→スクショ→結果出力の一連のフロー。
## v0.2.4: 品質指標（Difficulty Curve, Reward Timing）の自動出力追加
## v0.3: Feel Scorecard（Dead Time, Action Density, Reward Frequency）追加

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

# 品質指標（トップレベル変数としてドットアクセス問題を回避）
var qm_hp_samples: Array = []            # [{t, hp, hp_pct}] 5秒間隔
var qm_damage_taken_count := 0           # 被ダメ回数
var qm_lowest_hp_pct := 1.0             # 最低HP割合
var qm_enemy_count_samples: Array = []   # [{t, count}] 5秒間隔
var qm_levelup_timestamps: Array = []    # レベルアップ発生時刻（秒）
var qm_upgrade_menu_total_time := 0.0    # メニュー滞在秒数（疲労指標）

# Feel Scorecard（v0.3）
var feel_event_timestamps: Array[float] = []  # 全イベントのタイムスタンプ
var feel_kill_count := 0                      # キル数（action density計算用）
var feel_xp_pickup_count := 0                 # XP回収数（reward frequency計算用）
var _last_kill_count := 0                     # 前フレームのkill_count
var _last_xp := 0                            # 前フレームのXP（回収検出用）

var test_start_time := 0.0
var screenshot_timer := 0.0
var screenshots_taken := 0
var in_game := false
var pressed_start := false
var upgrade_auto_pick_timer := 0.0
var log_lines: PackedStringArray = []
var test_finished := false

# 品質指標トラッキング用
var _metric_sample_timer := 0.0
const METRIC_SAMPLE_INTERVAL := 5.0
var _last_hp := -1.0  # 前フレームHP（被ダメ検出用）
var _upgrade_menu_start := 0.0
var _in_upgrade_menu := false

func _ready() -> void:
	# ポーズ中もprocessを継続（アップグレード自動選択のため）
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		var scene = get_tree().current_scene
		if scene == null:
			return
		var tower = scene.get_node_or_null("Tower")
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
		if not _in_upgrade_menu:
			_in_upgrade_menu = true
			_upgrade_menu_start = Time.get_ticks_msec() / 1000.0
		upgrade_auto_pick_timer += delta
		if upgrade_auto_pick_timer > 0.5:
			_auto_pick_upgrade()
			upgrade_auto_pick_timer = 0.0
	else:
		if _in_upgrade_menu:
			_in_upgrade_menu = false
			var menu_dur: float = Time.get_ticks_msec() / 1000.0 - _upgrade_menu_start
			qm_upgrade_menu_total_time += menu_dur
		upgrade_auto_pick_timer = 0.0

	# 品質指標サンプリング
	_collect_quality_metrics(elapsed, delta)

	# テレメトリ収集（towerのfire_count等を読む）
	_collect_telemetry()

	# 終了判定
	if elapsed >= GAME_DURATION and not test_finished:
		test_finished = true
		_finish_test()

func _collect_quality_metrics(elapsed: float, delta: float) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var tower = scene.get_node_or_null("Tower")
	if not tower:
		return

	# HP追跡: 被ダメ検出
	if "hp" in tower and "max_hp" in tower:
		var cur_hp: float = tower.hp
		var max_hp_val: float = tower.max_hp
		if _last_hp >= 0.0 and cur_hp < _last_hp:
			qm_damage_taken_count += 1
			feel_event_timestamps.append(elapsed)  # 被ダメもイベント
		_last_hp = cur_hp
		var hp_pct: float = cur_hp / maxf(max_hp_val, 1.0)
		if hp_pct < qm_lowest_hp_pct:
			qm_lowest_hp_pct = hp_pct

	# Feel Scorecard: キル数/XP回収追跡
	var game_main = scene
	if "kill_count" in game_main:
		var cur_kills: int = game_main.kill_count
		if cur_kills > _last_kill_count:
			var new_kills := cur_kills - _last_kill_count
			feel_kill_count += new_kills
			for _k in range(new_kills):
				feel_event_timestamps.append(elapsed)
			_last_kill_count = cur_kills
	if "xp" in tower:
		var cur_xp: int = tower.xp
		if cur_xp > _last_xp and _last_xp >= 0:
			feel_xp_pickup_count += 1
			feel_event_timestamps.append(elapsed)
		_last_xp = cur_xp

	# 定期サンプリング（5秒間隔）
	_metric_sample_timer += delta
	if _metric_sample_timer >= METRIC_SAMPLE_INTERVAL:
		_metric_sample_timer = 0.0
		# HPサンプル
		if "hp" in tower and "max_hp" in tower:
			qm_hp_samples.append({
				"t": snappedf(elapsed, 0.1),
				"hp": tower.hp,
				"hp_pct": snappedf(tower.hp / maxf(tower.max_hp, 1.0), 0.01),
			})
		# 敵数サンプル
		var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
		qm_enemy_count_samples.append({
			"t": snappedf(elapsed, 0.1),
			"count": enemy_count,
		})

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
					_record_levelup_timestamp()
					return
		# ボタンコンテナが見つからない場合、直接Buttonを探す
		var btn := _find_first_button(upgrade_ui)
		if btn:
			btn.emit_signal("pressed")
			print("[AutoTest] Auto-picked upgrade (fallback): %s" % btn.text.get_slice("\n", 0))
			results.telemetry.level_ups += 1
			_record_levelup_timestamp()

func _record_levelup_timestamp() -> void:
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - test_start_time
	qm_levelup_timestamps.append(snappedf(elapsed, 0.1))

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
	var scene = get_tree().current_scene
	if scene == null:
		return
	var tower = scene.get_node_or_null("Tower")
	if not tower:
		return

	# TowerAttackノードからfire_countを収集
	for child in tower.get_children():
		if child.is_in_group("tower_attacks") and "fire_count" in child:
			var skill_name: String = child.stats.get("name", "slot_%d" % child.slot_index)
			results.telemetry.skills_fired[skill_name] = child.fire_count
			results.telemetry.total_fires = maxi(results.telemetry.total_fires, child.fire_count)

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
	var any_fired: bool = results.telemetry.total_fires > 0
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
	var leveled: bool = results.telemetry.level_ups > 0
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

	# --- 品質指標サマリー ---
	print("[AutoTest] === QUALITY METRICS ===")

	# Difficulty Curve
	print("[AutoTest] Damage taken: %d times" % qm_damage_taken_count)
	print("[AutoTest] Lowest HP: %.0f%%" % (qm_lowest_hp_pct * 100.0))
	# 難易度判定: 被ダメ0回 = too easy, 1-3回 = OK, 4+ = challenging
	var diff_rating := "TOO_EASY"
	if qm_damage_taken_count >= 4:
		diff_rating = "CHALLENGING"
	elif qm_damage_taken_count >= 1:
		diff_rating = "OK"
	print("[AutoTest] Difficulty: %s" % diff_rating)

	# HP推移
	for sample in qm_hp_samples:
		print("[AutoTest]   HP@%.0fs: %.0f%%" % [sample.t, sample.hp_pct * 100.0])

	# 敵密度推移
	for sample in qm_enemy_count_samples:
		print("[AutoTest]   Enemies@%.0fs: %d" % [sample.t, sample.count])

	# Reward Timing / Upgrade Fatigue
	var avg_interval := 0.0
	if qm_levelup_timestamps.size() >= 2:
		var total_interval := 0.0
		for idx in range(1, qm_levelup_timestamps.size()):
			total_interval += qm_levelup_timestamps[idx] - qm_levelup_timestamps[idx - 1]
		avg_interval = snappedf(total_interval / (qm_levelup_timestamps.size() - 1), 0.1)
	print("[AutoTest] Avg levelup interval: %.1fs (target: ~23s)" % avg_interval)
	print("[AutoTest] Upgrade menu total time: %.1fs" % qm_upgrade_menu_total_time)
	# 疲労判定: 平均間隔<10sは過頻度
	var fatigue_rating := "OK"
	if avg_interval > 0.0 and avg_interval < 10.0:
		fatigue_rating = "TOO_FREQUENT"
	elif avg_interval > 30.0:
		fatigue_rating = "TOO_SLOW"
	print("[AutoTest] Upgrade fatigue: %s" % fatigue_rating)

	print("[AutoTest] === END QUALITY METRICS ===")

	# --- Feel Scorecard ---
	print("[AutoTest] === FEEL SCORECARD ===")

	# Dead Time: max gap between events
	feel_event_timestamps.sort()
	var dead_time := 0.0
	if feel_event_timestamps.size() >= 2:
		for idx in range(1, feel_event_timestamps.size()):
			var gap: float = feel_event_timestamps[idx] - feel_event_timestamps[idx - 1]
			dead_time = maxf(dead_time, gap)
	var dead_time_rating := "EXCELLENT"
	if dead_time > 10.0:
		dead_time_rating = "FAIL"
	elif dead_time > 5.0:
		dead_time_rating = "WARN"
	elif dead_time > 3.0:
		dead_time_rating = "GOOD"
	print("[AutoTest] Dead Time: %.1fs (%s)" % [dead_time, dead_time_rating])

	# Action Density: events per second
	var total_events: int = results.telemetry.total_fires + feel_kill_count + feel_xp_pickup_count + results.telemetry.level_ups
	var action_density: float = float(total_events) / maxf(GAME_DURATION, 1.0)
	var density_rating := "GOOD"
	if action_density < 1.0:
		density_rating = "BORING"
	elif action_density > 15.0:
		density_rating = "CHAOTIC"
	elif action_density > 8.0:
		density_rating = "INTENSE"
	print("[AutoTest] Action Density: %.1f events/s (%s) [fires=%d kills=%d pickups=%d levelups=%d]" % [
		action_density, density_rating,
		results.telemetry.total_fires, feel_kill_count,
		feel_xp_pickup_count, results.telemetry.level_ups,
	])

	# Reward Frequency: XP pickups per minute
	var reward_freq: float = float(feel_xp_pickup_count) / maxf(GAME_DURATION / 60.0, 0.01)
	var reward_rating := "GOOD"
	if reward_freq < 10.0:
		reward_rating = "SPARSE"
	elif reward_freq > 100.0:
		reward_rating = "OVERWHELMING"
	elif reward_freq > 60.0:
		reward_rating = "ABUNDANT"
	print("[AutoTest] Reward Frequency: %.0f pickups/min (%s)" % [reward_freq, reward_rating])

	# Run Completion Desire (THE ONE feel heuristic)
	# なぜ: 「もう1回遊びたいか」の代理指標。ランの終わり方がリテンションを予測する
	# HP 30-70%で生存終了 = 理想。100%=ぬるい、0%=死亡（到達時間で評価）
	var final_hp_pct := 1.0
	if not qm_hp_samples.is_empty():
		final_hp_pct = qm_hp_samples[-1].hp_pct
	var survived := final_hp_pct > 0.0
	var desire_score := 0.0
	if survived:
		desire_score = 1.0 - absf(final_hp_pct - 0.50) * 1.5
		desire_score = clampf(desire_score, 0.0, 1.0)
	else:
		# 死亡: ランの進行度で評価（後半の死亡は前半より評価高い）
		var run_time_elapsed: float = GAME_DURATION
		if not qm_hp_samples.is_empty():
			run_time_elapsed = qm_hp_samples[-1].t
		var run_completion: float = run_time_elapsed / GAME_DURATION
		var fought_hard: float = 1.0 if qm_damage_taken_count >= 3 else 0.5
		desire_score = run_completion * 0.7 * fought_hard
	var desire_rating := "FAIL"
	if desire_score >= 0.8:
		desire_rating = "EXCELLENT"
	elif desire_score >= 0.6:
		desire_rating = "GOOD"
	elif desire_score >= 0.4:
		desire_rating = "WARN"
	print("[AutoTest] Run Completion Desire: %.2f (%s) [hp=%.0f%% survived=%s]" % [
		desire_score, desire_rating, final_hp_pct * 100.0, str(survived)
	])

	print("[AutoTest] === END FEEL SCORECARD ===")

	# 品質指標をresultsに統合（JSON出力用）
	results["quality_metrics"] = {
		"hp_samples": qm_hp_samples,
		"damage_taken_count": qm_damage_taken_count,
		"lowest_hp_pct": qm_lowest_hp_pct,
		"enemy_count_samples": qm_enemy_count_samples,
		"levelup_timestamps": qm_levelup_timestamps,
		"avg_levelup_interval": avg_interval,
		"upgrade_menu_total_time": qm_upgrade_menu_total_time,
		"difficulty_rating": diff_rating,
		"fatigue_rating": fatigue_rating,
	}

	# Feel Scorecard をresultsに追加
	results["feel_scorecard"] = {
		"dead_time": snappedf(dead_time, 0.1),
		"dead_time_rating": dead_time_rating,
		"action_density": snappedf(action_density, 0.1),
		"action_density_rating": density_rating,
		"reward_frequency": snappedf(reward_freq, 0.1),
		"reward_frequency_rating": reward_rating,
		"total_events": total_events,
		"kill_count": feel_kill_count,
		"xp_pickup_count": feel_xp_pickup_count,
		"event_count": feel_event_timestamps.size(),
		"run_desire": snappedf(desire_score, 0.01),
		"run_desire_rating": desire_rating,
		"run_survived": survived,
		"final_hp_pct": snappedf(final_hp_pct, 0.01),
	}

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
