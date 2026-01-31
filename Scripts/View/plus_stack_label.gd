extends Label

@export var queue_manager: QueueManager

func _ready() -> void:
	if queue_manager == null:
		var qm := get_tree().get_first_node_in_group("queue_manager")
		if qm is QueueManager:
			queue_manager = qm
	set_text("")

func _process(delta: float) -> void:
	if queue_manager == null:
		return
	set_text(queue_manager.get_draw_stack_text())
