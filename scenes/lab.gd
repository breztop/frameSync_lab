# SPDX-License-Identifier: GPL-3.0-only
extends Control

const Recorder = preload("res://scripts/frame_record.gd")
const MODES := ["轻负载", "典型桌面", "高复杂度"]
const LEVELS := ["低", "中", "高"]
const SIZES := [Vector2i(1152, 648), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const MAX_SAMPLES := 2000000

@onready var background := $Background
@onready var clock_label: Label = $Interface/Readout/Time
@onready var frame_label: Label = $Interface/Readout/Frame
@onready var stats_label: Label = $Interface/Readout/Stats
@onready var config_label: Label = $Interface/Readout/Config
@onready var status_label: Label = $Notifications/Toast/Margin/Row/Status
@onready var settings_panel: Control = $Interface/SettingsPanel
@onready var about_panel: Control = $Interface/AboutPanel
var fields: VBoxContainer
@onready var start_button: Button = $Interface/Actions/Start
@onready var stop_button: Button = $Interface/Actions/Stop
@onready var export_button: Button = $Interface/Actions/Export

var record := Recorder.new()
var controls: Dictionary = {}
var export_thread: Thread
var refresh_at := 0
var last_elapsed := 0
var last_number := 0
var initialized := false
var last_export_path := ""
var toast_export_path := ""
var toolbar_visible := true


func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	get_window().min_size = Vector2i(800, 450)
	fields = $Interface/SettingsPanel/Panel/Margin/Content/Tabs/Background/Scroll/Fields
	_option("mode", "背景", MODES, 0)
	_option("level", "复杂度", LEVELS, 0)
	_number("speed", "运动速度", 0.0, 5.0, 0.1, 1.0)
	_number("density", "细节密度", 0.5, 4.0, 0.5, 1.0)
	_number("elements", "动态元素", 0, 4096, 1, 64)
	_number("seed", "固定种子", 0, 2147483647, 1, 20260905)
	fields = $Interface/SettingsPanel/Panel/Margin/Content/Tabs/Display/Scroll/Fields
	_option("size", "窗口客户区", ["1152 × 648", "1920 × 1080", "2560 × 1440"], 0)
	_option("vsync", "VSync", ["开启", "关闭"], 0)
	_number("target", "目标 FPS", 30, 240, 1, 60)
	fields = $Interface/SettingsPanel/Panel/Margin/Content/Tabs/Record/Scroll/Fields
	_number("refresh", "显示器 Hz（填写）", 1, 1000, 1, 60)
	_text("capture", "采集分辨率", "1920x1080")
	_number("bitrate", "编码 kbps", 1, 200000, 1000, 20000)
	_text("sink", "sink 预览尺寸", "1152x648（请核实）")
	_text("machine", "机器 / 显示器", OS.get_processor_name())
	_text("notes", "测试备注", "单独运行 / BreFlow source 请填写")
	start_button.pressed.connect(_new_round)
	stop_button.pressed.connect(_stop_round)
	export_button.pressed.connect(_export_round)
	$Interface/Actions/Settings.pressed.connect(_toggle_settings)
	$Interface/Actions/About.pressed.connect(_toggle_about)
	$Interface/Actions/Logs.pressed.connect(_open_last_export)
	$Interface/Actions/Hide.pressed.connect(_toggle_toolbar)
	$Notifications/Toast/Margin/Row/Open.pressed.connect(_open_toast_export)
	$NotificationTimer.timeout.connect(func(): $Notifications/Toast.hide())
	$Interface/SettingsPanel/Panel/Margin/Content/Header/Close.pressed.connect(_toggle_settings)
	$Interface/SettingsPanel/Panel/Margin/Content/Footer/Folder.pressed.connect(_open_folder)
	$Interface/AboutPanel/Panel/Margin/Content/Header/Close.pressed.connect(_toggle_about)
	var tabs: TabContainer = $Interface/SettingsPanel/Panel/Margin/Content/Tabs
	tabs.set_tab_title(0, "画面与运动")
	tabs.set_tab_title(1, "窗口与帧率")
	tabs.set_tab_title(2, "测试环境记录")
	$Interface/AboutPanel/Panel/Margin/Content/Body.meta_clicked.connect(_open_about_link)
	$Interface/AboutPanel/Panel/Margin/Content/Identity/VersionBadge/Version.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.1"))
	get_window().size_changed.connect(_window_changed)
	_update_setting_availability()
	initialized = true
	background.configure(_config())
	_new_round()


const HELP := {
	"mode": "轻负载建立延迟基线；典型桌面观察文字和移动图块；高复杂度增加编码压力。",
	"level": "一键设置细节密度与元素数量。低 1× / 64，中 2× / 512，高 4× / 2048。",
	"speed": "运动速度倍率：1 为默认，0 为静止。轻负载模式没有运动。",
	"density": "高复杂度纹理的细密程度。数值越大，纹理越细；不等于编码码率。",
	"elements": "移动图元的数量。典型桌面最多显示 12 个窗口，高复杂度最多 4096 个图元。",
	"seed": "相同种子与设置可重复相同运动轨迹；改变种子会重新排列动态元素。",
	"size": "只改变此程序的客户区，不改变桌面、BreFlow 采集或 sink 预览尺寸。",
	"vsync": "与显示器刷新同步。建议以 60 Hz + 开启为基线，关闭后另建轮次比较。",
	"target": "应用更新帧率上限，不是实测 FPS。基线使用 60，实测值见主画面。",
	"refresh": "手动填写显示器当前刷新率，仅写入报告，不会修改显示器设置。",
	"capture": "填写 BreFlow source 的采集分辨率，例如 1920x1080，仅记录。",
	"bitrate": "填写 BreFlow 编码器目标码率，单位 kbps。20000 = 20 Mbps，仅记录。",
	"sink": "填写接收端预览客户区大小，与采集分辨率分开记录。",
	"machine": "填写 CPU / GPU、显示器型号和 source 机器信息，便于复现。",
	"notes": "注明单独运行或同时运行 BreFlow、连接方式及本轮要比较的条件。"
}


func _field(key: String, caption: String, input: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 18)
	description.add_child(label)
	var hint := Label.new()
	hint.text = HELP[key]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("9faebf"))
	description.add_child(hint)
	row.add_child(description)
	input.custom_minimum_size = Vector2(250, 40)
	input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input.tooltip_text = HELP[key]
	row.add_child(input)
	fields.add_child(row)
	var separator := HSeparator.new()
	fields.add_child(separator)
	controls[key] = input


func _open_about_link(meta: Variant) -> void:
	var error := OS.shell_open(str(meta))
	if error != OK:
		_notify("打开链接失败：" + error_string(error))


func _update_setting_availability() -> void:
	var moving: bool = controls.mode.selected != 0
	controls.level.disabled = not moving
	for key in ["speed", "elements", "seed"]:
		controls[key].editable = moving
	controls.density.editable = controls.mode.selected == 2


func _option(key: String, caption: String, items: Array, selected: int) -> void:
	var input := OptionButton.new()
	for item in items:
		input.add_item(item)
	input.select(selected)
	_field(key, caption, input)
	input.item_selected.connect(func(_index: int): _changed(key))


func _number(key: String, caption: String, minimum: float, maximum: float, step: float, value: float) -> void:
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = value
	_field(key, caption, input)
	input.value_changed.connect(func(_value: float): _changed(key))


func _text(key: String, caption: String, value: String) -> void:
	var input := LineEdit.new()
	input.text = value
	_field(key, caption, input)
	input.text_submitted.connect(func(_text_value: String): _changed(key))
	input.focus_exited.connect(func(): _changed(key))


func _config() -> Dictionary:
	var screen := DisplayServer.window_get_current_screen()
	var client := DisplayServer.window_get_size()
	var desktop := DisplayServer.screen_get_size(screen)
	return {"mode": MODES[controls.mode.selected], "mode_index": controls.mode.selected,
		"complexity": LEVELS[controls.level.selected], "speed": controls.speed.value,
		"density": controls.density.value, "elements": int(controls.elements.value),
		"seed": int(controls.seed.value),
		"requested_window": str(SIZES[controls.size.selected]),
		"client_width": client.x, "client_height": client.y,
		"desktop_width": desktop.x, "desktop_height": desktop.y, "screen_index": screen,
		"screen_refresh_hz_reported": DisplayServer.screen_get_refresh_rate(screen),
		"display_refresh_hz_user": controls.refresh.value,
		"vsync_requested": "enabled" if controls.vsync.selected == 0 else "disabled",
		"vsync_reported": DisplayServer.window_get_vsync_mode(), "target_fps": Engine.max_fps,
		"capture_resolution_user": controls.capture.text, "bitrate_kbps_user": controls.bitrate.value,
		"sink_preview_user": controls.sink.text, "machine_user": controls.machine.text,
		"notes_user": controls.notes.text, "os": OS.get_name(), "os_version": OS.get_version(),
		"app_version": ProjectSettings.get_setting("application/config/version", "0.1"),
		"godot": Engine.get_version_info().string, "renderer": "gl_compatibility",
		"background_resource_error": background.resource_error,
		"settings_visible": settings_panel.visible, "about_visible": about_panel.visible,
		"toolbar_visible": toolbar_visible}


func _changed(key: String) -> void:
	if not initialized:
		return
	if key == "level":
		var index: int = controls.level.selected
		controls.density.set_value_no_signal([1.0, 2.0, 4.0][index])
		controls.elements.set_value_no_signal([64, 512, 2048][index])
	if key == "size":
		DisplayServer.window_set_size(SIZES[controls.size.selected])
	if key == "vsync":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if controls.vsync.selected == 0 else DisplayServer.VSYNC_DISABLED)
	if key == "target":
		Engine.max_fps = int(controls.target.value)
	_update_setting_availability()
	var config := _config()
	record.mark(Time.get_ticks_usec(), "setting_changed:" + key, config)
	background.configure(config)
	background.update_frame(last_elapsed, last_number)
	_update_config_label(config)
	_notify("设置已更新")
	_show_resource_error()


func _window_changed() -> void:
	if initialized:
		var config := _config()
		record.mark(Time.get_ticks_usec(), "window_size_changed", config)
		_update_config_label(config)


func _new_round() -> void:
	if export_thread != null:
		return
	var config := _config()
	background.configure(config)
	record.begin(Time.get_ticks_usec(), config)
	last_elapsed = 0
	last_number = 0
	cached_fps = 0.0
	refresh_at = 0
	stop_button.disabled = false
	export_button.disabled = false
	_update_config_label(config)
	_notify("新一轮已开始 · 前 3 秒预热")
	_show_resource_error()


func _show_resource_error() -> void:
	if not background.resource_error.is_empty():
		_notify(background.resource_error)


func _stop_round() -> void:
	if record.active:
		record.finish(Time.get_ticks_usec(), _config())
		stop_button.disabled = true
		_notify("本轮已结束")


func _process(_delta: float) -> void:
	if export_thread != null and not export_thread.is_alive():
		var result: Dictionary = export_thread.wait_to_finish()
		export_thread = null
		start_button.disabled = false
		export_button.disabled = false
		var export_path: String = result.get("path", "")
		if not export_path.is_empty():
			last_export_path = export_path
		_notify(result.message, export_path)
	if not record.active:
		return
	# Exactly one monotonic sample drives all test elements in this update.
	var now := Time.get_ticks_usec()
	record.sample(now)
	last_elapsed = now - record.start_usec
	last_number = record.ticks.size()
	var millis := int(last_elapsed / 1000)
	clock_label.text = "%02d:%02d:%02d.%03d" % [int(millis / 3600000), int(millis / 60000) % 60, int(millis / 1000) % 60, millis % 1000]
	frame_label.text = "UPDATE #%09d  |  dt %7.3f ms" % [last_number, record.intervals[-1] / 1000.0]
	background.update_frame(last_elapsed, last_number)
	# Rolling maximum is live every frame; the rolling window is only five seconds.
	var recent := record.recent()
	if now >= refresh_at:
		cached_fps = recent.fps
		refresh_at = now + 250000
	stats_label.text = "实际更新 %.2f FPS  ·  最近 5 秒最大 %.3f ms  ·  %s" % [cached_fps, recent.max_ms, "预热 / 切换区间" if record.stable[-1] == 0 else "稳定统计区间"]
	if last_number >= MAX_SAMPLES:
		_stop_round()
		_notify("达到 200 万条内存记录上限，已停止；请导出后新建轮次。")


var cached_fps := 0.0


func _update_config_label(config: Dictionary) -> void:
	config_label.text = "%s / %s  密度 %.1f  数量 %d  ·  客户区 %d×%d  ·  %s" % [
		config.mode, config.complexity, config.density, config.elements,
		config.client_width, config.client_height, record.round_id]


func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	about_panel.hide()
	if not settings_panel.visible:
		get_viewport().gui_release_focus()
	record.mark(Time.get_ticks_usec(), "settings_visibility", _config())


func _toggle_about() -> void:
	about_panel.visible = not about_panel.visible
	settings_panel.hide()
	if not about_panel.visible:
		get_viewport().gui_release_focus()
	record.mark(Time.get_ticks_usec(), "about_visibility", _config())


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	# Tab always controls the settings overlay, including while editing a field.
	if event.keycode == KEY_TAB:
		_toggle_settings()
	elif event.keycode == KEY_ESCAPE and (settings_panel.visible or about_panel.visible):
		settings_panel.hide()
		about_panel.hide()
		get_viewport().gui_release_focus()
		record.mark(Time.get_ticks_usec(), "overlay_closed", _config())
	elif settings_panel.visible or about_panel.visible:
		return
	else:
		match event.keycode:
			KEY_H: _toggle_toolbar()
			KEY_N: _new_round()
			KEY_SPACE: _stop_round()
			KEY_E: _export_round()
			_: return
	get_viewport().set_input_as_handled()


func _notify(message: String, export_path: String = "") -> void:
	status_label.text = message
	status_label.tooltip_text = message if export_path.is_empty() else export_path
	toast_export_path = export_path
	$Notifications/Toast/Margin/Row/Open.visible = not export_path.is_empty()
	$Notifications/Toast.show()
	$NotificationTimer.start()


func _toggle_toolbar() -> void:
	toolbar_visible = not toolbar_visible
	$Interface/Header.visible = toolbar_visible
	$Interface/Title.visible = toolbar_visible
	$Interface/Actions.visible = toolbar_visible
	get_viewport().gui_release_focus()
	record.mark(Time.get_ticks_usec(), "toolbar_visibility", _config())


func _open_toast_export() -> void:
	_open_log_path(toast_export_path)


func _open_last_export() -> void:
	if last_export_path.is_empty():
		_open_folder()
	else:
		_open_log_path(last_export_path)


func _open_log_path(path: String) -> void:
	if path.is_empty():
		return
	var error := OS.shell_open(path)
	if error != OK:
		_notify("打开日志失败：" + error_string(error))


func _open_folder() -> void:
	var path := ProjectSettings.globalize_path("user://exports")
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error == OK:
		error = OS.shell_open(path)
	if error != OK:
		_notify("无法打开记录目录：" + error_string(error))


func _export_round() -> void:
	if export_thread != null:
		return
	_stop_round()
	if record.ticks.is_empty():
		_notify("没有帧记录，请先开始一轮测试。")
		return
	start_button.disabled = true
	export_button.disabled = true
	_notify("正在导出日志…")
	var path := ProjectSettings.globalize_path("user://exports/%s_export_%d" % [record.round_id, Time.get_ticks_usec()])
	export_thread = Thread.new()
	var error := export_thread.start(_write_export.bind(path, record))
	if error != OK:
		export_thread = null
		start_button.disabled = false
		export_button.disabled = false
		_notify("无法启动导出：" + error_string(error))


static func _write_export(path: String, data: FrameRecord) -> Dictionary:
	# Main thread freezes this record until the worker has finished. No scene API here.
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK:
		return {"message": "创建导出目录失败：" + error_string(error)}
	var file := FileAccess.open(path.path_join("frames.csv"), FileAccess.WRITE)
	if file == null:
		return {"message": "创建 CSV 失败：" + error_string(FileAccess.get_open_error())}
	file.store_csv_line(PackedStringArray(["round_id", "ticks_usec", "elapsed_usec", "update_number", "interval_usec", "stable_sample", "segment"]))
	var all_values: Array[int] = []
	var stable_values: Array[int] = []
	var by_segment: Dictionary = {}
	for i in data.ticks.size():
		file.store_csv_line(PackedStringArray([data.round_id, str(data.ticks[i]),
			str(data.ticks[i] - data.start_usec), str(i + 1), str(data.intervals[i]),
			str(data.stable[i]), str(data.segments[i])]))
		if data.intervals[i] > 0:
			all_values.append(data.intervals[i])
		if data.stable[i] == 1:
			stable_values.append(data.intervals[i])
			var segment_id: int = data.segments[i]
			if not by_segment.has(segment_id):
				var empty: Array[int] = []
				by_segment[segment_id] = empty
			by_segment[segment_id].append(data.intervals[i])
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return {"message": "CSV 写入失败（可能留下不完整文件）：" + error_string(error)}
	var summaries: Dictionary = {}
	for segment_id in by_segment:
		summaries[str(segment_id)] = Recorder.summarize(by_segment[segment_id])
	var report := {"schema_version": 1, "round_id": data.round_id,
		"initial_config": data.initial_config, "events": data.events,
		"all_intervals": Recorder.summarize(all_values),
		"stable_intervals": Recorder.summarize(stable_values), "stable_by_segment": summaries,
		"sample_count": data.ticks.size(), "percentile_method": "nearest_rank",
		"exclusion_policy": "first sample has no interval; 3s warmup; 1s after config/window/UI events; both interval endpoints must follow exclusion boundary",
		"measurement_scope": "application updates, not GPU completion, display presentation, capture frames or packet loss"}
	file = FileAccess.open(path.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		return {"message": "统计报告创建失败：" + error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return {"message": "统计报告写入失败：" + error_string(error)}
	return {"message": "日志已导出", "path": path}


func _exit_tree() -> void:
	if export_thread != null:
		export_thread.wait_to_finish()
