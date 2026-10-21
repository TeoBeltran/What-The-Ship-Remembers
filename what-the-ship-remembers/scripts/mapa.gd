extends Control
## Mapa (paso 7, reglas de 01 sección 6). Tab lo abre y lo cierra (Esc también lo cierra). Semitransparente.
## Se mueve arrastrando con el mouse (cualquier botón) o con WASD / flechas.
## - Salas en las que nunca se entró: no aparecen (tampoco sus pasillos).
## - Visitadas en turnos anteriores pero no en este: oscurecidas.
## - Visitadas en este turno: se ven bien.
## - Marcas del jugador por turno (Pa / Pr / Ft): el juego no las valida. Click izquierdo las cicla; 1/2/3 las ponen, 0 borra.
## - Luz: mouse sobre una sala + rueda (o L) para subir o bajar. Muestra la capacidad usada y libre.
## - Nunca muestra el tiempo real de la sala ni anomalías.
## Coordenadas en 960x540 (la interfaz se escala sola, x2 a 1920x1080).

signal luz_pedida(sala: String, nivel: int)
signal mensaje(texto: String)

const MARCAS := ["", "Pa", "Pr", "Ft"]
const AREA := Rect2(60, 80, 840, 290)

const COLOR_HOY := Color(0.52, 0.54, 0.58, 0.92)
const COLOR_ANTES := Color(0.2, 0.2, 0.22, 0.88)
const COLOR_PASILLO_HOY := Color(0.4, 0.41, 0.44, 0.9)
const COLOR_PASILLO_ANTES := Color(0.16, 0.16, 0.18, 0.88)
const COLOR_LUZ_ON := Color(0.95, 0.85, 0.45)
const COLOR_LUZ_OFF := Color(0.12, 0.12, 0.14)
const COLOR_MARCA := Color(0.75, 0.9, 1.0)

var nave: Node2D
var personaje: Node2D
var nombres: Dictionary = {}
var hover := ""
var desplazamiento := Vector2.ZERO   # cuánto se movió el mapa (arrastre o WASD)

const VELOCIDAD_TECLAS := 330.0      # px por segundo (en coordenadas de 960x540)
const LIMITE := Vector2(480, 270)    # hasta dónde se puede alejar el mapa
const UMBRAL_CLICK := 4.0            # menos movimiento que esto = click (marca), no arrastre

var _arrastrando := false
var _boton := 0
var _movido := 0.0

var _escala := 8.0
var _origen := Vector2.ZERO
var _rects: Dictionary = {}    # sala -> Rect2 en el mapa
var _pasillos: Array = []      # [a, b, Rect2 en el mapa]


func _ready() -> void:
	size = Medidas.UI_BASE
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	for s in [Estado.luz_cambiada, Estado.sala_cambiada, Estado.turno_empezado, Estado.sala_desbloqueada]:
		s.connect(func(_a = null, _b = null): queue_redraw())


## La llama el juego al empezar: toma la forma de la nave (salas en tiles) y la encaja en el área del mapa.
func configurar(n: Node2D, p: Node2D, noms: Dictionary) -> void:
	nave = n
	personaje = p
	nombres = noms
	var tiles: Dictionary = {}
	var total := Rect2()
	var primero := true
	for c in nave.salas:
		var s = nave.salas[c]
		var r := Rect2(Vector2(s.pos_tiles), Vector2(s.ancho, s.alto))
		tiles[c] = r
		total = r if primero else total.merge(r)
		primero = false
	_escala = floorf(minf(AREA.size.x / total.size.x, AREA.size.y / total.size.y))
	_origen = AREA.position + (AREA.size - total.size * _escala) / 2.0 - total.position * _escala
	for c in tiles:
		_rects[c] = _a_mapa(tiles[c])
	_pasillos.clear()
	for p2 in nave.pasillos:
		var piso: Rect2 = p2["piso"]
		var r := Rect2(piso.position / Medidas.TILE, piso.size / Medidas.TILE)
		_pasillos.append([p2["a"], p2["b"], _a_mapa(r)])


func _a_mapa(r_tiles: Rect2) -> Rect2:
	return Rect2(_origen + r_tiles.position * _escala, r_tiles.size * _escala)


func abrir() -> void:
	visible = true
	hover = ""
	desplazamiento = Vector2.ZERO
	_arrastrando = false
	queue_redraw()


func cerrar() -> void:
	visible = false
	hover = ""
	_arrastrando = false


func se_muestra(sala: String) -> bool:
	return Estado.visitadas.has(sala)


func sala_bajo_mouse() -> String:
	var m := get_local_mouse_position() - desplazamiento
	for c in _rects:
		if se_muestra(c) and _rects[c].has_point(m):
			return c
	return ""


## Sala sobre la que actúan las teclas: la que está bajo el mouse, o la actual.
func sala_objetivo() -> String:
	return hover if hover != "" else Estado.sala_actual


func _process(delta: float) -> void:
	if not visible:
		return
	var dir := Vector2(
		_tecla(KEY_D, KEY_RIGHT) - _tecla(KEY_A, KEY_LEFT),
		_tecla(KEY_S, KEY_DOWN) - _tecla(KEY_W, KEY_UP))
	if dir != Vector2.ZERO:
		_mover(-dir.normalized() * VELOCIDAD_TECLAS * delta)  # D muestra lo que está a la derecha
	var h := sala_bajo_mouse()
	if h != hover:
		hover = h
	queue_redraw()  # el punto del personaje y el resaltado se actualizan en vivo


func _tecla(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _mover(cuanto: Vector2) -> void:
	desplazamiento = (desplazamiento + cuanto).clamp(-LIMITE, LIMITE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _arrastrando:
			_mover(event.relative)
			_movido += event.relative.length()
		accept_event()
		return
	if not event is InputEventMouseButton:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				cambiar_luz(hover, 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				cambiar_luz(hover, -1)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if event.pressed and not _arrastrando:
				_arrastrando = true
				_boton = event.button_index
				_movido = 0.0
			elif not event.pressed and event.button_index == _boton:
				_arrastrando = false
				# Click izquierdo sin arrastrar: cambia la marca de la sala.
				if _boton == MOUSE_BUTTON_LEFT and _movido < UMBRAL_CLICK and hover != "":
					ciclar_marca(hover)
	accept_event()


# ---------------- luz ----------------

func cambiar_luz(sala: String, paso: int) -> void:
	if sala == "":
		return
	luz_pedida.emit(sala, int(Estado.luz[sala]) + paso)


## Tecla L: sube un nivel; pasado el máximo posible (o sin capacidad), vuelve a apagada.
func ciclar_luz(sala: String) -> void:
	if sala == "":
		return
	var n := int(Estado.luz[sala]) + 1
	if n > Estado.luz_maxima(sala) or Estado.motivo_no_luz(sala, n) != "":
		n = 0
	luz_pedida.emit(sala, n)


# ---------------- marcas ----------------

func marcar(sala: String, marca: String) -> void:
	if sala == "":
		return
	if not Estado.visitadas_turno.has(sala):
		mensaje.emit("Todavía no entré a %s en este turno." % nombres.get(sala, sala).to_lower())
		return
	if marca == "":
		Estado.marcas.erase(sala)
	else:
		Estado.marcas[sala] = marca
	queue_redraw()


func ciclar_marca(sala: String) -> void:
	var i := MARCAS.find(Estado.marcas.get(sala, ""))
	marcar(sala, MARCAS[(i + 1) % MARCAS.size()])


# ---------------- dibujo ----------------

func _draw() -> void:
	var fuente := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	draw_string(fuente, Vector2(60, 66), "MAPA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.92))
	draw_string(fuente, Vector2(124, 66), "Turno %d" % Estado.turno, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.6, 0.64))

	# Todo lo de la nave se dibuja corrido según el desplazamiento; el pie queda fijo.
	draw_set_transform(desplazamiento)
	# Pasillos: solo entre salas que se muestran.
	for p in _pasillos:
		if se_muestra(p[0]) and se_muestra(p[1]):
			var hoy: bool = Estado.visitadas_turno.has(p[0]) and Estado.visitadas_turno.has(p[1])
			draw_rect(p[2], COLOR_PASILLO_HOY if hoy else COLOR_PASILLO_ANTES)

	for c in _rects:
		if not se_muestra(c):
			continue
		var r: Rect2 = _rects[c]
		var hoy := Estado.visitadas_turno.has(c)
		draw_rect(r, COLOR_HOY if hoy else COLOR_ANTES)
		var borde := Color(1, 1, 1, 0.95) if c == hover else Color(0.08, 0.08, 0.09)
		draw_rect(r, borde, false, 1.0)
		var texto_c := Color(0.08, 0.08, 0.1) if hoy else Color(0.55, 0.55, 0.58)
		draw_string(fuente, r.position + Vector2(6, 16), nombres.get(c, c), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 16, texto_c)
		# Luz: tres cuadritos abajo a la izquierda (× = no llega a ese nivel).
		var nivel := int(Estado.luz[c])
		var maximo := Estado.luz_maxima(c)
		for n in range(1, 4):
			var q := Rect2(r.position + Vector2(6 + (n - 1) * 12, r.size.y - 13), Vector2(9, 7))
			if n <= maximo:
				draw_rect(q, COLOR_LUZ_ON if n <= nivel else COLOR_LUZ_OFF)
			else:
				draw_rect(q, COLOR_LUZ_OFF, false, 1.0)
		# Marca del jugador (arriba a la derecha).
		var marca: String = Estado.marcas.get(c, "")
		if marca != "":
			var caja := Rect2(r.end.x - 30, r.position.y + 4, 26, 16)
			draw_rect(caja, Color(0.05, 0.08, 0.12, 0.9))
			draw_rect(caja, COLOR_MARCA, false, 1.0)
			draw_string(fuente, caja.position + Vector2(0, 13), marca, HORIZONTAL_ALIGNMENT_CENTER, caja.size.x, 16, COLOR_MARCA)

	# Dónde estoy.
	if personaje:
		var p := _origen + personaje.position / Medidas.TILE * _escala
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.WHITE)

	draw_set_transform(Vector2.ZERO)
	# Pie: capacidad y controles.
	var usada := Estado.capacidad_usada()
	var total := Estado.cfg("capacidad_luz")
	draw_string(fuente, Vector2(60, 390), "Capacidad de luz: %d / %d   (libre %d)" % [usada, total, total - usada], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_LUZ_ON)
	var ayuda := "Sala bajo el mouse: rueda / L luz · click o 1/2/3 marcar · 0 borrar   |   Arrastrar o WASD mover · Tab cerrar"
	draw_string(fuente, Vector2(60, 410), ayuda, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.6, 0.64))
	if hover != "":
		var info := "%s · luz %s" % [nombres.get(hover, hover), Estado.NOMBRES_LUZ[int(Estado.luz[hover])].to_lower()]
		if not Estado.visitadas_turno.has(hover):
			info += " · no entraste en este turno"
		draw_string(fuente, Vector2(60, 430), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 1.0))
