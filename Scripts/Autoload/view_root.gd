extends SubViewportContainer
## First autoload. Hosts the entire game inside a 480x270 SubViewport whose
## texture is drawn at window resolution through the "Screen Style" shader
## (the RetroArch pipeline: low-res render, high-res reconstruction).
## Autoload CanvasLayers (HUD, transitions, split panes - all layer >= 1)
## draw above this container and stay crisp at native window resolution.

const CLEAN_EDGE := preload("res://Shaders/clean_edge.gdshader")

@onready var view: SubViewport = $GameView

var _adopted := false
var _style_applied := -1
var _pane_material: ShaderMaterial = null

func _ready() -> void:
	# Input reaches nodes inside the SubViewport only through this container's
	# forwarding - it must keep processing while the tree is paused, or pause
	# menus and the join lobby go dead.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The GameView must be the 2D audio listener or every AudioStreamPlayer2D
	# in the game world goes silent (the root listener no longer sees them).
	view.audio_listener_enable_2d = true
	get_window().size_changed.connect(_on_window_resized)
	call_deferred("_adopt_current_scene")

## Move the engine-instanced boot scene (and thus everything TransitionManager
## swaps in after it) into the game view.
func _adopt_current_scene() -> void:
	var cur := get_tree().current_scene
	if not is_instance_valid(cur):
		return
	if cur.get_parent() == get_tree().root:
		cur.get_parent().remove_child(cur)
		view.add_child(cur)
	_adopted = true

func _process(_delta: float) -> void:
	if not _adopted:
		_adopt_current_scene()
	var style := int(SettingsManager.settings_file.get("screen_style", 0))
	if style != _style_applied:
		_style_applied = style
		_apply_style(style)

func _output_scale() -> float:
	# output pixels per game texel (4.0 on the 1920x1080 couch panel)
	return maxf(1.0, float(get_window().size.x) / 480.0)

func _make_screen_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CLEAN_EDGE
	m.set_shader_parameter("scale", _output_scale())
	return m

## Shared material for the split-screen pane containers, so the panes match
## the main view. Null in Classic mode (panes then draw plain nearest).
func pane_material() -> ShaderMaterial:
	if _style_applied != 0:
		return null
	if _pane_material == null:
		_pane_material = _make_screen_material()
	return _pane_material

func _apply_style(style: int) -> void:
	_pane_material = null
	if style == 0:
		# Smooth & Modern: cleanEdge reconstruction. The shader does its own
		# neighbourhood sampling - the source must stay NEAREST.
		material = _make_screen_material()
	else:
		# Classic Pixels: plain nearest upscale, the original look
		material = null
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _on_window_resized() -> void:
	if material is ShaderMaterial:
		material.set_shader_parameter("scale", _output_scale())
	if _pane_material != null:
		_pane_material.set_shader_parameter("scale", _output_scale())
