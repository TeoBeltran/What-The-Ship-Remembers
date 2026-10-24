extends Node2D
## Escena principal: la nave continua, el personaje, la cámara y la interfaz.
## Paso 3: movimiento (flechas/WASD o click derecho), cobro al entrar a otra sala, zoom.
## Paso 4: objetos e interacción (E, o click derecho sobre un objeto), textos, avisos.
## Paso 5: interacciones forzadas como cinemática (camina solo hasta el objeto y recién ahí habla),
##         descansar hablando con NORA (cuando no tiene nada nuevo) y fin de turno al quedarse sin energía.
## Paso 6: luz. Panel con L para repartir la capacidad; oscuridad por sala.
## Paso 7: mapa manteniendo Tab (luz con la rueda o L, marcas Pa/Pr/Ft) y barra de energía.
## Paso 8: consola de NORA con menú de temas (conversaciones disponibles, descansar, nada por ahora)
##         y menú del personaje con Q (anotaciones, conversaciones con NORA, inventario).
## Paso 9: cierre del Alfa. En el T12, COM_T (las dos pinzas) dispara el evento cierre_alfa: el personaje
##         camina solo hasta la consola de NORA y salen los diálogos encadenados T_CIERRE_*. Si el T12 termina
##         sin eso (descansar o sin energía), el cierre sale igual, ahí donde esté.
##
## Controles: E interactuar · Tab mapa · Q anotaciones · L luz · ruedita / I / O zoom · Esc menú
## Pantalla: F11 pantalla completa
## Depuración (provisoria): F1 info e IDs · F2 abrir sala común · F3 recargar energía
##                          F4 turno siguiente · F5 cambiar la luz de la sala actual

const NOMBRES := {"MAN": "Sala de mando", "COM": "Comunicaciones", "SCO": "Sala común", "PTA": "Sala de la puerta"}
const ZOOMS := [0.75, 1.0, 1.5, 2.0]
const ZOOM_INICIAL := 1  # x1 (el arte ya se dibuja al doble: Medidas.ARTE)
const E := Medidas.ESCALA
const ALCANCE := 14.0 * E  # px alrededor de un objeto para poder interactuar

var depuracion := false
var _zoom_i := ZOOM_INICIAL
var _pendiente = null  # objeto al que se va caminando para interactuar (click derecho)
var _cinematica := ""  # id de la interacción forzada hacia la que camina solo
var _fin_turno := false  # durante el texto y el fundido a negro entre turnos
var _alfa_terminado := false
var _cierre := ""  # paso 9: "" · "esperar" (termina el diálogo de COM_T) · "caminar" (va solo a NORA) · "hablando"
var _ultima_pos := Vector2.ZERO  # última posición dentro de la sala actual (para volver si no puede pasar)
var _opciones_nora: Array = []  # lo que significa cada opción de la pregunta abierta: id de conversación, "descansar" o "nada"

@onready var nave: Node2D = $Nave
@onready var personaje: CharacterBody2D = $Personaje
@onready var camara: Camera2D = $Camara
@onready var ui: CanvasLayer = $Interfaz


func _ready() -> void:
	camara.zoom = Vector2.ONE * ZOOMS[_zoom_i]
	Estado.energia_cambiada.connect(func(_e): _actualizar_hud())
	Estado.sala_cambiada.connect(func(_s): _actualizar_hud())
	Estado.turno_empezado.connect(func(_t): _empezar_turno())
	Estado.texto_mostrado.connect(func(_id, lineas): ui.mostrar_lineas(lineas))
	Estado.anotacion_agregada.connect(func(_id): ui.aviso("Añadido a las anotaciones"))
	Estado.item_agregado.connect(func(id): ui.aviso("Guardado: " + str(Estado.items.get(id, {}).get("nombre", id))))
	Estado.audio_reproducido.connect(ui.aviso_audio)
	nave.aviso.connect(ui.mostrar_mensaje)
	ui.respuesta.connect(_on_respuesta)
	ui.luz_pedida.connect(_on_luz_pedida)
	ui.mapa.luz_pedida.connect(_on_luz_pedida)
	ui.mapa.mensaje.connect(ui.mostrar_mensaje)
	ui.mapa.configurar(nave, personaje, NOMBRES)
	Estado.luz_cambiada.connect(func(_s, _n): _actualizar_hud(); ui.refrescar_luz())
	Estado.evento_especial.connect(func(id):
		if id == "arreglo_panel":
			ui.aviso("Mando y comunicaciones ya pueden llegar a luz máxima")
			ui.aviso("Energía del traje: %d por turno" % Estado.energia_maxima())
		elif id == "cierre_alfa":
			_cierre = "esperar")
	Estado.forzadas_automaticas = false  # las forzadas se hacen como cinemática (ver _physics_process)
	Estado.nueva_partida()


## Cada turno empieza en el centro de la sala de mando.
func _empezar_turno() -> void:
	personaje.detener()
	personaje.cinematica = false
	_pendiente = null
	_cinematica = ""
	personaje.position = nave.centro_de("MAN")
	_ultima_pos = personaje.position
	camara.position = personaje.position
	camara.reset_smoothing()
	_actualizar_hud()


func _physics_process(_delta: float) -> void:
	personaje.bloqueado = ui.dialogo_activo() or _fin_turno or ui.luz_abierta() or ui.mapa.visible or ui.menu_personaje.visible
	# ¿Entró a otra sala? (en los pasillos no se cambia de sala)
	nave.poner_vista(personaje.position)
	var sala: String = nave.sala_en(personaje.position)
	if sala != "" and sala != Estado.sala_actual:
		if not Estado.mover_a(sala):
			personaje.detener()
			personaje.position = _ultima_pos
	elif sala == Estado.sala_actual:
		_ultima_pos = personaje.position
	# Llegó caminando al objeto que se clickeó.
	if _pendiente != null and personaje.ruta.is_empty():
		var obj = _pendiente
		_pendiente = null
		if obj.rect_global().grow(ALCANCE + 4 * E).has_point(personaje.position):
			_interactuar_con(obj)
	if ui.dialogo_activo() or ui.menu_abierto() or ui.luz_abierta() or ui.mapa.visible or ui.menu_personaje.visible or _fin_turno or _alfa_terminado:
		return
	# Cierre del Alfa (paso 9): cuando termina el diálogo de las pinzas, camina solo hasta NORA.
	if _cierre != "":
		_avanzar_cierre()
		return
	# Cinemática en curso: cuando llega (o se traba), recién ahí se dispara la interacción forzada.
	if _cinematica != "":
		if personaje.ruta.is_empty():
			_terminar_cinematica()
		return
	var forzada := Estado.siguiente_forzada()
	if forzada != "":
		_empezar_cinematica(forzada)
	elif Estado.energia <= 0:
		_terminar_turno(Estado.textos.get("SIS_SIN_ENERGIA", []))


# ============================================================
# Cinemáticas (interacciones forzadas) y fin de turno
# ============================================================

func _nodo_de(id: String):
	for n in nave.salas[Estado.objetos[id]["sala"]].objetos_nodos:
		if n.ids.has(id):
			return n
	return null


func _empezar_cinematica(id: String) -> void:
	_cinematica = id
	_pendiente = null
	personaje.cinematica = true
	var n = _nodo_de(id)
	if n == null:
		personaje.detener()
		return
	var r: Rect2 = n.rect_global()
	if r.grow(ALCANCE).has_point(personaje.position):
		personaje.detener()  # ya está al lado
	else:
		personaje.seguir(_camino_a_objeto(r), r, ALCANCE - 3 * E)


## Camino hasta el lugar libre más cercano al objeto y, al final, derecho hacia el objeto
## (así llega aunque esté sobre una mesa o entre sillas). El personaje se frena apenas lo alcanza.
func _camino_a_objeto(r: Rect2) -> PackedVector2Array:
	var ruta: PackedVector2Array = nave.camino_a_rect(personaje.position, r)
	ruta.append(r.get_center())
	return ruta


func _terminar_cinematica() -> void:
	var id := _cinematica
	_cinematica = ""
	personaje.cinematica = false
	personaje.detener()
	if not Estado.interactuar(id):
		# Si dejó de verse (por ejemplo, se bajó la luz), no se pierde: se hace cuando se vuelva a ver.
		if Estado.se_ve(id) and Estado.objetos[id]["sala"] == Estado.sala_actual:
			push_warning("No se pudo hacer la forzada %s: %s" % [id, Estado.motivo_no_usable(id)])
			Estado.obj[id]["usado"] = true  # para no quedar en un bucle


## Texto (opcional) → negro → turno siguiente en la sala de mando. En el último turno, fin del Alfa.
func _terminar_turno(lineas: Array) -> void:
	_fin_turno = true
	_pendiente = null
	personaje.detener()
	if not lineas.is_empty():
		ui.mostrar_lineas(lineas)
		await ui.dialogo_terminado
	if Estado.es_ultimo_turno():
		_jugar_cierre()
		return
	await ui.fundido(1.0, "Turno %d" % (Estado.turno + 1)).finished
	await get_tree().create_timer(0.6).timeout
	Estado.empezar_turno()
	await ui.fundido(0.0, "Turno %d" % Estado.turno).finished
	_fin_turno = false


# ============================================================
# Cierre del Alfa (paso 9)
# ============================================================

func _consola():
	for n in nave.salas["MAN"].objetos_nodos:
		if n.es_consola:
			return n
	return null


func _avanzar_cierre() -> void:
	match _cierre:
		"esperar":
			_cierre = "caminar"
			_pendiente = null
			personaje.cinematica = true
			var c = _consola()
			if c == null:
				personaje.detener()
			else:
				personaje.seguir(_camino_a_objeto(c.rect_global()), c.rect_global(), ALCANCE - 3 * E)
		"caminar":
			if personaje.ruta.is_empty():
				personaje.cinematica = false
				personaje.detener()
				_jugar_cierre()


## Diálogos encadenados del cierre y fin del Alfa. Si ya sabe que hay dos pinzas, habla de eso;
## si no (nunca volvió a comunicaciones), la versión general.
func _jugar_cierre() -> void:
	_cierre = "hablando"
	_fin_turno = true
	_pendiente = null
	personaje.detener()
	var sabe_dos := false
	for id in ["COM_T", "COM_S", "COM_M"]:
		if Estado.obj.has(id) and Estado.obj[id]["usado"]:
			sabe_dos = true
	if not (Estado.obj.has("COM_T") and Estado.obj["COM_T"]["usado"]):
		ui.aviso_audio("musica_cierre")
	var lineas: Array = []
	lineas.append_array(Estado.textos.get("T_CIERRE_PINZA" if sabe_dos else "T_CIERRE_GENERAL", []))
	lineas.append_array(Estado.textos.get("T_CIERRE_FIN", []))
	ui.mostrar_lineas(lineas)
	await ui.dialogo_terminado
	_alfa_terminado = true
	await ui.fundido(1.0, "Fin del Alfa\n\nGracias por jugar.\nEsc para salir", 2.0).finished


# ============================================================
# Consola de NORA (paso 8)
# ============================================================
# Con temas nuevos: menú con un tema por conversación disponible + Descansar + Nada por ahora.
# Sin temas: "No tengo nada nuevo para informarle. ¿Desea descansar?" (Sí / Todavía no).
# En el turno 1 no se puede descansar: sin "Descansar" en el menú, y sin temas solo "No tengo nada nuevo".
# Al terminar una conversación elegida, si quedan temas, el menú vuelve solo.

func _linea_sistema(id: String, por_defecto: String) -> Dictionary:
	var lineas: Array = Estado.textos.get(id, [])
	return lineas[-1] if not lineas.is_empty() else {"hablante": "NORA", "texto": por_defecto}


## En el turno 1 no se puede descansar (pedido del usuario): no aparece la opción.
func _se_puede_descansar() -> bool:
	return Estado.turno > 1


func _hablar_con_nora() -> void:
	var temas := Estado.conversaciones_disponibles()
	if temas.is_empty() and not _se_puede_descansar():
		_opciones_nora = []
		ui.mostrar_lineas([_linea_sistema("SIS_NORA_SIN_DESCANSO", "No tengo nada nuevo para informarle.")])
		return
	if temas.is_empty():
		_opciones_nora = ["descansar", "nada"]
		ui.preguntar(_linea_sistema("SIS_DESCANSAR_PREGUNTA", "No tengo nada nuevo para informarle. ¿Desea descansar?"),
			["Sí, descansar", "Todavía no"])
		return
	_opciones_nora = temas.duplicate()
	var textos: Array = []
	for id in temas:
		textos.append(Estado.tema_de(id))
	if _se_puede_descansar():
		_opciones_nora.append("descansar")
		textos.append("Descansar (terminar el turno)")
	_opciones_nora.append("nada")
	textos.append("Nada por ahora")
	ui.preguntar(_linea_sistema("SIS_NORA_MENU", "¿En qué puedo ayudarle?"), textos, true)


func _on_respuesta(indice: int) -> void:
	var eleccion: String = _opciones_nora[indice] if indice < _opciones_nora.size() else "nada"
	_opciones_nora = []
	match eleccion:
		"descansar":
			_terminar_turno(Estado.textos.get("SIS_DESCANSAR_SI", []))
		"nada":
			pass
		_:
			if Estado.interactuar(eleccion):
				await ui.dialogo_terminado
				if not Estado.conversaciones_disponibles().is_empty() and not _fin_turno:
					_hablar_con_nora()


func _process(_delta: float) -> void:
	camara.position = personaje.position
	# La oscuridad de la sala también oscurece al personaje (en los pasillos no hay oscuridad).
	var oscuro := 0.0
	if nave.salas.has(nave.vista):
		oscuro = nave.salas[nave.vista].alfa_oscuridad_actual()
	personaje.modulate = Color(1.0 - oscuro, 1.0 - oscuro, 1.0 - oscuro)
	# El mapa se cierra solo si aparece un diálogo, el menú o el cambio de turno.
	if ui.mapa.visible and (ui.dialogo_activo() or ui.menu_abierto() or _fin_turno or _alfa_terminado):
		ui.mapa.cerrar()
	_actualizar_indicacion()


# ============================================================
# Interacción
# ============================================================

## Objeto visible más cercano al alcance del personaje (en la sala actual).
## Prefiere los que todavía tienen algo para hacer (NORA siempre: conversación o descansar),
## así un objeto ya usado no tapa a otro que está al lado.
func objeto_cercano():
	var mejor = null
	var mejor_d := INF
	for obj in nave.salas[Estado.sala_actual].objetos_nodos:
		if not obj.se_ve():
			continue
		var r: Rect2 = obj.rect_global()
		if r.grow(ALCANCE).has_point(personaje.position):
			var d := r.get_center().distance_to(personaje.position)
			if not (obj.es_consola or obj.id_usable() != "" or obj.id_visible_pendiente() != ""):
				d += 1000.0  # ya no hay nada para hacer: solo si no hay otro
			if d < mejor_d:
				mejor = obj
				mejor_d = d
	return mejor


func _interactuar_con(obj) -> void:
	if obj.es_consola:
		_hablar_con_nora()
		return
	var id: String = obj.id_usable()
	if id != "":
		Estado.interactuar(id)
		return
	var pendiente: String = obj.id_visible_pendiente()
	if pendiente == "":
		ui.mostrar_mensaje("No hay nada más para hacer acá." if not obj.es_consola else "NORA no tiene nada nuevo para decir.")
	else:
		ui.mostrar_mensaje("No puedo investigar %s: %s." % [obj.nombre(), Estado.motivo_no_usable(pendiente)])


func _actualizar_indicacion() -> void:
	if ui.dialogo_activo() or ui.menu_abierto() or ui.luz_abierta() or ui.mapa.visible or ui.menu_personaje.visible or _fin_turno or _cinematica != "" or _cierre != "":
		ui.indicacion.text = ""
		return
	var obj = objeto_cercano()
	if obj == null:
		ui.indicacion.text = ""
		return
	if obj.es_consola:
		var nuevos := Estado.conversaciones_disponibles().size()
		ui.indicacion.text = "E: hablar con NORA" + ("" if nuevos == 0 else " (%d %s)" % [nuevos, "tema nuevo" if nuevos == 1 else "temas nuevos"])
		return
	var id: String = obj.id_usable()
	if id != "":
		var costo: int = Estado.costo_interaccion(id)
		ui.indicacion.text = "E: investigar " + obj.nombre() + ("" if costo == 0 else " (%d)" % costo)
	elif obj.id_visible_pendiente() != "":
		var costo: int = Estado.costo_interaccion(obj.id_visible_pendiente())
		ui.indicacion.text = "E: investigar %s (%d) — no alcanza la energía" % [obj.nombre(), costo]
	else:
		ui.indicacion.text = ""


## Objeto visible bajo un punto de la nave (para el click derecho).
func _objeto_en(punto: Vector2):
	for obj in nave.salas[Estado.sala_actual].objetos_nodos:
		if obj.se_ve() and obj.rect_global().grow(2 * E).has_point(punto):
			return obj
	return null


# ============================================================
# HUD
# ============================================================

func _actualizar_hud() -> void:
	var sala: String = Estado.sala_actual
	ui.estado.text = "Turno %d    Energía %d/%d    %s    Luz %s    Capacidad %d/%d" % [
		Estado.turno, Estado.energia, Estado.energia_maxima(), NOMBRES.get(sala, sala),
		Estado.NOMBRES_LUZ[int(Estado.luz[sala])].to_lower(), Estado.capacidad_usada(), Estado.cfg("capacidad_luz")]
	if depuracion:
		ui.depuracion.text = "[DEPURACIÓN] Tiempo: %s · Luz: %d · Capacidad %d/%d · F2 abrir sala común · F3 energía · F4 turno · F5 luz" % [
			Estado.tiempo_de(sala), Estado.luz[sala], Estado.capacidad_usada(), Estado.cfg("capacidad_luz")]
	else:
		ui.depuracion.text = "E interactuar · Click derecho moverse · Tab mapa · Q anotaciones · L luz · Ruedita/I/O zoom · Esc menú · F1 depuración"


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
		if ui.menu_personaje.visible:
			ui.menu_personaje.cerrar()
			get_viewport().set_input_as_handled()
			return
		if ui.mapa.visible:
			ui.mapa.cerrar()
			get_viewport().set_input_as_handled()
			return
		if ui.luz_abierta():
			ui.cerrar_luz()
			get_viewport().set_input_as_handled()
			return
		if ui.menu_abierto():
			ui.cerrar_menu()
		else:
			ui.abrir_menu()
		get_viewport().set_input_as_handled()
		return
	if ui.menu_abierto() or _alfa_terminado:
		return
	# Menú del personaje (Q): anotaciones, conversaciones, inventario.
	if ui.menu_personaje.visible:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_Q:
					if not event.echo:
						ui.menu_personaje.cerrar()
				KEY_LEFT, KEY_A:
					ui.menu_personaje.cambiar_pestana(-1)
				KEY_RIGHT, KEY_D, KEY_TAB:
					ui.menu_personaje.cambiar_pestana(1)
				KEY_1, KEY_KP_1:
					ui.menu_personaje.elegir(0)
				KEY_2, KEY_KP_2:
					ui.menu_personaje.elegir(1)
				KEY_3, KEY_KP_3:
					ui.menu_personaje.elegir(2)
				KEY_UP, KEY_W:
					ui.menu_personaje.desplazar(-1)
				KEY_DOWN, KEY_S:
					ui.menu_personaje.desplazar(1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		if not (ui.dialogo_activo() or ui.pregunta_activa() or ui.luz_abierta() or _fin_turno or _cinematica != "" or _cierre != ""):
			if ui.mapa.visible:
				ui.mapa.cerrar()
			personaje.detener()
			_pendiente = null
			ui.menu_personaje.abrir()
		get_viewport().set_input_as_handled()
		return
	# Tab abre y cierra el mapa (no durante diálogos, el panel de luz ni el cambio de turno).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if ui.mapa.visible:
			ui.mapa.cerrar()
		elif not (ui.dialogo_activo() or ui.pregunta_activa() or ui.luz_abierta() or _fin_turno or _cierre != ""):
			if _cinematica == "":
				personaje.detener()
				_pendiente = null
			ui.mapa.abrir()
		get_viewport().set_input_as_handled()
		return
	# Mapa abierto: L luz, 1/2/3 marcas, 0 borrar. Sobre la sala bajo el mouse, o la actual. WASD lo mueve (mapa.gd).
	if ui.mapa.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var s: String = ui.mapa.sala_objetivo()
			match event.keycode:
				KEY_L:
					ui.mapa.ciclar_luz(s)
				KEY_1, KEY_KP_1:
					ui.mapa.marcar(s, "Pa")
				KEY_2, KEY_KP_2:
					ui.mapa.marcar(s, "Pr")
				KEY_3, KEY_KP_3:
					ui.mapa.marcar(s, "Ft")
				KEY_0, KEY_KP_0, KEY_BACKSPACE, KEY_DELETE:
					ui.mapa.marcar(s, "")
		return
	# Pregunta con opciones: ←/→ (o A/D, W/S) eligen, E / Enter / Espacio confirman; el click lo manejan los botones.
	if ui.pregunta_activa():
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_LEFT, KEY_A, KEY_UP, KEY_W:
					ui.mover_seleccion(-1)
				KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
					ui.mover_seleccion(1)
				KEY_E, KEY_ENTER, KEY_SPACE:
					ui.confirmar_pregunta()
		return
	# Diálogo abierto: E / Espacio / Enter / click lo avanzan
	if ui.dialogo_activo():
		if (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]) \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			ui.avanzar_dialogo()
		return
	# Durante una cinemática o el cambio de turno no se controla al personaje.
	if _cinematica != "" or _fin_turno or _cierre != "":
		return
	# Panel de luz abierto: ↑/↓ (W/S) sala, ←/→ (A/D) nivel, L cierra. El click lo manejan los cuadritos.
	if ui.luz_abierta():
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_UP, KEY_W:
					ui.mover_seleccion_luz(-1)
				KEY_DOWN, KEY_S:
					ui.mover_seleccion_luz(1)
				KEY_LEFT, KEY_A:
					ui.cambiar_luz(-1)
				KEY_RIGHT, KEY_D:
					ui.cambiar_luz(1)
				KEY_L, KEY_E, KEY_ENTER:
					ui.cerrar_luz()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			ui.cerrar_luz()
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
				if obj == null:
					personaje.seguir(nave.camino(personaje.position, punto))
				else:
					personaje.seguir(_camino_a_objeto(obj.rect_global()), obj.rect_global(), ALCANCE - 3 * E)
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
		KEY_L:
			personaje.detener()
			_pendiente = null
			ui.abrir_luz(NOMBRES)
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
			Estado.energia = Estado.energia_maxima()
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
		KEY_F11:
			_pantalla_completa()
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


## F11: pantalla completa / ventana. A 1920x1080 en pantalla completa se ve 1:1 (cada píxel del arte, exacto).
func _pantalla_completa() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## El jugador pide un nivel de luz desde el panel. No cuesta energía (01, sección 5).
func _on_luz_pedida(sala: String, nivel: int) -> void:
	if nivel < 0 or nivel > 3:
		return
	if nivel > Estado.luz_maxima(sala) and nivel <= int(Estado.salas[sala]["luz_max_alfa"]):
		ui.mostrar_mensaje("%s no llega a luz %s todavía. Algo no está conectado." % [NOMBRES.get(sala, sala), Estado.NOMBRES_LUZ[nivel].to_lower()])
		return
	if nivel > Estado.luz_maxima(sala):
		ui.mostrar_mensaje("%s no llega a luz %s." % [NOMBRES.get(sala, sala), Estado.NOMBRES_LUZ[nivel].to_lower()])
		return
	if not Estado.set_luz(sala, nivel):
		ui.mostrar_mensaje("No alcanza la capacidad de luz. Bajá la luz de otra sala.")
