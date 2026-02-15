extends Node

## 起動後2秒でスクリーンショットを保存して終了するデバッグ用ノード。
## メインシーンにautoloadとして追加して使う。

var timer := 0.0
var taken := false

func _process(delta: float) -> void:
	timer += delta
	if timer >= 2.0 and not taken:
		taken = true
		_take_screenshot()

func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("/home/namakusa/screenshots/spell-cascade-v0.png")
	if err == OK:
		print("SCREENSHOT_SAVED: /home/namakusa/screenshots/spell-cascade-v0.png")
	else:
		print("SCREENSHOT_FAILED: error code ", err)
	get_tree().quit()
