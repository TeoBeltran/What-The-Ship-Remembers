extends CanvasLayer
## Interfaz en greybox (pasos 3 a 5): estado arriba, caja de diálogo (con preguntas de opciones),
## avisos, indicación para interactuar, fundido a negro entre turnos y menú de pausa (Esc).

signal dialogo_terminado
signal respuesta(indice: int)

const NOMBRE_HABLANTE := {"PERSONAJE": "Yo", "NORA": "NORA"}
const NOMBRE_AUDIO := {"estatica": "estática de radio", "chisporroteo": "chisporroteo eléctrico"}

var estado: Label
var depuracion: Label
var mensaje: Label
var indicacion: Label
var avisos: VBoxContainer
var caja: PanelContainer
var caja_hablante: Label
var caja_texto: Label
var menu: Control
var caja_pie: Label
var caja_opciones: HBoxContainer
var negro: ColorRect
var negro_texto: Label

var _cola: Array = []          # líneas pendientes {hablante, texto}
var _tiempo_mensaje := 0.0
var _pregunta := false
var _seleccion := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	estado = _label(Vector2(8, 4), 12)
	mensaje = _label(Vector2(8, 284), 12)
	mensaje.size.x = 624
	mensaje.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	indicacion = _label(Vector2(8, 302), 11)
	indicacion.size.x = 624
	indicacion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	indicacion.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	depuracion = _label(Vector2(8, 340), 10)
	depuracion.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	avisos = VBoxContainer.new()
	avisos.position = Vector2(440, 24)
	avisos.size = Vector2(192, 100)
	avisos.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(avisos)
	_crear_caja()
	_crear_negro()
	_crear_menu()


func _label(pos: Vector2, tam: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", tam)
	add_child(l)
	return l


func _process(delta: float) -> void:
	if _tiempo_mensaje > 0:
		_tiempo_mensaje -= delta
		if _tiempo_mensaje <= 0:
			mensaje.text = ""


# ============================================================
# Mensajes y avisos
# ============================================================

func mostrar_mensaje(texto: String) -> void:
	mensaje.text = texto
	_tiempo_mensaje = 2.5


## Aviso chico arriba a la derecha que se desvanece (anotaciones, items, sonidos).
func aviso(texto: String, color := Color(0.95, 0.9, 0.6)) -> void:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	avisos.add_child(l)
	var t := create_tween()
	t.tween_interval(2.5)
	t.tween_property(l, "modulate:a", 0.0, 0.8)
	t.tween_callback(l.queue_free)


func aviso_audio(id: String) -> void:
	aviso("♪ " + NOMBRE_AUDIO.get(id, id), Color(0.7, 0.85, 1.0))


# ============================================================
# Caja de diálogo
# ============================================================

func _crear_caja() -> void:
	caja = PanelContainer.new()
	caja.position = Vector2(40, 250)
	caja.size = Vector2(560, 80)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.05, 0.07, 0.92)
	estilo.border_color = Color(0.6, 0.6, 0.65)
	estilo.set_border_width_all(1)
	estilo.set_content_margin_all(8)
	caja.add_theme_stylebox_override("panel", estilo)
	var v := VBoxContainer.new()
	caja.add_child(v)
	caja_hablante = Label.new()
	caja_hablante.add_theme_font_size_override("font_size", 10)
	v.add_child(caja_hablante)
	caja_texto = Label.new()
	caja_texto.add_theme_font_size_override("font_size", 12)
	caja_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja_texto.custom_minimum_size = Vector2(540, 0)
	v.add_child(caja_texto)
	caja_opciones = HBoxContainer.new()
	caja_opciones.add_theme_constant_override("separation", 40)
	caja_opciones.alignment = BoxContainer.ALIGNMENT_CENTER
	caja_opciones.visible = false
	v.add_child(caja_opciones)
	caja_pie = Label.new()
	caja_pie.text = "E / Espacio / click para seguir"
	caja_pie.add_theme_font_size_override("font_size", 8)
	caja_pie.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	caja_pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(caja_pie)
	caja.visible = false
	add_child(caja)


func dialogo_activo() -> bool:
	return caja.visible


## Agrega líneas a la cola y las muestra de a una.
func mostrar_lineas(lineas: Array) -> void:
	_cola.append_array(lineas)
	if not caja.visible:
		_siguiente()


func _siguiente() -> void:
	if _cola.is_empty():
		caja.visible = false
		dialogo_terminado.emit()
		return
	var l: Dictionary = _cola.pop_front()
	var h: String = l["hablante"]
	caja_hablante.text = NOMBRE_HABLANTE.get(h, h)
	# NORA en otro color (en greybox, su "voz").
	caja_hablante.add_theme_color_override("font_color", Color(0.45, 0.85, 0.95) if h == "NORA" else Color(0.9, 0.9, 0.9))
	caja_texto.text = l["texto"]
	caja.visible = true


func avanzar_dialogo() -> void:
	if caja.visible and not _pregunta:
		_siguiente()


# ---------------- preguntas con opciones ----------------

## Muestra una línea con opciones (←/→ o A/D para elegir, E/Enter/Espacio o click para confirmar).
## Emite respuesta(indice) al elegir.
func preguntar(linea: Dictionary, opciones: Array) -> void:
	_cola.clear()
	for b in caja_opciones.get_children():
		b.queue_free()
	# Cada opción: una marca ">" de ancho fijo (solo se prende la elegida) + el botón. El texto nunca se mueve.
	for i in opciones.size():
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 4)
		var marca := Label.new()
		marca.text = ">"
		marca.custom_minimum_size = Vector2(8, 0)
		marca.add_theme_font_size_override("font_size", 11)
		marca.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fila.add_child(marca)
		var b := Button.new()
		b.text = opciones[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 0)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func(): _elegir(i))
		b.mouse_entered.connect(func(): _seleccion = i; _marcar())
		fila.add_child(b)
		caja_opciones.add_child(fila)
	_cola.append(linea)
	_siguiente()
	_pregunta = true
	_seleccion = 0
	caja_opciones.visible = true
	caja_pie.text = "←/→ elegir · E / Enter confirmar"
	_marcar.call_deferred()


func pregunta_activa() -> bool:
	return _pregunta


func mover_seleccion(paso: int) -> void:
	var n := caja_opciones.get_child_count()
	_seleccion = posmod(_seleccion + paso, n)
	_marcar()


func confirmar_pregunta() -> void:
	_elegir(_seleccion)


func _marcar() -> void:
	for i in caja_opciones.get_child_count():
		var marca := caja_opciones.get_child(i).get_child(0) as Label
		marca.modulate.a = 1.0 if i == _seleccion else 0.0


func _elegir(i: int) -> void:
	if not _pregunta:
		return
	_pregunta = false
	caja_opciones.visible = false
	caja_pie.text = "E / Espacio / click para seguir"
	caja.visible = false
	respuesta.emit(i)


# ---------------- fundido a negro ----------------

func _crear_negro() -> void:
	negro = ColorRect.new()
	negro.color = Color.BLACK
	negro.size = Vector2(640, 360)
	negro.modulate.a = 0.0
	negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	negro_texto = Label.new()
	negro_texto.size = Vector2(640, 360)
	negro_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	negro_texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	negro_texto.add_theme_font_size_override("font_size", 16)
	negro.add_child(negro_texto)
	add_child(negro)


## Funde a negro (a = 1) o vuelve (a = 0). Devuelve el tween para esperarlo con await.
func fundido(a: float, texto := "", duracion := 0.8) -> Tween:
	negro_texto.text = texto
	var t := create_tween()
	t.tween_property(negro, "modulate:a", a, duracion)
	return t


# ============================================================
# Menú de pausa (Esc) — por ahora solo visual
# ============================================================

func _crear_menu() -> void:
	menu = ColorRect.new()
	menu.color = Color(0, 0, 0, 0.7)
	menu.size = Vector2(640, 360)
	var panel := PanelContainer.new()
	panel.position = Vector2(220, 80)
	panel.size = Vector2(200, 200)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.08, 0.08, 0.1)
	estilo.border_color = Color(0.6, 0.6, 0.65)
	estilo.set_border_width_all(1)
	estilo.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", estilo)
	menu.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var titulo := Label.new()
	titulo.text = "PAUSA"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(titulo)
	for par in [["Volver al juego", cerrar_menu], ["Guardar partida", func(): mostrar_mensaje("Guardar partida: próximamente.")],
			["Cargar partida", func(): mostrar_mensaje("Cargar partida: próximamente.")],
			["Opciones", func(): mostrar_mensaje("Opciones: próximamente.")], ["Salir", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = par[0]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(par[1])
		v.add_child(b)
	menu.visible = false
	add_child(menu)


func menu_abierto() -> bool:
	return menu.visible


func abrir_menu() -> void:
	menu.visible = true
	get_tree().paused = true
	(menu.get_child(0).get_child(0).get_child(1) as Button).grab_focus()


func cerrar_menu() -> void:
	menu.visible = false
	get_tree().paused = false
