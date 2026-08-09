extends Node
## Slow-mo powerup, v3 (David's simplified design after playtest).
## ONE mode: the whole game slows to half speed EXCEPT the players -
## "game faithful, it just moves slower". Charge with coins (+4) and enemy
## defeats (+10); a full bar arms. HOLD EITHER BUMPER (~0.5 s) to fire:
## the bar dumps to zero and the effect runs a flat 15 seconds. Anything
## collected during it simply charges the next use. Keyboard seat: hold V/B.
##
## Mechanism: everything autonomous in the world is enrolled in the
## "slowmo_world" group (base-class one-liners + per-script adds) and gets
## process-frozen on alternate physics frames - uniform half rate for motion,
## AI, node timers, tweens and animation. Hardening: enrolled collision roots
## hold DISABLE_MODE_MAKE_STATIC and their child collision objects
## DISABLE_MODE_KEEP_ACTIVE during the effect (bodies stay solid, no
## area_entered churn), meta-tag ownership (never fights the ice block or
## VisibleOnScreenEnabler2D), carried items and yoshi-tongued things skip.
## Auto-scroll cameras are special-cased: scroll_speed halves instead.
## The active effect paints the RetroArch "technicolor" film look, faithfully
## ported (see Shaders/technicolor_film.gdshader for lineage/attribution).
##
## Mode 2 (full cinematic, players included) is parked until this one is
## nailed - the second bumper's future home.

const EFFECT_SECONDS := 15.0    # flat duration (David's number)
const HOLD_SECONDS := 0.5       # bumper hold to fire (kids click things)
const MUSIC_PITCH := 0.85

const SFX_IN := preload("res://Assets/Audio/SFX/slowmo_in.wav")
const SFX_OUT := preload("res://Assets/Audio/SFX/slowmo_out.wav")
const FILM_SHADER := preload("res://Shaders/technicolor_film_view.gdshader")
const FILM_LUT := preload("res://Assets/Shaders/cmyk-16.png")
const FILM_NOISE := preload("res://Assets/Shaders/film_noise1.png")

var active_seat := -1           # seat that fired the active effect (-1 = off)
var time_left := 0.0
var hold_time := [0.0, 0.0, 0.0, 0.0]
var _area_cache := {}           # CollisionObject2D -> original disable_mode
var _root_cache := {}           # enrolled body root -> original disable_mode
var _scroll_cache := {}         # auto_scroll node -> original scroll_speed
var _pitch_fx: AudioEffectPitchShift = null
var _film_mat: ShaderMaterial = null
var _film_strength := 0.0
var _film_applied := false
var _saved_material: Material = null

func _ready() -> void:
	# The film look is applied as ViewRoot's material - the same mount that
	# renders cleanEdge in Smooth mode, i.e. the one shader path PROVEN to
	# draw on this renderer. (Screen-texture overlay CanvasLayers silently
	# didn't render here - the v11 vignette and the first technicolor mount
	# both failed the same way.)
	_film_mat = ShaderMaterial.new()
	_film_mat.shader = FILM_SHADER
	_film_mat.set_shader_parameter("lut_tex", FILM_LUT)
	_film_mat.set_shader_parameter("noise_tex", FILM_NOISE)
	_film_mat.set_shader_parameter("strength", 0.0)

func _process(delta: float) -> void:
	var target := 1.0 if active_seat >= 0 else 0.0
	_film_strength = move_toward(_film_strength, target, delta * 2.0)
	_film_mat.set_shader_parameter("strength", _film_strength)
	if _film_strength > 0.01 and not _film_applied:
		_saved_material = ViewRoot.material
		ViewRoot.material = _film_mat
		_film_applied = true
	elif _film_strength <= 0.01 and _film_applied:
		ViewRoot.material = _saved_material
		_saved_material = null
		_film_applied = false
		ViewRoot._style_applied = -1   # let ViewRoot re-assert the Screen Style

func _physics_process(delta: float) -> void:
	if active_seat == -1 and _gameplay_ok():
		_poll_hold(delta)
	if active_seat >= 0:
		time_left -= delta
		_poll_owner_exit(delta)
		if active_seat >= 0 and (time_left <= 0.0 or not _gameplay_ok()):
			_end_effect()
		elif active_seat >= 0:
			_freeze_tick()

func _gameplay_ok() -> bool:
	if not SettingsManager.settings_file.get("slowmo_powerups", true):
		return false
	if not is_instance_valid(GameManager.current_level):
		return false
	if GameManager.vs_mode or TransitionManager.changing_scene:
		return false
	return true

func _poll_hold(delta: float) -> void:
	for seat in range(CoopManager.players_connected):
		var node = CoopManager.alive_players.get(seat)
		if not is_instance_valid(node):
			hold_time[seat] = 0.0
			continue
		# debug-build cheat for QA: F9 fills seat 0's bar
		if OS.is_debug_build() and seat == 0 and Input.is_key_pressed(KEY_F9):
			CoopManager.slowmo_charge[0] = 100.0
		if CoopManager.slowmo_charge[seat] < 100.0:
			hold_time[seat] = 0.0
			continue
		var held := Input.is_action_pressed(CoopManager.get_player_input_str("slowmo_enemy", seat)) \
			or Input.is_action_pressed(CoopManager.get_player_input_str("slowmo_world", seat))
		if held:
			hold_time[seat] += delta
			if hold_time[seat] >= HOLD_SECONDS:
				hold_time[seat] = 0.0
				_start_effect(seat)
				return
		else:
			hold_time[seat] = 0.0

## Only the player who fired the effect may cancel it early - a short
## bumper hold (~0.25 s) so a stray tap mid-jump doesn't eat the powerup.
func _poll_owner_exit(delta: float) -> void:
	var seat := active_seat
	var node = CoopManager.alive_players.get(seat)
	if not is_instance_valid(node):
		return
	var held := Input.is_action_pressed(CoopManager.get_player_input_str("slowmo_enemy", seat)) 		or Input.is_action_pressed(CoopManager.get_player_input_str("slowmo_world", seat))
	# reuse hold_time, but only once the fire-hold has been released first
	if held and hold_time[seat] >= 0.0:
		hold_time[seat] += delta
		if hold_time[seat] >= 0.25:
			hold_time[seat] = -1.0
			_end_effect()
	elif not held:
		hold_time[seat] = 0.0

func _start_effect(seat: int) -> void:
	active_seat = seat
	time_left = EFFECT_SECONDS
	hold_time[seat] = -1.0   # ignore the still-held fire press until released
	CoopManager.slowmo_charge[seat] = 0.0   # the bar is spent, recharge fresh - no extension mechanics
	SoundManager.play_ui_sound(SFX_IN)
	_music_pitch(MUSIC_PITCH)
	_slow_autoscrollers(true)

func _end_effect() -> void:
	active_seat = -1
	time_left = 0.0
	SoundManager.play_ui_sound(SFX_OUT)
	_music_pitch(1.0)
	_slow_autoscrollers(false)
	_thaw_all()

## ---- the freeze loop --------------------------------------------------------

func _freeze_tick() -> void:
	var off_frame := (Engine.get_physics_frames() & 1) == 1
	for e in get_tree().get_nodes_in_group("slowmo_world"):
		if not is_instance_valid(e):
			continue
		# never fight the ice block, yoshi's tongue, or items in a player's hands
		if e.get("frozen") == true or e.get("is_yoshi_item") == true or e.get("held") == true:
			continue
		var y = e.get("yoshi")
		if y != null and is_instance_valid(y):
			continue
		if off_frame:
			if e.process_mode != Node.PROCESS_MODE_DISABLED:
				_harden(e)
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.set_meta("slowmo_off", true)
		else:
			if e.has_meta("slowmo_off"):
				e.process_mode = Node.PROCESS_MODE_INHERIT
				e.remove_meta("slowmo_off")

## Bodies must stay solid and areas must stay in the physics space while
## frozen, or players fall through platforms/bosses and area_entered re-fires
## every re-add. Cache originals, restore on thaw.
func _harden(e: Node) -> void:
	if e.has_meta("slowmo_prepped"):
		return
	e.set_meta("slowmo_prepped", true)
	if e is CollisionObject2D and not _root_cache.has(e):
		_root_cache[e] = e.disable_mode
		e.disable_mode = CollisionObject2D.DISABLE_MODE_MAKE_STATIC
	for child in e.find_children("*", "CollisionObject2D", true, false):
		if not _area_cache.has(child):
			_area_cache[child] = child.disable_mode
			child.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE

func _thaw_all() -> void:
	for e in get_tree().get_nodes_in_group("slowmo_world"):
		if not is_instance_valid(e):
			continue
		if e.has_meta("slowmo_off"):
			e.process_mode = Node.PROCESS_MODE_INHERIT
			e.remove_meta("slowmo_off")
		if e.has_meta("slowmo_prepped"):
			e.remove_meta("slowmo_prepped")
	for n in _root_cache.keys():
		if is_instance_valid(n):
			n.disable_mode = _root_cache[n]
	_root_cache.clear()
	for child in _area_cache.keys():
		if is_instance_valid(child):
			child.disable_mode = _area_cache[child]
	_area_cache.clear()

## Auto-scroll owns the live camera + kill walls - frame-freezing it would
## stutter the camera for everyone. Halve its speed instead.
func _slow_autoscrollers(on: bool) -> void:
	for n in get_tree().get_nodes_in_group("slowmo_autoscroll"):
		if not is_instance_valid(n):
			continue
		if on:
			if not _scroll_cache.has(n):
				_scroll_cache[n] = n.scroll_speed
				n.scroll_speed = n.scroll_speed * 0.5
		else:
			if _scroll_cache.has(n):
				n.scroll_speed = _scroll_cache[n]
	if not on:
		_scroll_cache.clear()

## ---- music pitch ------------------------------------------------------------

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
