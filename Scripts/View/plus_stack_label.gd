extends Label

@export var queue_manager: QueueManager


func _process(delta: float) -> void:
	set_text(queue_manager.get_draw_stack_text())
