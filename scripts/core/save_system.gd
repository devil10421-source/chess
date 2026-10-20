class_name SaveSystem
extends RefCounted
## 存檔位置：user://save_v1.json
## Windows：%APPDATA%\Godot\app_userdata\六族遠征\save_v1.json（Android/iOS 為 App 私有資料夾）

const SAVE_PATH := "user://save_v1.json"

static var path_override := ""   # 測試用


static func _path() -> String:
	return path_override if path_override != "" else SAVE_PATH


static func has_save() -> bool:
	return FileAccess.file_exists(_path()) and load_run() != null


static func save_run(run: RunState) -> bool:
	if run == null:
		return false
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		push_error("無法寫入存檔：%s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(run.to_dict(), "\t"))
	f.close()
	return true


static func load_run() -> RunState:
	if not FileAccess.file_exists(_path()):
		return null
	var text := FileAccess.get_file_as_string(_path())
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var run := RunState.from_dict(data)
	if run == null or run.finished:
		return null
	return run


static func clear() -> void:
	if FileAccess.file_exists(_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path()))
