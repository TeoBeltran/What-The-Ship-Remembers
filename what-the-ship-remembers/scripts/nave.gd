extends Node2D
## La nave del Alfa como un solo espacio continuo (paso 3).
## Las salas (escenas/salas/) están ubicadas como en el mapa (doc 04). Esta escena arma:
## - los pasillos cortos entre puertas que se miran (con paredes y niebla);
## - una barrera en el medio de cada pasillo, cerrada si no se puede pasar (sala bloqueada o sin energía);
## - la grilla de caminos para moverse con click derecho.
## Moverse de sala se cobra al ENTRAR a la otra sala (lo detecta el juego con sala_en()).

signal aviso(texto: String)

const PARED := 8.0
const CELDA := 8  # grilla de caminos (px)
const COLOR_PISO := Color(0.42, 0.42, 0.44)
const COLOR_PARED := Color(0.2, 0.2, 0.22)

var salas: Dictionary = {}     # codigo -> nodo sala
var pasillos: Array = []       # {a, b, piso: Rect2, barrera: CollisionShape2D, sensor: Area2D}
var trabadas: Array = []       # huecos de puertas sin destino
var grilla := AStarGrid2D.new()

var _niebla_pasillos: Node2D


func _ready() -> void:
	for n in get_children():
		if n.has_method("puertas"):
			salas[n.codigo] = n
	_crear_pasillos()
	_crear_trabadas()
	_niebla_pasillos = Node2D.new()
	_niebla_pasillos.z_index = 20
	add_child(_niebla_pasillos)
	_niebla_pasillos.draw.connect(_dibujar_niebla_pasillos)
	for s in [Estado.energia_cambiada, Estado.sala_cambiada, Estado.sala_desbloqueada, Estado.turno_empezado]:
		s.connect(func(_x): actualizar())
	actualizar()


## Sala que contiene el punto (paredes incluidas), o "" si está en un pasillo o afuera.
func sala_en(punto: Vector2) -> String:
	for c in salas:
		if salas[c].rect_global().has_point(punto):
			return c
	return ""


func centro_de(codigo: String) -> Vector2:
	return salas[codigo].position + salas[codigo].centro()


# ============================================================
# Pasillos
# ============================================================

func _crear_pasillos() -> void:
	var hechos := {}
	for a in salas:
		for p in salas[a].puertas():
			var b: String = p.destino
			if b == "" or not salas.has(b) or hechos.has([b, a]):
				continue
			var q = salas[b].puerta_hacia(a)
			if q == null:
				push_error("La puerta de %s hacia %s no tiene pareja en %s" % [a, b, b])
				continue
			hechos[[a, b]] = true
			_crear_pasillo(a, b, salas[a].hueco_puerta(p), salas[b].hueco_puerta(q), p.lado in ["izquierda", "derecha"])


func _crear_pasillo(a: String, b: String, hueco_a: Rect2, hueco_b: Rect2, horizontal: bool) -> void:
	# Piso entre los dos huecos (sin incluirlos).
	var piso: Rect2
	if horizontal:
		var x0 := minf(hueco_a.end.x, hueco_b.end.x)
		var x1 := maxf(hueco_a.position.x, hueco_b.position.x)
		piso = Rect2(x0, hueco_a.position.y, x1 - x0, hueco_a.size.y)
	else:
		var y0 := minf(hueco_a.end.y, hueco_b.end.y)
		var y1 := maxf(hueco_a.position.y, hueco_b.position.y)
		piso = Rect2(hueco_a.position.x, y0, hueco_a.size.x, y1 - y0)
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	# Paredes a los costados del pasillo.
	var lados: Array[Rect2] = []
	if horizontal:
		lados = [Rect2(piso.position.x, piso.position.y - PARED, piso.size.x, PARED), Rect2(piso.position.x, piso.end.y, piso.size.x, PARED)]
	else:
		lados = [Rect2(piso.position.x - PARED, piso.position.y, PARED, piso.size.y), Rect2(piso.end.x, piso.position.y, PARED, piso.size.y)]
	for r in lados:
		cuerpo.add_child(_forma(r))
	# Barrera en el medio (se activa cuando no se puede pasar).
	var c := piso.get_center()
	var r_barrera := Rect2(c.x - PARED / 2.0, piso.position.y, PARED, piso.size.y) if horizontal else Rect2(piso.position.x, c.y - PARED / 2.0, piso.size.x, PARED)
	var barrera := _forma(r_barrera)
	cuerpo.add_child(barrera)
	# Sensor alrededor de la barrera, para avisar por qué no se puede pasar.
	var sensor := Area2D.new()
	sensor.add_child(_forma(r_barrera.grow(6)))
	add_child(sensor)
	var pasillo := {"a": a, "b": b, "piso": piso, "paredes": lados, "barrera": barrera, "sensor": sensor, "abierto": true}
	sensor.body_entered.connect(func(body): if body.has_method("es_personaje") and not pasillo["abierto"]: _avisar_cerrado(pasillo))
	pasillos.append(pasillo)


func _crear_trabadas() -> void:
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	for c in salas:
		for p in salas[c].puertas():
			if p.destino == "":
				var hueco: Rect2 = salas[c].hueco_puerta(p)
				cuerpo.add_child(_forma(hueco))
				var sensor := Area2D.new()
				sensor.add_child(_forma(hueco.grow(6)))
				add_child(sensor)
				sensor.body_entered.connect(func(body): if body.has_method("es_personaje"): aviso.emit("No cede. Algo la traba."))
				trabadas.append(hueco)


func _forma(r: Rect2) -> CollisionShape2D:
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	forma.shape = rect
	forma.position = r.get_center()
	return forma


## Del lado de la sala actual: ¿se puede ir a la otra punta del pasillo?
func _motivo_cerrado(pasillo: Dictionary) -> String:
	var actual := Estado.sala_actual
	if actual == pasillo["a"]:
		return Estado.motivo_no_movible(pasillo["b"])
	if actual == pasillo["b"]:
		return Estado.motivo_no_movible(pasillo["a"])
	return "no estás en ninguna de las dos salas"


func _avisar_cerrado(pasillo: Dictionary) -> void:
	aviso.emit("No puedo pasar: " + _motivo_cerrado(pasillo) + ".")


## Recalcula qué pasillos están abiertos, la niebla y la grilla de caminos.
func actualizar() -> void:
	for p in pasillos:
		p["abierto"] = _motivo_cerrado(p) == ""
		p["barrera"].set_deferred("disabled", p["abierto"])
	_niebla_pasillos.queue_redraw()
	queue_redraw()
	_armar_grilla()


# ============================================================
# Dibujo
# ============================================================

func _draw() -> void:
	for p in pasillos:
		for r in p["paredes"]:
			draw_rect(r, COLOR_PARED)
		draw_rect(p["piso"], COLOR_PISO)


func _dibujar_niebla_pasillos() -> void:
	for p in pasillos:
		var a: String = p["a"]
		var b: String = p["b"]
		var zona: Rect2 = p["piso"].grow(PARED)
		if Estado.sala_actual in [a, b]:
			continue
		var visto := Estado.visitadas.has(a) or Estado.visitadas.has(b)
		_niebla_pasillos.draw_rect(zona, Color(0, 0, 0, 0.6) if visto else Color.BLACK)


# ============================================================
# Caminos (click derecho)
# ============================================================

func _armar_grilla() -> void:
	var zonas: Array[Rect2] = []
	for c in salas:
		if not Estado.desbloqueadas.has(c):
			continue
		var r: Rect2 = salas[c].rect_global()
		zonas.append(r.grow(-PARED))
		for p in salas[c].puertas():
			if p.destino != "" and Estado.desbloqueadas.has(p.destino):
				zonas.append(salas[c].hueco_puerta(p))
	for p in pasillos:
		if Estado.desbloqueadas.has(p["a"]) and Estado.desbloqueadas.has(p["b"]):
			zonas.append(p["piso"])
	if zonas.is_empty():
		return  # todavía no empezó la partida
	var total := zonas[0]
	for z in zonas:
		total = total.merge(z)
	var region := Rect2i(Vector2i((total.position / CELDA).floor()), Vector2i((total.size / CELDA).ceil()) + Vector2i(2, 2))
	grilla.region = region
	grilla.cell_size = Vector2(CELDA, CELDA)
	grilla.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grilla.update()
	var libre := {}
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var celda := Rect2(Vector2(x, y) * CELDA, Vector2(CELDA, CELDA))
			for z in zonas:
				if z.encloses(celda):
					libre[Vector2i(x, y)] = true
					break
	# Se achica un borde de una celda para que el personaje no roce las paredes.
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var id := Vector2i(x, y)
			var ok := libre.has(id)
			if ok:
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					if not libre.has(id + d):
						ok = false
						break
			grilla.set_point_solid(id, not ok)


## Camino desde "desde" hasta el punto libre más cercano a "hasta" (en px de la nave).
func camino(desde: Vector2, hasta: Vector2) -> PackedVector2Array:
	var a = _celda_libre(desde)
	var b = _celda_libre(hasta)
	if a == null or b == null:
		return PackedVector2Array()
	var ids := grilla.get_id_path(a, b)
	var puntos := PackedVector2Array()
	for id in ids:
		puntos.append(Vector2(id) * CELDA + Vector2(CELDA, CELDA) / 2.0)
	if puntos.size() > 0:
		puntos.remove_at(0)
	return puntos


func _celda_libre(punto: Vector2):
	var c := Vector2i((punto / CELDA).floor())
	for radio in range(0, 6):
		for dx in range(-radio, radio + 1):
			for dy in range(-radio, radio + 1):
				var id := c + Vector2i(dx, dy)
				if grilla.is_in_boundsv(id) and not grilla.is_point_solid(id):
					return id
	return null
