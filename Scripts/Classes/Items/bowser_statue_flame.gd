extends Enemy

func _ready() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
	SoundManager.play_sfx(SoundManager.boss_flame, self)

func _physics_process(delta: float) -> void:
	global_position.x -= 64 * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_visible_on_screen_enabler_2d_screen_entered() -> void:
	SoundManager.play_sfx(SoundManager.boss_flame, self)
