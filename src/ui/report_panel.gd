class_name ReportPanel
extends VBoxContainer
## "While you were away" and other one-off reports.

var _title: Label
var _body: Label


func setup() -> void:
	add_theme_constant_override("separation", 3)
	_title = UIKit.label("", 11, UIStyle.ACCENT)
	add_child(_title)
	var sc := UIKit.scroll(170)
	add_child(sc)
	_body = UIKit.label("", 9)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(320, 0)
	sc.add_child(_body)
	add_child(UIKit.button("OK", func(): get_meta("hud").show_panel(""), 0, 24))


func show_report(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
