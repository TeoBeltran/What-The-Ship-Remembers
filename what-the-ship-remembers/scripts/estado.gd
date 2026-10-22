extends Node
## Núcleo de reglas del Alfa (paso 2). Sin gráficos.
## Va a ser el singleton (Autoload) "Estado" desde el paso 3. Mientras tanto se puede crear con .new().
##
## Reglas: diseno/01 (secciones 4 y 5) y diseno/02. Datos: res://datos/*.json (generados desde la planilla).
## La interfaz (pasos 3 en adelante) escucha las señales; este script no dibuja nada.

signal turno_empezado(turno: int)
signal energia_cambiada(energia: int)
signal sala_cambiada(sala: String)
signal luz_cambiada(sala: String, nivel: int)
signal objeto_activado(id: String)
signal objeto_usado(id: String)
signal texto_mostrado(id: String, lineas: Array)
signal item_agregado(id: String)
signal audio_reproducido(id: String)
signal anotacion_agregada(id: String)
signal evento_especial(id: String)
signal sala_desbloqueada(sala: String)

const SALA_INICIO := "MAN"

# ---------- datos (de los JSON) ----------
var objetos: Dictionary = {}
var salas: Dictionary = {}
var guion: Dictionary = {}
var conexiones: Array = []
var textos: Dictionary = {}
var anotaciones_txt: Dictionary = {}
var items: Dictionary = {}
var audios: Dictionary = {}
var eventos: Dictionary = {}
var config: Dictionary = {}
var muebles: Array = []               # fijos en todos los tiempos (solo se dibujan)

## true: las interacciones forzadas se usan solas apenas se ven (simulación).
## false: el juego las pide con siguiente_forzada() y las hace como cinemática (camina hasta el objeto).
var forzadas_automaticas := true

# ---------- estado de la partida ----------
var turno: int = 0
var energia: int = 0
var sala_actual: String = SALA_INICIO
var luz: Dictionary = {}              # sala -> nivel 0..3
var desbloqueadas: Dictionary = {}    # sala -> true
var arregladas: Dictionary = {}       # sala -> true (permite luz máxima)
var energia_extra: int = 0            # energía por turno ganada con arreglos (panel eléctrico: +1)
var obj: Dictionary = {}              # id -> {activo, usado, desdibujado}
var visitadas: Dictionary = {}        # salas visitadas alguna vez
var visitadas_turno: Dictionary = {}  # salas visitadas en el turno actual
var marcas: Dictionary = {}           # sala -> "Pa"/"Pr"/"Ft" (del jugador, por turno)
var inventario: Array[String] = []
var anotaciones: Array[String] = []
var anotaciones_turno: Dictionary = {} # id de anotación -> turno en que se agregó (paso 8)
var conversaciones: Array = []        # conversaciones con NORA ya tenidas, en orden: {id, turno} (paso 8)


func _init() -> void:
	cargar_datos()


# ============================================================
# Datos
# ============================================================

func cargar_datos() -> void:
	objetos = _leer("objetos")
	salas = _leer("salas")
	guion = _leer("guion")
	conexiones = _leer("conexiones")
	textos = _leer("textos")
	anotaciones_txt = _leer("anotaciones")
	items = _leer("items")
	audios = _leer("audios")
	eventos = _leer("eventos")
	config = _leer("config")
	muebles = _leer("muebles")


func _leer(nombre: String):
	var ruta := "res://datos/%s.json" % nombre
	var datos = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if datos == null:
		push_error("No se pudo leer " + ruta)
		return {}
	return datos


func cfg(clave: String) -> int:
	return int(config.get(clave, 0))


# ============================================================
# Partida y turnos
# ============================================================

func nueva_partida() -> void:
	turno = 0
	obj.clear()
	for id in objetos:
		obj[id] = {"activo": false, "usado": false, "desdibujado": false}
	luz.clear()
	desbloqueadas.clear()
	arregladas.clear()
	energia_extra = 0
	for s in salas:
		luz[s] = int(salas[s]["luz_inicial"])
		if salas[s]["desbloqueada_inicio"]:
			desbloqueadas[s] = true
	visitadas.clear()
	inventario.clear()
	anotaciones.clear()
	anotaciones_turno.clear()
	conversaciones.clear()
	empezar_turno()


## Empieza el turno siguiente: energía al máximo, en la sala de mando, marcas y visitas del turno vacías.
func empezar_turno() -> void:
	turno += 1
	energia = energia_maxima()
	visitadas_turno.clear()
	marcas.clear()
	sala_actual = SALA_INICIO
	_marcar_visita(SALA_INICIO)
	turno_empezado.emit(turno)
	energia_cambiada.emit(energia)
	sala_cambiada.emit(sala_actual)
	revisar_activaciones()
	procesar_forzadas()


## Energía del traje al empezar cada turno (14 en el Alfa; 15 después de arreglar el panel).
func energia_maxima() -> int:
	return cfg("energia_por_turno") + energia_extra


func es_ultimo_turno() -> bool:
	return turno >= cfg("turnos_alfa")


func tiempo_de(sala: String) -> String:
	if not guion.has(str(turno)):
		return "presente"  # antes de empezar la partida
	return guion[str(turno)][sala]


func _marcar_visita(sala: String) -> void:
	visitadas[sala] = true
	visitadas_turno[sala] = true


# ============================================================
# Activaciones (función única, la llaman todas las acciones)
# ============================================================

## Activa los objetos que cumplen condiciones + TurnoM. Repite hasta que no cambie nada,
## porque una activación puede habilitar otra (condiciones ".Activo").
func revisar_activaciones() -> Array:
	var nuevos := []
	var cambio := true
	while cambio:
		cambio = false
		for id in objetos:
			if obj[id]["activo"]:
				continue
			var o: Dictionary = objetos[id]
			if int(o["turno_min"]) <= turno and _cumple_condiciones(o):
				obj[id]["activo"] = true
				nuevos.append(id)
				cambio = true
				objeto_activado.emit(id)
	return nuevos


func _cumple_condiciones(o: Dictionary) -> bool:
	var conds: Array = o["condiciones"]
	if conds.is_empty():
		return true
	var resultados := []
	for c in conds:
		resultados.append(bool(obj[c["objeto"]][c["campo"]]))
	if o["tipo_cond"] == "O":
		return resultados.has(true)
	return not resultados.has(false)


# ============================================================
# Visibilidad e interacción
# ============================================================

## Existe en este momento: activo, la sala está en su tiempo y no pasó su último turno (turnoMax).
func existe(id: String) -> bool:
	var o: Dictionary = objetos[id]
	if o.get("turno_max") != null and turno > int(o["turno_max"]):
		return false
	return obj[id]["activo"] and o["tiempo"] == tiempo_de(o["sala"])


## Se dibuja: existe + no desdibujado + luz de la sala >= LuzM.
func se_ve(id: String) -> bool:
	var o: Dictionary = objetos[id]
	return existe(id) and not obj[id]["desdibujado"] and int(luz[o["sala"]]) >= int(o["luz_min"])


func objetos_visibles(sala: String) -> Array:
	var lista := []
	for id in objetos:
		if objetos[id]["sala"] == sala and se_ve(id):
			lista.append(id)
	return lista


func es_solo_visual(id: String) -> bool:
	return (objetos[id]["disparadores"] as Array).is_empty()


## Costo final: Costo de la planilla, con descuento si la sala está a luz máxima (mínimo 0).
func costo_interaccion(id: String) -> int:
	var o: Dictionary = objetos[id]
	if o["forzada"]:
		return 0
	var c := int(o["costo"])
	if int(luz[o["sala"]]) == 3:
		c -= cfg("descuento_luz_max")
	return maxi(c, 0)


## Por qué no se puede usar ("" = se puede). Útil para la interfaz y para depurar.
func motivo_no_usable(id: String) -> String:
	if not objetos.has(id):
		return "no existe ese objeto"
	if objetos[id]["sala"] != sala_actual:
		return "no estás en esa sala"
	if not se_ve(id):
		return "no se ve (inactivo, otro tiempo, desdibujado o poca luz)"
	if obj[id]["usado"]:
		return "ya se usó"
	if es_solo_visual(id):
		return "es solo visual"
	if energia < costo_interaccion(id):
		return "no alcanza la energía (%d de %d)" % [energia, costo_interaccion(id)]
	return ""


func se_puede_usar(id: String) -> bool:
	return motivo_no_usable(id) == ""


## Interactuar: cobra, marca Usado, ejecuta disparadores y revisa activaciones.
func interactuar(id: String) -> bool:
	if not se_puede_usar(id):
		return false
	_gastar(costo_interaccion(id))
	obj[id]["usado"] = true
	if es_conversacion(id):
		conversaciones.append({"id": id, "turno": turno})
	objeto_usado.emit(id)
	for d in objetos[id]["disparadores"]:
		_ejecutar_disparador(int(d["tipo"]), str(d["param"]))
	revisar_activaciones()
	procesar_forzadas()
	return true


func _ejecutar_disparador(tipo: int, param: String) -> void:
	match tipo:
		0:
			_evento(param)
		1:
			texto_mostrado.emit(param, textos.get(param, []))
		2:
			inventario.append(param)
			item_agregado.emit(param)
		3:
			audio_reproducido.emit(param)
		4:
			if not anotaciones.has(param):
				anotaciones.append(param)
				anotaciones_turno[param] = turno
			anotacion_agregada.emit(param)
		5:
			obj[param]["desdibujado"] = true


## Eventos especiales (disparador tipo 0): los resuelve el código.
func _evento(id: String) -> void:
	match id:
		"arreglo_panel":
			# Panel eléctrico arreglado (destornillador + pinza): mando y comunicaciones pueden llegar a luz
			# máxima (suben solas si alcanza la capacidad) y el traje gana energía por turno, también ahora.
			arregladas["MAN"] = true
			arregladas["COM"] = true
			energia_extra = cfg("energia_por_arreglo")
			energia += energia_extra
			energia_cambiada.emit(energia)
			for s in ["MAN", "COM"]:
				if desbloqueadas.has(s) and int(luz[s]) < luz_maxima(s):
					set_luz(s, luz_maxima(s))
		_:
			if id.begins_with("desbloquear_"):
				desbloquear(id.trim_prefix("desbloquear_"))
	evento_especial.emit(id)


# ============================================================
# NORA (paso 8)
# ============================================================

## Las conversaciones con NORA son los objetos MAN_N* (consola de la sala de mando).
func es_conversacion(id: String) -> bool:
	return id.begins_with("MAN_N")


## Conversaciones que se pueden elegir ahora en la consola (no forzadas: esas salen solas).
func conversaciones_disponibles() -> Array:
	var lista := []
	for id in objetos:
		if es_conversacion(id) and not objetos[id]["forzada"] and se_puede_usar(id):
			lista.append(id)
	lista.sort_custom(func(a, b): return int(a.trim_prefix("MAN_N")) < int(b.trim_prefix("MAN_N")))
	return lista


## Líneas de texto de una conversación (su primer disparador de texto).
func lineas_de(id: String) -> Array:
	for d in objetos[id]["disparadores"]:
		if int(d["tipo"]) == 1:
			return textos.get(str(d["param"]), [])
	return []


## Tema que ve el jugador en el menú de NORA: la primera línea del personaje (sin comillas ni puntos suspensivos finales).
func tema_de(id: String) -> String:
	for l in lineas_de(id):
		if l["hablante"] == "PERSONAJE":
			return str(l["texto"])
	return "Hablar"


## Primera interacción forzada pendiente en la sala actual ("" = ninguna). La usa el juego para las cinemáticas.
func siguiente_forzada() -> String:
	for id in objetos_visibles(sala_actual):
		if objetos[id]["forzada"] and not obj[id]["usado"]:
			return id
	return ""


## Usa solas las interacciones forzadas visibles en la sala actual (solo en modo automático).
func procesar_forzadas() -> void:
	if not forzadas_automaticas:
		return
	var hubo := true
	while hubo:
		hubo = false
		for id in objetos_visibles(sala_actual):
			if objetos[id]["forzada"] and not obj[id]["usado"]:
				if interactuar(id):
					hubo = true
					break


# ============================================================
# Energía y movimiento
# ============================================================

func _gastar(cantidad: int) -> void:
	energia -= cantidad
	energia_cambiada.emit(energia)


func conectadas(a: String, b: String) -> bool:
	for c in conexiones:
		if (c[0] == a and c[1] == b) or (c[0] == b and c[1] == a):
			return true
	return false


## Costo de moverse: 0 a mando o si es la vuelta de una conexión con vuelta_gratis;
## si no, 3 (o 2 si la sala de ORIGEN está a luz máxima).
func costo_mover(destino: String) -> int:
	if destino == SALA_INICIO:
		return cfg("costo_volver_a_mando")
	for c in conexiones:
		if c[0] == destino and c[1] == sala_actual and c.size() > 2 and c[2]:
			return 0
	if int(luz[sala_actual]) == 3:
		return cfg("costo_cruzar_desde_luz_max")
	return cfg("costo_cruzar_puerta")


func motivo_no_movible(destino: String) -> String:
	if not salas.has(destino):
		return "no existe esa sala"
	if destino == sala_actual:
		return "ya estás ahí"
	if not conectadas(sala_actual, destino):
		return "no hay conexión directa"
	if not desbloqueadas.has(destino):
		return "la sala está bloqueada"
	if energia < costo_mover(destino):
		return "no alcanza la energía (%d de %d)" % [energia, costo_mover(destino)]
	return ""


func mover_a(destino: String) -> bool:
	if motivo_no_movible(destino) != "":
		return false
	_gastar(costo_mover(destino))
	sala_actual = destino
	_marcar_visita(destino)
	sala_cambiada.emit(destino)
	revisar_activaciones()
	_textos_al_entrar()
	procesar_forzadas()
	return true


## Textos automáticos al entrar (campo TextoAlEntrar): se muestran si el objeto se ve, sin usarlo.
func _textos_al_entrar() -> void:
	for id in objetos_visibles(sala_actual):
		var t = objetos[id].get("texto_al_entrar")
		if t:
			texto_mostrado.emit(t, textos.get(t, []))


func desbloquear(sala: String) -> void:
	if desbloqueadas.has(sala):
		return
	desbloqueadas[sala] = true
	luz[sala] = 0  # toda sala recién desbloqueada empieza apagada (01, sección 5)
	sala_desbloqueada.emit(sala)


# ============================================================
# Luz
# ============================================================

const NOMBRES_LUZ := ["Apagada", "Baja", "Media", "Máxima"]


## Capacidad que ocupa una sala con un nivel de luz: el nivel, salvo a luz máxima,
## donde ocupa "capacidad_a_luz_max" (normalmente 3; hay arreglos que la bajan a 2 o 1).
func ocupa(sala: String, nivel := -1) -> int:
	if nivel < 0:
		nivel = int(luz[sala])
	if nivel == 3:
		return int(salas[sala].get("capacidad_a_luz_max", 3))
	return nivel


func capacidad_usada() -> int:
	var total := 0
	for s in luz:
		total += ocupa(s)
	return total


func capacidad_libre() -> int:
	return cfg("capacidad_luz") - capacidad_usada()


func luz_maxima(sala: String) -> int:
	if arregladas.has(sala):
		return int(salas[sala]["luz_max_alfa"])
	return int(salas[sala]["luz_max_sin_arreglo"])


func motivo_no_luz(sala: String, nivel: int) -> String:
	if not desbloqueadas.has(sala):
		return "la sala está bloqueada"
	if nivel < 0 or nivel > 3:
		return "nivel inválido"
	if nivel > luz_maxima(sala):
		return "esa sala llega como mucho a %d" % luz_maxima(sala)
	if capacidad_usada() - ocupa(sala) + ocupa(sala, nivel) > cfg("capacidad_luz"):
		return "no alcanza la capacidad de luz (libre: %d)" % capacidad_libre()
	return ""


## Cambiar la luz no cuesta energía. Si el jugador está en esa sala, se revisan las forzadas
## (los objetos se redibujan en la interfaz al recibir luz_cambiada).
func set_luz(sala: String, nivel: int) -> bool:
	if motivo_no_luz(sala, nivel) != "":
		return false
	if int(luz[sala]) == nivel:
		return true
	luz[sala] = nivel
	luz_cambiada.emit(sala, nivel)
	if sala == sala_actual:
		procesar_forzadas()
	return true
