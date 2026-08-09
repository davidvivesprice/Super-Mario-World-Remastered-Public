extends Node2D
## Self-verifying render test for the technicolor film shader: draws the
## rainbow LUT strip twice - left clean, right through the film material at
## full strength - screenshots the real GPU output, and quits. Run with:
##   godot --path . res://Tests/film_check.tscn
## PASS = the saved PNG's right half is visibly graded (two-strip color,
## vignette). A shader compile failure leaves the right half identical.

const OUT_PATH := "user://film_check.png"

func _ready() -> void:
	var tex := preload("res://Assets/Shaders/cmyk-16.png")  # full-hue rainbow strip
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://Shaders/technicolor_film_view.gdshader")
	mat.set_shader_parameter("lut_tex", tex)
	mat.set_shader_parameter("noise_tex", preload("res://Assets/Shaders/film_noise1.png"))
	mat.set_shader_parameter("strength", 1.0)
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var left := TextureRect.new()
	left.texture = tex
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.position = Vector2(0, 0)
	left.size = Vector2(240, 270)
	layer.add_child(left)
	var right := TextureRect.new()
	right.texture = tex
	right.stretch_mode = TextureRect.STRETCH_SCALE
	right.material = mat
	right.position = Vector2(240, 0)
	right.size = Vector2(240, 270)
	layer.add_child(right)
	_snap()

func _snap() -> void:
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_PATH)
	print("FILM_CHECK saved: ", ProjectSettings.globalize_path(OUT_PATH))
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
