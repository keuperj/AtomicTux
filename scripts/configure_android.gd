@tool
extends SceneTree


func _initialize() -> void:
	_configure.call_deferred()


func _configure() -> void:
	await process_frame
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var root := ProjectSettings.globalize_path("res://")
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("export/android/java_sdk_path", root.path_join("tools/jdk-17"))
	settings.set_setting("export/android/android_sdk_path", root.path_join("tools/android-sdk"))
	settings.set_setting("export/android/debug_keystore", root.path_join("tools/config/debug.keystore"))
	settings.set_setting("export/android/debug_keystore_user", "androiddebugkey")
	settings.set_setting("export/android/debug_keystore_pass", "android")
	quit()
