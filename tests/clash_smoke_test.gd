extends Node
## 《氏族爭霸》冒煙測試入口（tests/clash_smoke_test.tscn）：從主選單進入十人對局，實際操作備戰、交易、制度選擇、淘汰與觀戰。


func _ready() -> void:
	var driver := preload("res://tests/clash_smoke_driver.gd").new()
	driver.name = "ClashSmokeDriver"
	get_tree().root.add_child.call_deferred(driver)
