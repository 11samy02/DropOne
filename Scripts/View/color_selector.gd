extends HBoxContainer
class_name ColorSelector


func _ready() -> void:
	hide()
	Signals.COLOR_request_color_select.connect(func():
		show()
	)
	Signals.COLOR_color_selected.connect(func(color):
		hide()
	)



func _on_red_pressed() -> void:
	Signals.COLOR_color_selected.emit(CardResource.CardColor.RED)


func _on_yellow_pressed() -> void:
	Signals.COLOR_color_selected.emit(CardResource.CardColor.YELLOW)


func _on_green_pressed() -> void:
	Signals.COLOR_color_selected.emit(CardResource.CardColor.GREEN)


func _on_blue_pressed() -> void:
	Signals.COLOR_color_selected.emit(CardResource.CardColor.BLUE)
