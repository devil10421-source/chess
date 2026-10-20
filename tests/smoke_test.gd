extends Node
## 冒煙測試入口：把測試驅動器掛在 root 下（換場景時不會被釋放），再從主選單開始走流程。


func _ready() -> void:
	var driver := preload("res://tests/smoke_driver.gd").new()
	driver.name = "SmokeDriver"
	get_tree().root.add_child.call_deferred(driver)
