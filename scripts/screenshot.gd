extends Node

## デバッグ用スクリーンショット。
## 起動→初回スキルを自動選択→数秒待機→スクショ→終了。

var timer := 0.0
var phase := 0  # 0=wait_for_ui, 1=gameplay, 2=done

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	timer += delta

	if phase == 0 and timer >= 0.5:
		# 初回スキル選択UIのボタンを自動クリック
		_auto_select_first_button()
		phase = 1
		timer = 0.0

	elif phase == 1 and timer >= 12.0:
		# 12秒後にスクショ（敵がレンジ内に到達する時間）
		phase = 2
		_take_screenshot()

func _auto_select_first_button() -> void:
	var upgrade_ui := get_tree().current_scene.get_node_or_null("UpgradeUI")
	if upgrade_ui == null:
		# UpgradeUIが見つからない場合、pauseを解除
		get_tree().paused = false
		return
	# ボタンコンテナ内の最初のボタンを押す
	for child in upgrade_ui.get_children():
		if child is Control:
			for sub in child.get_children():
				if sub is PanelContainer:
					_find_and_press_button(sub)
					return
	# フォールバック: 直接全子ノードからButtonを探す
	_find_and_press_button(upgrade_ui)

func _find_and_press_button(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.pressed.emit()
			return
		_find_and_press_button(child)

func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "/home/namakusa/screenshots/spell-cascade-v6-player-avatar.png"
	var err := img.save_png(path)
	if err == OK:
		print("SCREENSHOT_SAVED: %s" % path)
	else:
		print("SCREENSHOT_FAILED: error code ", err)
	get_tree().quit()
