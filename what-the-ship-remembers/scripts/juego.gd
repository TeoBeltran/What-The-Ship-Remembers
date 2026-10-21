extends Node2D
## Escena principal: la nave continua, el personaje, la cámara y la interfaz.
## Paso 3: movimiento (flechas/WASD o click derecho), cobro al entrar a otra sala, zoom.
## Paso 4: objetos e interacción (E, o click derecho sobre un objeto), textos, avisos.
##
## Controles: E interactuar · ruedita / I / O zoom · Esc menú
## Depuración (provisoria): F1 info e IDs · F2 abrir sala común · F3 recargar energía
##                          F4 turno siguiente · F5 cambiar la luz de la sala actual

const NOMBRES := {"MAN": "Sala de mando", "COM": "Comunicaciones", "SCO": "Sala común", "PTA": "Sala de la puerta"}
const ZOOMS := [0.75, 1.0, 1.5, 2.0]
const ALCANCE := 14.0  # px alrededor de un objeto para poder interactuar

var depuracion := false
var _zoom_i := 1
var _pendiente = null  # objeto al que se va caminando para interactuar (click derecho)

@onready var nave: Node2D = $Nave
@onready var personaje: CharacterBody2D = $Personaje
@onready var camara: Camera2D = $Camara
@onready var ui: CanvasLayer = $Interfaz


func _ready() -> void:
	Estado.energia_cambiada.connect(func(_e): _actualizar_hud())
	Estado.sala_cambiada.connect(func(_s): _actualizar_hud())
	Estado.turno_empezado.connect(func(_t): _empezar_turno())
	Estado.texto_mostrado.connect(func(_id, lineas): ui.mostrar_lineas(lineas))
	Estado.anotacion_agregada.connect(func(_id): ui.aviso("Añadido a las anotaciones"))
	Estado.item_agregado.connect(func(id): ui.aviso("Guardado: " + str(Estado.items.get(id, {}).get("nombre", id))))
	Estado.audio_reproducido.connect(ui.aviso_audio)
	nave.aviso.connect(ui.mostrar_mensaje)
	Estado.nueva_partida()


## Cada turno empieza en el centro de la sala de mando.
func _empezar_turno() -> void:
	personaje.detener()
	_pendiente = null
	personaje.position = nave.centro_de("MAN")
	camara.position = personaje.position
	camara.reset_smoothing()
	_actualizar_hud()


func _physics_process(_delta: float) -> void:
	personaje.bloqueado = ui.dialogo_activo()
	# ¿Entró a otra sala? (en los pasillos no se cambia de sala)
	var sala: String = nave.sala_en(personaje.position)
	if sala != "" and sala != Estado.sala_actual:
		if not Estado.mover_a(sala):
			personaje.detener()
			personaje.position = nave.centro_de(Estado.sala_actual)
	# Llegó caminando al objeto que se clickeó.
	if _pendiente != null and personaje.ruta.is_empty():
		var obj = _pendiente
		_pendiente = null
		if obj.rect_global().grow(ALCANCE + 4).has_point(personaje.position):
			_interactuar_con(obj)


func _process(_delta: float) -> void:
	camara.position = personaje.position
	_actualizar_indicacion()


# ============================================================
# Interacción
# ============================================================

## Objeto visible más cercano al alcance del personaje (en la sala actual).
func objeto_cercano():
	var mejor = null
	var mejor_d := INF
	for obj in nave.salas[Estado.sala_actual].objetos_nodos:
		if not obj.se_ve():
			continue
		var r: Rect2 = obj.rect_global()
		if r.grow(ALCANCE).has_point(personaje.position):
			var d := r.get_center().distance_to(personaje.position)
			if d < mejor_d:
				mejor = obj
				mejor_d = d
	return mejor


func _interactuar_con(obj) -> void:
	var id: String = obj.id_usable()
	if id != "":
		Estado.interactuar(id)
		return
	var pendiente: String = obj.id_visible_pendiente()
	if pendiente == "":
		ui.mostrar_mensaje("No hay nada más para hacer acá." if not obj.es_consola else "NORA no tiene nada nuevo para decir.")
	else:
		ui.mostrar_mensaje("No puedo: " + Estado.motivo_no_usable(pendiente) + ".")


func _actualizar_indicacion() -> void:
	if ui.dialogo_activo() or ui.menu_abierto():
		ui.indicacion.text = ""
		return
	var obj = objeto_cercano()
	if obj == null:
		ui.indicacion.text = ""
		return
	var id: String = obj.id_usable()
	if id != "":
		var costo: int = Estado.costo_interaccion(id)
		ui.indicacion.text = ("E: hablar con NORA" if obj.es_consola else "E: investigar") + ("" if costo == 0 else " (%d)" % costo)
	elif obj.id_visible_pendiente() != "":
		ui.indicacion.text = "E: investigar (sin energía)"
	else:
		ui.indicacion.text = ""


## Objeto visible bajo un punto de la nave (para el click derecho).
func _objeto_en(punto: Vector2):
	for obj in nave.salas[Estado.sala_actual].objetos_nodos:
		if obj.se_ve() and obj.rect_global().grow(2).has_point(punto):
			return obj
	return null


# ============================================================
# HUD
# ============================================================

func _actualizar_hud() -> void:
	var sala: String = Estado.sala_actual
	ui.estado.text = "Turno %d    Energía %d/%d    %s" % [
		Estado.turno, Estado.energia, Estado.cfg("energia_por_turno"), NOMBRES.get(sala, sala)]
	if depuracion:
		ui.depuracion.text = "[DEPURACIÓN] Tiempo: %s · Luz: %d · Capacidad %d/%d · F2 abrir sala común · F3 energía · F4 turno · F5 luz" % [
			Estado.tiempo_de(sala), Estado.luz[sala], Estado.capacidad_usada(), Estado.cfg("capacidad_luz")]
	else:
		ui.depuracion.text = "E interactuar · Click derecho moverse · Ruedita/I/O zoom · Esc menú · F1 depuración"


func _set_depuracion(valor: bool) -> void:
	depuracion = valor
	for c in nave.salas:
		for obj in nave.salas[c].objetos_nodos:
			obj.mostrar_id = valor
			obj.queue_redraw()


# ============================================================
# Zoom
# ============================================================

func _zoom(paso: int) -> void:
	_zoom_i = clampi(_zoom_i + paso, 0, ZOOMS.size() - 1)
	var z: float = ZOOMS[_zoom_i]
	create_tween().tween_property(camara, "zoom", Vector2(z, z), 0.15)


# ============================================================
# Entrada
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	# Menú de pausa
	if event.is_action_pressed("ui_cancel"):
		if ui.menu_abierto():
			ui.cerrar_menu()
		else:
			ui.abrir_menu()
		get_viewport().set_input_as_handled()
		return
	if ui.menu_abierto():
		return
	# Diálogo abierto: E / Espacio / Enter / click lo avanzan
	if ui.dialogo_activo():
		if (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]) \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			ui.avanzar_dialogo()
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				var punto := get_global_mouse_position()
				var obj = _objeto_en(punto)
				if obj and obj.rect_global().grow(ALCANCE).has_point(personaje.position):
					personaje.detener()
					_interactuar_con(obj)
					return
				_pendiente = obj
				var destino: Vector2 = punto if obj == null else obj.rect_global().get_center()
				personaje.seguir(nave.camino(personaje.position, destino))
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(-1)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_E:
			var obj = objeto_cercano()
			if obj:
				personaje.detener()
				_interactuar_con(obj)
		KEY_I:
			_zoom(1)
		KEY_O:
			_zoom(-1)
		KEY_F1:
			_set_depuracion(not depuracion)
		KEY_F2:
			Estado.desbloquear("SCO")
			ui.mostrar_mensaje("[Depuración] Sala común desbloqueada.")
		KEY_F3:
			Estado.energia = Estado.cfg("energia_por_turno")
			Estado.energia_cambiada.emit(Estado.energia)
			ui.mostrar_mensaje("[Depuración] Energía recargada.")
		KEY_F4:
			if Estado.turno < Estado.cfg("turnos_alfa"):
				Estado.empezar_turno()
				ui.mostrar_mensaje("[Depuración] Turno %d." % Estado.turno)
			else:
				ui.mostrar_mensaje("[Depuración] Ya es el último turno del Alfa.")
		KEY_F5:
			_ciclar_luz()
		_:
			return
	_actualizar_hud()


## Depuración: sube la luz de la sala actual (vuelve a 0 después del máximo). La luz real llega en el paso 6.
func _ciclar_luz() -> void:
	var s: String = Estado.sala_actual
	var nivel: int = (int(Estado.luz[s]) + 1) % (Estado.luz_maxima(s) + 1)
	if Estado.set_luz(s, nivel):
		ui.mostrar_mensaje("[Depuración] Luz de %s: %d (capacidad %d/%d)." % [s, nivel, Estado.capacidad_usada(), Estado.cfg("capacidad_luz")])
	else:
		ui.mostrar_mensaje("[Depuración] No se pudo: " + Estado.motivo_no_luz(s, nivel) + ". Bajá la luz de otra sala.")
