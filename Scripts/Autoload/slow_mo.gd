extends Node
## Slow-mo powerups (David's design, v2 after playtest).
## Charge with coins (+4) and enemy defeats (+10); a full bar arms both modes.
## L3 = ENEMY slow-mo, R3 = WORLD slow-mo. 15 s drain, refilled (extended) by
## anything you score during the effect. Keyboard seat: V / B.
##
## WORLD mode (v2): the whole game view skips every other simulation frame -
## "dropping framerate" on purpose. Per executed frame the physics are
## byte-identical (jump heights exact); the world just plays at half rate.
## No Engine.time_scale - v1 used it and it warped jump feel.
## ENEMY mode (v2): alternate-frame freeze on everything in the "enemies"
## group EXCEPT bodies in the air - arcs and falls play out at full physics,
## only grounded locomotion (and floaty pattern movers on the ground) halves.
## Both modes paint a breathing vignette: teal = enemy, indigo = world.

const DRAIN_PER_SEC := 100.0 / 15.0    # full bar = 15 s (David's number)
const MUSIC_PITCH := 0.85

const SFX_IN := preload("res://Assets/Audio/SFX/slowmo_in.wav")
const SFX_OUT := preload("res://Assets/Audio/SFX/slowmo_out.wav")
const VIGNETTE_SHADER := preload("res://Shaders/slowmo_vignette.gdshader")

const TEAL := Color(0.05, 0.78, 0.72)
const INDIGO := Color(0.38, 0.28, 0.95)

var enemy_seat := -1     # seat that owns the active enemy slow-mo (-1 = off)
var world_seat := -1
var _area_cache := {}    # CollisionObject2D -> original disable_mode
var _pitch_fx: AudioEffectPitchShift = null
var _vignette: ColorRect = null
var _vig_mat: ShaderMaterial = null
var _vig_strength := 0.0
var _vig_target := 0.0

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3   # above split panes (1) + meters (2), below GameManager UI (5)
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.color = Color.WHITE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = VIGNETTE_SHADER
	_vignette.material = _vig_mat
	layer.add_child(_vignette)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.visible = false

func _process(delta: float) -> void:
	# vignette fade runs on idle time so it stays smooth during frame-skip
	_vig_strength = move_toward(_vig_strength, _vig_target, delta * 2.5)
	_vig_mat.set_shader_parameter("strength", _vig_strength)
	_vignette.visible = _vig_strength > 0.01

func _physics_process(delta: float) -> void:
	if _gameplay_ok():
		_poll_activation()
	_run_drain(delta)
	if world_seat >= 0:
		_world_tick()
	if enemy_seat >= 0:
		_freeze_tick()

func _gameplay_ok() -> bool:
	if not SettingsManager.settings_file.get("slowmo_powerups", true):
		return false
	if not is_instance_valid(GameManager.current_level):
		return false
	if GameManager.vs_mode or TransitionManager.changing_scene:
		return false
	return true

func _poll_activation() -> void:
	for seat in range(CoopManager.players_connected):
		var node = CoopManager.alive_players.get(seat)
		if not is_instance_valid(node):
			continue
		if CoopManager.slowmo_charge[seat] < 100.0:
			continue
		if enemy_seat == -1 and Input.is_action_just_pressed(CoopManager.get_player_input_str("slowmo_enemy", seat)):
			_start_enemy(seat)
		elif world_seat == -1 and Input.is_action_just_pressed(CoopManager.get_player_input_str("slowmo_world", seat)):
			_start_world(seat)

func _run_drain(delta: float) -> void:
	if enemy_seat >= 0:
		CoopManager.slowmo_charge[enemy_seat] = maxf(CoopManager.slowmo_charge[enemy_seat] - DRAIN_PER_SEC * delta, 0.0)
		if CoopManager.slowmo_charge[enemy_seat] <= 0.0 or not _gameplay_ok():
			_end_enemy()
	if world_seat >= 0:
		CoopManager.slowmo_charge[world_seat] = maxf(CoopManager.slowmo_charge[world_seat] - DRAIN_PER_SEC * delta, 0.0)
		if CoopManager.slowmo_charge[world_seat] <= 0.0 or not _gameplay_ok():
			_end_world()

func _set_vignette(col: Color, on: bool) -> void:
	if on:
		_vig_mat.set_shader_parameter("tint", Color(col.r, col.g, col.b, 1.0))
		_vig_target = 1.0
	else:
		# only fade out if the other mode isn't holding the overlay
		if enemy_seat == -1 and world_seat == -1:
			_vig_target = 0.0
		elif enemy_seat >= 0:
			_vig_mat.set_shader_parameter("tint", Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
		elif world_seat >= 0:
			_vig_mat.set_shader_parameter("tint", Color(INDIGO.r, INDIGO.g, INDIGO.b, 1.0))

func _start_enemy(seat: int) -> void:
	enemy_seat = seat
	SoundManager.play_ui_sound(SFX_IN)
	_set_vignette(TEAL, true)

func _end_enemy() -> void:
	enemy_seat = -1
	SoundManager.play_ui_sound(SFX_OUT)
	_thaw_all()
	_set_vignette(TEAL, false)

func _start_world(seat: int) -> void:
	world_seat = seat
	SoundManager.play_ui_sound(SFX_IN)
	_music_pitch(MUSIC_PITCH)
	_set_vignette(INDIGO, true)

func _end_world() -> void:
	world_seat = -1
	SoundManager.play_ui_sound(SFX_OUT)
	_music_pitch(1.0)
	if is_instance_valid(ViewRoot.view):
		ViewRoot.view.process_mode = Node.PROCESS_MODE_INHERIT
	_set_vignette(INDIGO, false)

## ---- world mode: whole-game frame skip ------------------------------------
## The entire game lives inside ViewRoot's GameView; disabling its processing
## every other physics frame halves the simulation rate for EVERYTHING in it
## (players, enemies, timers, animations) with per-frame physics untouched.
## Nodes with explicit PROCESS_MODE_ALWAYS (the pause menu) keep running -
## DISABLED only propagates to children that INHERIT.

func _world_tick() -> void:
	if not is_instance_valid(ViewRoot.view):
		return
	var off_frame := (Engine.get_physics_frames() & 1) == 1
	ViewRoot.view.process_mode = Node.PROCESS_MODE_DISABLED if off_frame else Node.PROCESS_MODE_INHERIT

## ---- enemy mode: grounded freeze loop --------------------------------------

func _freeze_tick() -> void:
	var off_frame := (Engine.get_physics_frames() & 1) == 1
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# never fight the ice block, yoshi's tongue, or held/item forms
		if e.get("frozen") == true or e.get("is_yoshi_item") == true:
			continue
		var y = e.get("yoshi")
		if y != null and is_instance_valid(y):
			continue
		# airborne bodies finish their arcs at full physics ("slow their
		# speed, not their physics" - jumps and falls look natural)
		var airborne: bool = e is CharacterBody2D and not e.is_on_floor() and absf(e.velocity.y) > 1.0
		if off_frame and not airborne:
			if e.process_mode != Node.PROCESS_MODE_DISABLED:
				_keep_areas_active(e)
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.set_meta("slowmo_off", true)
		else:
			if e.has_meta("slowmo_off"):
				e.process_mode = Node.PROCESS_MODE_INHERIT
				e.remove_meta("slowmo_off")

## While frozen on off-frames, hit/hurt areas must stay in the physics space
## or area_entered re-fires every re-add (double damage/stomps). Cache the
## original disable modes and restore on thaw.
func _keep_areas_active(e: Node) -> void:
	if e.has_meta("slowmo_areas_prepped"):
		return
	e.set_meta("slowmo_areas_prepped", true)
	for child in e.find_children("*", "CollisionObject2D", true, false):
		if not _area_cache.has(child):
			_area_cache[child] = child.disable_mode
			child.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE

func _thaw_all() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_meta("slowmo_off"):
			e.process_mode = Node.PROCESS_MODE_INHERIT
			e.remove_meta("slowmo_off")
		if e.has_meta("slowmo_areas_prepped"):
			e.remove_meta("slowmo_areas_prepped")
	for child in _area_cache.keys():
		if is_instance_valid(child):
			child.disable_mode = _area_cache[child]
	_area_cache.clear()

## ---- music pitch (world mode) ----------------------------------------------

func _music_pitch(pitch: float) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus == -1:
		return
	if pitch == 1.0:
		if _pitch_fx != null:
			for i in AudioServer.get_bus_effect_count(bus):
				if AudioServer.get_bus_effect(bus, i) == _pitch_fx:
					AudioServer.remove_bus_effect(bus, i)
					break
			_pitch_fx = null
	else:
		if _pitch_fx == null:
			_pitch_fx = AudioEffectPitchShift.new()
			AudioServer.add_bus_effect(bus, _pitch_fx)
		_pitch_fx.pitch_scale = pitch
