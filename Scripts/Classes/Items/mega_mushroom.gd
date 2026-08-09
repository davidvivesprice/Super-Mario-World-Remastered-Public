extends CharacterBody2D


func _on_hitbox_area_entered(area: Area2D) -> void:
	var node = area.get_parent()
	if node is Player:
		node.mega_mushroom_grow()
		queue_free()

func _enter_tree() -> void:
	add_to_group("slowmo_world")   # slow-mo powerup target
