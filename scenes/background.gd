# SPDX-License-Identifier: GPL-3.0-only
extends Control

var mode := 0
var elapsed := 0.0
var speed := 1.0
var density := 1.0
var element_count := 64
var seed_value := 20260905
var points := PackedVector2Array()
var velocities := PackedVector2Array()
var colors := PackedColorArray()
var resource_error := ""


func configure(config: Dictionary) -> void:
	mode = config.mode_index
	speed = config.speed
	density = config.density
	element_count = config.elements
	seed_value = config.seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	points.clear()
	velocities.clear()
	colors.clear()
	for i in element_count:
		points.append(Vector2(rng.randf() * 1152.0, rng.randf() * 648.0))
		velocities.append(Vector2(rng.randf_range(-70, 70), rng.randf_range(-50, 50)))
		colors.append(Color.from_hsv(rng.randf(), 0.55, 0.95))
	var shader := $Texture.material as ShaderMaterial
	if shader == null or shader.shader == null:
		resource_error = "背景着色器加载失败，使用纯色背景；请检查资源文件。"
		$Texture.material = null
		$Texture.color = Color(0.035, 0.06, 0.095)
		queue_redraw()
		return
	resource_error = ""
	shader.set_shader_parameter("mode", mode)
	shader.set_shader_parameter("speed", speed)
	shader.set_shader_parameter("density", density)
	shader.set_shader_parameter("seed_value", float(seed_value % 65521))
	queue_redraw()


func update_frame(usec: int, _number: int) -> void:
	elapsed = usec / 1000000.0
	var shader := $Texture.material as ShaderMaterial
	if shader != null and shader.shader != null:
		shader.set_shader_parameter("elapsed", elapsed)
	queue_redraw()


func _draw() -> void:
	if not resource_error.is_empty() or (mode != 1 and mode != 2):
		return
	var count := mini(element_count, 12) if mode == 1 else element_count
	for i in count:
		var p := points[i] + velocities[i] * elapsed * speed
		p = Vector2(fposmod(p.x, 1152.0), fposmod(p.y, 648.0))
		if mode == 2:
			draw_rect(Rect2(p, Vector2(3, 7) * density), colors[i])
		else:
			draw_style_box(_window_style(), Rect2(p, Vector2(220, 104)))
			draw_rect(Rect2(p, Vector2(220, 20)), colors[i].darkened(0.6))
			for line in 4:
				var offset := fposmod(elapsed * speed * 18.0 + line * 19.0, 76.0)
				draw_string(ThemeDB.fallback_font, p + Vector2(8, 27 + offset),
					"BreFlow  Aa 012345  演示文本", HORIZONTAL_ALIGNMENT_LEFT, 205, 12, Color.WHITE)


var window_style: StyleBoxFlat


func _window_style() -> StyleBoxFlat:
	if window_style == null:
		window_style = StyleBoxFlat.new()
		window_style.bg_color = Color(0.06, 0.09, 0.14, 0.95)
		window_style.set_border_width_all(1)
		window_style.border_color = Color(0.3, 0.45, 0.6)
	return window_style
