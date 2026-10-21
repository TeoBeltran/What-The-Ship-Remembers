extends Control
## Menú del personaje (paso 8), se abre y cierra con Q (Esc también cierra).
## Tres pestañas: Anotaciones (hechos, agrupados por turno), Conversaciones (lo que dijo NORA,
## para releer y comparar) e Inventario.
## ←/→ (A/D) o 1/2/3 cambian de pestaña · ↑/↓ (W/S) o la ruedita desplazan · click en las pestañas.
## La interfaz está a 960x540 (se escala con el CanvasLayer).

const PESTANAS := ["Anotaciones", "Conversaciones", "Inventario"]
const C_TITULO := "#e0e0e0"
const C_TURNO := "#8a8f99"
const C_TEXTO := "#d8d8d8"
const C_VACIO := "#6a6e76"
const C_YO := "#e6e6e6"

var _pestana := 0
var _botones: Array[Button] = []
var _texto: RichTextLabel


func _ready() -> void:
	position = Vector2(0, 0)
	size = Vector2(960, 540)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.6)
	fondo.size = size
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	var panel := PanelContainer.new()
	panel.position = Vector2(60, 42)
	panel.size = Vector2(840, 450)
	panel.add_theme_stylebox_override("panel", TemaUI.marco("marco_dialogo", TemaUI.C_BORDE, 18))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	v.add_child(fila)
	for i in PESTANAS.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, PESTANAS[i]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): elegir(i))
		fila.add_child(b)
		_botones.append(b)
	_texto = RichTextLabel.new()
	_texto.bbcode_enabled = true
	_texto.scroll_active = true
	_texto.scroll_following = false
	_texto.custom_minimum_size = Vector2(800, 340)
	_texto.add_theme_font_override("normal_font", TemaUI.fuente)
	_texto.add_theme_font_override("bold_font", TemaUI.fuente)
	_texto.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_texto.add_theme_font_size_override("normal_font_size", 16)
	_texto.add_theme_font_size_override("bold_font_size", 16)
	_texto.focus_mode = Control.FOCUS_NONE
	v.add_child(_texto)
	var pie := Label.new()
	pie.text = "←/→ o 1/2/3 pestaña · ↑/↓ o ruedita desplazar · Q / Esc cerrar"
	pie.add_theme_font_size_override("font_size", 16)
	pie.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(pie)


func abrir() -> void:
	visible = true
	elegir(_pestana)


func cerrar() -> void:
	visible = false


func elegir(i: int) -> void:
	_pestana = posmod(i, PESTANAS.size())
	for j in _botones.size():
		_botones[j].button_pressed = j == _pestana
	_texto.clear()
	match _pestana:
		0:
			_texto.append_text(_anotaciones())
		1:
			_texto.append_text(_conversaciones())
		2:
			_texto.append_text(_inventario())
	# Anotaciones y conversaciones: se abre al final (lo más nuevo); inventario, arriba.
	if _pestana < 2:
		_bajar_al_final.call_deferred()
	else:
		_texto.scroll_to_line(0)


func _bajar_al_final() -> void:
	_texto.scroll_to_line(maxi(_texto.get_line_count() - 1, 0))


func cambiar_pestana(paso: int) -> void:
	elegir(_pestana + paso)


func desplazar(paso: int) -> void:
	var barra := _texto.get_v_scroll_bar()
	barra.value += paso * 20


# ------------------------------------------------------------
# Contenido de cada pestaña (BBCode)
# ------------------------------------------------------------

static func _limpio(t: String) -> String:
	return t.replace("[", "[lb]")


func _anotaciones() -> String:
	if Estado.anotaciones.is_empty():
		return "[color=%s]Todavía no anoté nada.[/color]" % C_VACIO
	var s := ""
	var turno_actual := -1
	for id in Estado.anotaciones:
		var t := int(Estado.anotaciones_turno.get(id, 0))
		if t != turno_actual:
			turno_actual = t
			s += ("\n" if s != "" else "") + "[color=%s]Turno %d[/color]\n" % [C_TURNO, t]
		s += "[color=%s]·  %s[/color]\n" % [C_TEXTO, _limpio(str(Estado.anotaciones_txt.get(id, id)))]
	return s


func _conversaciones() -> String:
	if Estado.conversaciones.is_empty():
		return "[color=%s]Todavía no hablé con NORA.[/color]" % C_VACIO
	var voces: Dictionary = get_parent().VOCES
	var s := ""
	var turno_actual := -1
	for c in Estado.conversaciones:
		if int(c["turno"]) != turno_actual:
			turno_actual = int(c["turno"])
			s += ("\n" if s != "" else "") + "[color=%s]Turno %d[/color]\n" % [C_TURNO, turno_actual]
		else:
			s += "[color=%s]  ·[/color]\n" % C_TURNO  # separa conversaciones del mismo turno
		for l in Estado.lineas_de(c["id"]):
			var h: String = l["hablante"]
			var texto := _limpio(str(l["texto"]))
			if h == "PERSONAJE":
				s += "[color=%s]Yo: %s[/color]\n" % [C_YO, texto]
			else:
				# Se respeta la "voz" de NORA (normal o de otro tiempo) también al releer.
				var voz: Dictionary = voces.get(h, voces["NORA"])
				s += "[color=#%s]NORA:[/color] [color=#%s]%s[/color]\n" % [
					voz["nombre"].to_html(false), voz["texto"].to_html(false), texto]
	return s


func _inventario() -> String:
	if Estado.inventario.is_empty():
		return "[color=%s]No llevo nada encima.[/color]" % C_VACIO
	var s := ""
	for id in Estado.inventario:
		var it: Dictionary = Estado.items.get(id, {})
		s += "[color=%s][b]%s[/b][/color]\n[color=%s]%s[/color]\n\n" % [
			C_TITULO, _limpio(str(it.get("nombre", id))), C_TEXTO, _limpio(str(it.get("descripcion", "")))]
	return s


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			desplazar(-1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			desplazar(1)
			accept_event()
