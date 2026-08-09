extends AnimatableBody2D

var sinking := false

func _physics_process(delta: float) -> void:
	if sinking:
		global_position.y += 16 * delta

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player:
		sinking = true

func _enter_tree() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
