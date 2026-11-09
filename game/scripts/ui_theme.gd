extends RefCounted
## Shared look for menus and overlays: flat translucent black panels, white text, one orange
## accent, matching the in-game HUD apps.

const BG := Color(0.0, 0.0, 0.0, 0.62)
const PANEL := Color(0.055, 0.058, 0.065, 0.92)
const RAISED := Color(1, 1, 1, 0.05)
const HOVER := Color(1, 1, 1, 0.11)
const BORDER := Color(1, 1, 1, 0.09)
const TEXT := Color("f2f2f2")
const MUTED := Color(1, 1, 1, 0.6)
const ACCENT := Color("ff8a2b")
const ACCENT_DARK := Color("c9651a")
const INK := Color("141414")


static func box(color: Color, radius := 4, padding := 8, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(padding)
	if border_width > 0:
		s.border_color = border
		s.set_border_width_all(border_width)
	s.anti_aliasing = true
	return s


static func accent_left(color: Color, padding := 10) -> StyleBoxFlat:
	var s := box(color, 3, padding)
	s.border_color = ACCENT
	s.border_width_left = 3
	s.content_margin_left = padding + 6
	return s


static func bold_font() -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.65
	return f


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var focus := box(Color.TRANSPARENT, 4, 8, ACCENT, 1)
	focus.draw_center = false
	for kind in [&"Button", &"OptionButton", &"CheckBox", &"CheckButton"]:
		t.set_stylebox("normal", kind, box(RAISED, 4, 9))
		t.set_stylebox("hover", kind, box(HOVER, 4, 9))
		t.set_stylebox("pressed", kind, box(Color(ACCENT, 0.35), 4, 9))
		t.set_stylebox("hover_pressed", kind, box(Color(ACCENT, 0.42), 4, 9))
		t.set_stylebox("disabled", kind, box(Color(1, 1, 1, 0.02), 4, 9))
		t.set_stylebox("focus", kind, focus)
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, Color.WHITE)
		t.set_color("font_focus_color", kind, Color.WHITE)
		t.set_color("font_disabled_color", kind, Color(1, 1, 1, 0.3))
	# Checkboxes: plain rows, the check icon carries the state.
	for state in ["normal", "pressed", "hover", "hover_pressed"]:
		t.set_stylebox(state, &"CheckBox", box(Color.TRANSPARENT if state.begins_with("normal") or state == "pressed" else HOVER, 4, 6))
	# Big call-to-action.
	t.set_type_variation(&"PrimaryButton", &"Button")
	t.set_stylebox("normal", &"PrimaryButton", box(ACCENT, 4, 12))
	t.set_stylebox("hover", &"PrimaryButton", box(Color("ffa152"), 4, 12))
	t.set_stylebox("pressed", &"PrimaryButton", box(ACCENT_DARK, 4, 12))
	var primary_focus := box(Color.TRANSPARENT, 4, 12, Color.WHITE, 2)
	primary_focus.draw_center = false
	t.set_stylebox("focus", &"PrimaryButton", primary_focus)
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		t.set_color(state, &"PrimaryButton", INK)
	t.set_font_size("font_size", &"PrimaryButton", 20)
	t.set_font("font", &"PrimaryButton", bold_font())
	# Sidebar entries: text-only rows with an accent bar on hover and focus.
	t.set_type_variation(&"SideButton", &"Button")
	t.set_stylebox("normal", &"SideButton", box(Color.TRANSPARENT, 3, 12))
	t.set_stylebox("hover", &"SideButton", accent_left(HOVER, 12))
	t.set_stylebox("pressed", &"SideButton", accent_left(Color(ACCENT, 0.3), 12))
	t.set_stylebox("focus", &"SideButton", accent_left(Color(1, 1, 1, 0.07), 12))
	t.set_font_size("font_size", &"SideButton", 18)
	t.set_constant("align_to_largest_stylebox", &"SideButton", 1)
	# Lists, popups, tabs, sliders, scroll bars.
	t.set_stylebox("panel", &"ItemList", box(Color(0, 0, 0, 0.35), 4, 4))
	t.set_stylebox("selected", &"ItemList", accent_left(Color(ACCENT, 0.22), 6))
	t.set_stylebox("selected_focus", &"ItemList", accent_left(Color(ACCENT, 0.28), 6))
	t.set_stylebox("hovered", &"ItemList", box(HOVER, 3, 6))
	t.set_stylebox("focus", &"ItemList", focus)
	t.set_color("font_color", &"ItemList", MUTED)
	t.set_color("font_selected_color", &"ItemList", Color.WHITE)
	t.set_constant("v_separation", &"ItemList", 6)
	t.set_stylebox("panel", &"PopupMenu", box(Color(0.07, 0.07, 0.08, 0.98), 4, 6, BORDER, 1))
	t.set_stylebox("hover", &"PopupMenu", box(Color(ACCENT, 0.3), 3, 4))
	t.set_color("font_color", &"PopupMenu", TEXT)
	t.set_stylebox("panel", &"TabContainer", box(Color(0, 0, 0, 0.0), 0, 14))
	t.set_stylebox("tab_selected", &"TabContainer", accent_bottom(Color(1, 1, 1, 0.06)))
	t.set_stylebox("tab_unselected", &"TabContainer", box(Color.TRANSPARENT, 0, 12))
	t.set_stylebox("tab_hovered", &"TabContainer", box(HOVER, 0, 12))
	t.set_stylebox("tab_focus", &"TabContainer", focus)
	t.set_stylebox("tabbar_background", &"TabContainer", box(Color(0, 0, 0, 0.25), 0, 0))
	t.set_color("font_selected_color", &"TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", &"TabContainer", MUTED)
	t.set_color("font_hovered_color", &"TabContainer", TEXT)
	t.set_font_size("font_size", &"TabContainer", 15)
	t.set_stylebox("slider", &"HSlider", box(Color(1, 1, 1, 0.14), 2, 2))
	t.set_stylebox("grabber_area", &"HSlider", box(ACCENT, 2, 2))
	t.set_stylebox("grabber_area_highlight", &"HSlider", box(Color("ffa152"), 2, 2))
	for bar in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(1, 1, 1, 0.04), 3, 0))
		t.set_stylebox("grabber", bar, box(Color(1, 1, 1, 0.22), 3, 0))
		t.set_stylebox("grabber_highlight", bar, box(Color(1, 1, 1, 0.35), 3, 0))
		t.set_stylebox("grabber_pressed", bar, box(ACCENT, 3, 0))
	t.set_color("font_color", &"Label", TEXT)
	t.set_stylebox("panel", &"PanelContainer", box(PANEL, 4, 16))
	t.set_stylebox("panel", &"Panel", box(PANEL, 4, 0))
	t.set_stylebox("normal", &"LineEdit", box(Color(0, 0, 0, 0.4), 4, 8, BORDER, 1))
	t.set_color("font_color", &"LineEdit", TEXT)
	t.set_stylebox("embedded_border", &"Window", box(Color(0.06, 0.06, 0.07, 0.98), 4, 12, BORDER, 1))
	t.set_color("title_color", &"Window", TEXT)
	return t


static func accent_bottom(color: Color) -> StyleBoxFlat:
	var s := box(color, 0, 12)
	s.border_color = ACCENT
	s.border_width_bottom = 2
	return s


static func label(value: String, size := 15, color := TEXT, heavy := false) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if heavy:
		l.add_theme_font_override("font", bold_font())
	return l


static func section(title: String) -> Label:
	var l := label(title.to_upper(), 12, ACCENT, true)
	return l
