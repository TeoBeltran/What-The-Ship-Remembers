extends CanvasLayer
## Interfaz en greybox (pasos 3 a 5): estado arriba, caja de diálogo (con preguntas de opciones),
## avisos, indicación para interactuar, fundido a negro entre turnos y menú de pausa (Esc).
## Paso 6: panel de luz (L) para repartir la capacidad entre las salas (atajo; también se hace desde el mapa).
## Paso 7: barra de energía y mapa con Tab (scripts/mapa.gd).
## Paso 8: menú de NORA (opciones en lista), voz de NORA "de otro tiempo" (hablante NORA_OTRA)
##         y menú del personaje con Q (scripts/menu_personaje.gd).

signal dialogo_terminado
signal respuesta(indice: int)
signal luz_pedida(sala: String, nivel: int)  # el jugador quiere cambiar la luz desde el panel

const NOMBRE_HABLANTE := {"PERSONAJE": "Yo", "NORA": "NORA", "NORA_OTRA": "NORA"}

## Estilo de cada voz en greybox: color del nombre, color del texto y borde de la caja.
## NORA_OTRA = NORA hablando con datos de otro tiempo (01, sección 2.1): parecida, pero más "limpia".
## Es a propósito sutil: el jugador lo tiene que notar comparando, no por un cartel.
const VOCES := {
	"PERSONAJE": {"nombre": Color(0.9, 0.9, 0.9), "texto": Color(0.92, 0.92, 0.92), "borde": Color(0.6, 0.6, 0.65)},
	"NORA": {"nombre": Color(0.45, 0.85, 0.95), "texto": Color(0.72, 0.88, 0.92), "borde": Color(0.35, 0.6, 0.68)},
	"NORA_OTRA": {"nombre": Color(0.8, 0.97, 1.0), "texto": Color(1.0, 1.0, 1.0), "borde": Color(0.75, 0.92, 0.98)},
}
const CAJA_ABAJO := 330.0  # la caja de diálogo crece hacia arriba desde acá
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
var caja_opciones: BoxContainer
var negro: ColorRect
var negro_texto: Label
var mapa: Control
var menu_personaje: Control
var barra_energia: Control
var _estilo_caja: StyleBoxFlat

var _cola: Array = []          # líneas pendientes {hablante, texto}
var _tiempo_mensaje := 0.0
var _pregunta := false
var _seleccion := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# La interfaz está pensada a 640x360 y se agranda a la resolución real (1920x1080 → x3).
	var escala: float = get_viewport().get_visible_rect().size.y / Medidas.UI_BASE.y
	scale = Vector2(escala, escala)
	# El mapa va primero: los mensajes y el estado se dibujan por encima.
	mapa = preload("res://scripts/mapa.gd").new()
	add_child(mapa)
	menu_personaje = preload("res://scripts/menu_personaje.gd").new()
	add_child(menu_personaje)
	estado = _label(Vector2(8, 4), 12)
	_crear_barra_energia()
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
	_crear_panel_luz()
	_crear_negro()
	_crear_menu()


func _label(pos: Vector2, tam: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", tam)
	add_child(l)
	return l


func _process(delta: float) -> void:
	if caja.visible:
		_acomodar_caja()
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
	_estilo_caja = StyleBoxFlat.new()
	_estilo_caja.bg_color = Color(0.05, 0.05, 0.07, 0.92)
	_estilo_caja.border_color = Color(0.6, 0.6, 0.65)
	_estilo_caja.set_border_width_all(1)
	_estilo_caja.set_content_margin_all(8)
	caja.add_theme_stylebox_override("panel", _estilo_caja)
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
	caja_opciones = BoxContainer.new()  # horizontal (Sí / No) o vertical (menú de NORA)
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


## La caja queda apoyada abajo y crece hacia arriba según el contenido (se llama cada cuadro mientras se ve).
func _acomodar_caja() -> void:
	var alto := caja.get_combined_minimum_size().y
	caja.size = Vector2(560, alto)
	caja.position = Vector2(40, CAJA_ABAJO - alto)


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
	var voz: Dictionary = VOCES.get(h, VOCES["PERSONAJE"])
	caja_hablante.add_theme_color_override("font_color", voz["nombre"])
	caja_texto.add_theme_color_override("font_color", voz["texto"])
	_estilo_caja.border_color = voz["borde"]
	caja_texto.text = l["texto"]
	caja.visible = true
	_acomodar_caja()


func avanzar_dialogo() -> void:
	if caja.visible and not _pregunta:
		_siguiente()


# ---------------- preguntas con opciones ----------------

## Muestra una línea con opciones (←/→ o A/D para elegir, E/Enter/Espacio o click para confirmar).
## Emite respuesta(indice) al elegir.
## vertical = true: una opción debajo de la otra (para listas largas, como el menú de NORA).
func preguntar(linea: Dictionary, opciones: Array, vertical := false) -> void:
	_cola.clear()
	caja_opciones.vertical = vertical
	caja_opciones.alignment = BoxContainer.ALIGNMENT_BEGIN if vertical else BoxContainer.ALIGNMENT_CENTER
	caja_opciones.add_theme_constant_override("separation", 1 if vertical else 40)
	for b in caja_opciones.get_children():
		caja_opciones.remove_child(b)  # sacarlas ya: si no, _marcar las cuenta hasta el cuadro siguiente
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
		if vertical:
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _elegir(i))
		b.mouse_entered.connect(func(): _seleccion = i; _marcar())
		fila.add_child(b)
		caja_opciones.add_child(fila)
	_cola.append(linea)
	_siguiente()
	_pregunta = true
	_seleccion = 0
	caja_opciones.visible = true
	caja_pie.text = ("↑/↓" if vertical else "←/→") + " elegir · E / Enter confirmar"
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


# ============================================================
# Panel de luz (L) — paso 6
# ============================================================
# Una fila por sala desbloqueada: tres cuadritos (nivel), lleno = encendido, vacío = se puede,
# tachado = esa sala no llega (falta un arreglo o es su máximo en el Alfa).
# ↑/↓ (W/S) elige sala · ←/→ (A/D) baja o sube · click en un cuadrito · L o Esc cierra.

const COLOR_LUZ_ON := Color(0.95, 0.85, 0.45)
const COLOR_LUZ_OFF := Color(0.25, 0.25, 0.28)
const COLOR_LUZ_NO := Color(0.12, 0.12, 0.13)

var panel_luz: PanelContainer
var _luz_filas: VBoxContainer
var _luz_capacidad: Label
var _luz_salas: Array = []      # códigos de las salas que se muestran, en orden
var _luz_nombres: Dictionary = {}
var _luz_sel := 0


func _crear_panel_luz() -> void:
	panel_luz = PanelContainer.new()
	panel_luz.position = Vector2(420, 40)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.05, 0.07, 0.94)
	estilo.border_color = Color(0.6, 0.6, 0.65)
	estilo.set_border_width_all(1)
	estilo.set_content_margin_all(8)
	panel_luz.add_theme_stylebox_override("panel", estilo)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel_luz.add_child(v)
	var titulo := Label.new()
	titulo.text = "LUZ DE LA NAVE"
	titulo.add_theme_font_size_override("font_size", 11)
	v.add_child(titulo)
	_luz_filas = VBoxContainer.new()
	_luz_filas.add_theme_constant_override("separation", 3)
	v.add_child(_luz_filas)
	_luz_capacidad = Label.new()
	_luz_capacidad.add_theme_font_size_override("font_size", 10)
	v.add_child(_luz_capacidad)
	var pie := Label.new()
	pie.text = "↑/↓ sala · ←/→ luz · L cerrar"
	pie.add_theme_font_size_override("font_size", 8)
	pie.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	v.add_child(pie)
	panel_luz.visible = false
	add_child(panel_luz)


func luz_abierta() -> bool:
	return panel_luz.visible


func abrir_luz(nombres: Dictionary) -> void:
	_luz_nombres = nombres
	_luz_salas.clear()
	for s in Estado.salas:
		if Estado.desbloqueadas.has(s) and Estado.visitadas.has(s):  # no revela salas donde nunca entró
			_luz_salas.append(s)
	_luz_salas.sort_custom(func(a, b): return int(Estado.salas[a]["numero"]) < int(Estado.salas[b]["numero"]))
	_luz_sel = maxi(_luz_salas.find(Estado.sala_actual), 0)
	panel_luz.visible = true
	refrescar_luz()


func cerrar_luz() -> void:
	panel_luz.visible = false


func mover_seleccion_luz(paso: int) -> void:
	if _luz_salas.is_empty():
		return
	_luz_sel = posmod(_luz_sel + paso, _luz_salas.size())
	refrescar_luz()


## Pide subir (+1) o bajar (-1) la luz de la sala elegida.
func cambiar_luz(paso: int) -> void:
	if _luz_salas.is_empty():
		return
	var s: String = _luz_salas[_luz_sel]
	luz_pedida.emit(s, int(Estado.luz[s]) + paso)


func refrescar_luz() -> void:
	if not panel_luz.visible:
		return
	for f in _luz_filas.get_children():
		_luz_filas.remove_child(f)
		f.queue_free()
	for i in _luz_salas.size():
		var s: String = _luz_salas[i]
		var nivel := int(Estado.luz[s])
		var maximo := Estado.luz_maxima(s)
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 4)
		var marca := Label.new()
		marca.text = ">" if i == _luz_sel else ""
		marca.custom_minimum_size = Vector2(8, 0)
		marca.add_theme_font_size_override("font_size", 10)
		fila.add_child(marca)
		var nombre := Label.new()
		nombre.text = _luz_nombres.get(s, s)
		nombre.custom_minimum_size = Vector2(92, 0)
		nombre.add_theme_font_size_override("font_size", 10)
		if s == Estado.sala_actual:
			nombre.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		fila.add_child(nombre)
		for n in range(1, 4):
			var c := ColorRect.new()
			c.custom_minimum_size = Vector2(10, 8)
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			c.color = COLOR_LUZ_ON if n <= nivel else (COLOR_LUZ_OFF if n <= maximo else COLOR_LUZ_NO)
			if n > maximo:
				var x := Label.new()  # tachado: esa sala no llega a este nivel
				x.text = "×"
				x.add_theme_font_size_override("font_size", 8)
				x.add_theme_color_override("font_color", Color(0.4, 0.4, 0.42))
				x.position = Vector2(2, -3)
				c.add_child(x)
			var sala_c := s
			var nivel_c := n
			c.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_luz_sel = _luz_salas.find(sala_c)
					# click en el nivel que ya tiene: lo baja uno (así se puede apagar)
					luz_pedida.emit.call_deferred(sala_c, nivel_c if int(Estado.luz[sala_c]) != nivel_c else nivel_c - 1))
			fila.add_child(c)
		var texto := Label.new()
		texto.text = Estado.NOMBRES_LUZ[nivel]
		texto.add_theme_font_size_override("font_size", 9)
		texto.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
		fila.add_child(texto)
		_luz_filas.add_child(fila)
	var usada := Estado.capacidad_usada()
	var total := Estado.cfg("capacidad_luz")
	_luz_capacidad.text = "Capacidad: %d / %d   (libre %d)" % [usada, total, total - usada]


# ============================================================
# Barra de energía (paso 7)
# ============================================================
# Un segmento por punto de energía del turno, debajo del texto de estado.

func _crear_barra_energia() -> void:
	barra_energia = Control.new()
	barra_energia.position = Vector2(8, 20)
	barra_energia.size = Vector2(150, 5)
	barra_energia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(barra_energia)
	barra_energia.draw.connect(func():
		var maximo := maxi(Estado.cfg("energia_por_turno"), 1)
		var ancho := barra_energia.size.x / maximo
		for i in maximo:
			var lleno := i < Estado.energia
			var c := Color(0.45, 0.85, 0.95) if lleno else Color(0.18, 0.2, 0.22)
			if lleno and Estado.energia <= 3:
				c = Color(0.95, 0.55, 0.35)  # poca energía
			barra_energia.draw_rect(Rect2(i * ancho, 0, ancho - 1, barra_energia.size.y), c))
	Estado.energia_cambiada.connect(func(_e): barra_energia.queue_redraw())
	Estado.turno_empezado.connect(func(_t): barra_energia.queue_redraw())
