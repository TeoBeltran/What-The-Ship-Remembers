extends Node2D
## La nave del Alfa como un solo espacio continuo, armado en una grilla de tiles (como un map maker).
## Las salas (escenas/salas/) dicen dónde está su piso y qué arte usan; acá se arma todo lo demás:
## - las paredes de cada sala: frente de 2 tiles arriba (se ve de frente), 1 tile a los costados y abajo;
## - los pasillos entre salas conectadas (datos/conexiones.json) y sus puertas (siempre puertas dobles
##   en una pared que se ve de frente: nunca puertas de costado);
## - la colisión, el dibujo del piso y las paredes, la niebla de los pasillos y la grilla de caminos.
## Moverse de sala se cobra al ENTRAR al piso de la otra sala (lo detecta el juego con sala_en()).
##
## Pasillo de costado (sala A a la izquierda, sala B a la derecha, misma altura), visto en tiles:
##   entre la pared de A y la de B hay 6 columnas.
##     filas 1-2  frente de pared
##     filas 3-4  pasillo de arriba (une las dos puertas)
##     filas 5-6  pared de frente con una puerta doble de cada lado (en el medio, pared)
##     filas 7-8  dos recovecos abiertos hacia su sala (la abertura en la pared es del pasillo)
##                separados por un tabique de 2 tiles
##     fila 9     pared de abajo
##   Así, vayas para donde vayas, siempre entrás por una puerta que se ve de frente.
## Salida trabada a la derecha (sala.salida_trabada_derecha): la mitad izquierda de un pasillo de costado,
##   el recoveco (filas 7-8) y la puerta doble de frente (filas 5-6), que nunca abre.
## Pasillo hacia arriba (sala A arriba, sala B abajo, centradas): 2 tiles de ancho; una puerta en el
##   frente de B y otra en el frente propio del pasillo, justo debajo de la pared de A.

signal aviso(texto: String)

const T := Medidas.TILE
const CELDA := Medidas.CELDA  # grilla de caminos (px)
const E := Medidas.ESCALA
const F := Medidas.FRENTE     # alto del frente de pared, en tiles

## Arte de los pasillos (números de arte_nave.gd).
const PISO_PASILLO := 1
const PARED_PASILLO := 3

const Puerta := preload("res://scripts/puerta.gd")

var salas: Dictionary = {}     # codigo -> nodo sala
var pasillos: Array = []       # {id, a, b, piso: Rect2, abierto, motivo, puertas}
var puertas: Array = []
var grilla := AStarGrid2D.new()

## Plano de la nave: Vector2i (tile) -> {tipo, dueno, ...}
## tipo: "piso" | "tapa" (pared vista desde arriba) | "frente" (pared vista de frente) | "puerta"
## dueno: código de sala, o id del pasillo ("P0", "P1"...)
var celdas: Dictionary = {}

var _niebla_pasillos: Node2D


func _ready() -> void:
	for n in get_children():
		if n.has_method("rects_solidos"):
			salas[n.codigo] = n
	for c in salas:
		_armar_sala(salas[c])
	_armar_pasillos()
	for c in salas:
		if salas[c].salida_trabada_derecha:
			_salida_trabada(salas[c])
	_crear_colision()
	for c in salas:
		var sala = salas[c]
		sala.poner_zonas(_rects_de(c).map(func(r): return Rect2(r.position - sala.position, r.size)))
	_niebla_pasillos = Node2D.new()
	_niebla_pasillos.z_index = 20
	add_child(_niebla_pasillos)
	_niebla_pasillos.draw.connect(_dibujar_niebla_pasillos)
	for s in [Estado.energia_cambiada, Estado.sala_cambiada, Estado.sala_desbloqueada, Estado.turno_empezado]:
		s.connect(func(_x): actualizar())
	actualizar()


## Sala cuyo PISO contiene el punto, o "" si está en un pasillo, una puerta o afuera.
func sala_en(punto: Vector2) -> String:
	for c in salas:
		if salas[c].rect_global().has_point(punto):
			return c
	return ""


func centro_de(codigo: String) -> Vector2:
	return salas[codigo].position + salas[codigo].centro()


# ============================================================
# Plano
# ============================================================

func _poner(t: Vector2i, tipo: String, dueno: String, extra := {}) -> void:
	var d := {"tipo": tipo, "dueno": dueno}
	d.merge(extra, true)
	celdas[t] = d


func _armar_sala(s) -> void:
	var o: Vector2i = s.pos_tiles
	var w: int = s.ancho
	var h: int = s.alto
	for x in w:
		for y in h:
			_poner(o + Vector2i(x, y), "piso", s.codigo, {"material": s.piso, "u": x % 2, "v": y % 2})
		for v in F:  # frente de arriba, alineado con las placas del piso
			_poner(o + Vector2i(x, v - F), "frente", s.codigo, {"pared": s.pared, "u": x % 2, "v": v})
	for y in range(-F, h + 1):  # costados
		_poner(o + Vector2i(-1, y), "tapa", s.codigo)
		_poner(o + Vector2i(w, y), "tapa", s.codigo)
	for x in range(-1, w + 1):  # abajo
		_poner(o + Vector2i(x, h), "tapa", s.codigo)
	for col in s.puertas_trabadas:
		_crear_puerta(o + Vector2i(col, -F), s.codigo, s.pared, null)


func _armar_pasillos() -> void:
	var hechos := {}
	for con in Estado.conexiones:
		var a: String = con["a"] if con is Dictionary else con[0]
		var b: String = con["b"] if con is Dictionary else con[1]
		if not salas.has(a) or not salas.has(b) or hechos.has([b, a]) or hechos.has([a, b]):
			continue
		hechos[[a, b]] = true
		var sa = salas[a]
		var sb = salas[b]
		if sa.pos_tiles.x > sb.pos_tiles.x + sb.ancho:
			_pasillo_costado(sb, sa)
		elif sb.pos_tiles.x > sa.pos_tiles.x + sa.ancho:
			_pasillo_costado(sa, sb)
		elif sa.pos_tiles.y < sb.pos_tiles.y:
			_pasillo_arriba(sa, sb)
		else:
			_pasillo_arriba(sb, sa)


func _nuevo_pasillo(a: String, b: String) -> Dictionary:
	var p := {"id": "P%d" % pasillos.size(), "a": a, "b": b, "abierto": true, "motivo": "", "puertas": [], "piso": Rect2()}
	pasillos.append(p)
	return p


func _piso_pasillo(p: Dictionary, t: Vector2i) -> void:
	_poner(t, "piso", p["id"], {"material": PISO_PASILLO})
	var r := Rect2(Vector2(t) * T, Vector2(T, T))
	p["piso"] = r if p["piso"].size == Vector2.ZERO else p["piso"].merge(r)


func _pasillo_costado(izq, der) -> void:
	var xa: int = izq.pos_tiles.x + izq.ancho        # columna de la pared derecha de la sala izquierda
	var xb: int = der.pos_tiles.x - 1                # columna de la pared izquierda de la sala derecha
	var y0: int = izq.pos_tiles.y
	if xb - xa != 7 or der.pos_tiles.y != y0 or izq.alto < 10 or der.alto < 10:
		push_error("Pasillo %s-%s: las salas tienen que estar a la misma altura (alto >= 10) y con 6 tiles entre sus paredes" % [izq.codigo, der.codigo])
		return
	var p := _nuevo_pasillo(izq.codigo, der.codigo)
	var id: String = p["id"]
	for i in 6:
		var x := xa + 1 + i
		var u := i % 2
		_poner(Vector2i(x, y0 + 1), "frente", id, {"pared": PARED_PASILLO, "u": u, "v": 0})
		_poner(Vector2i(x, y0 + 2), "frente", id, {"pared": PARED_PASILLO, "u": u, "v": 1})
		_piso_pasillo(p, Vector2i(x, y0 + 3))
		_piso_pasillo(p, Vector2i(x, y0 + 4))
		if i in [2, 3]:  # pared del medio, entre las dos puertas
			_poner(Vector2i(x, y0 + 5), "frente", id, {"pared": PARED_PASILLO, "u": u, "v": 0})
			_poner(Vector2i(x, y0 + 6), "frente", id, {"pared": PARED_PASILLO, "u": u, "v": 1})
			_poner(Vector2i(x, y0 + 7), "tapa", id)  # tabique entre los recovecos
			_poner(Vector2i(x, y0 + 8), "tapa", id)
		else:
			_piso_pasillo(p, Vector2i(x, y0 + 7))
			_piso_pasillo(p, Vector2i(x, y0 + 8))
		_poner(Vector2i(x, y0 + 9), "tapa", id)
	# Aberturas en las paredes de las salas (son parte del pasillo).
	for y in [y0 + 7, y0 + 8]:
		_piso_pasillo(p, Vector2i(xa, y))
		_piso_pasillo(p, Vector2i(xb, y))
	_crear_puerta(Vector2i(xa + 1, y0 + 5), id, PARED_PASILLO, p)
	_crear_puerta(Vector2i(xa + 5, y0 + 5), id, PARED_PASILLO, p)


## Recoveco abierto hacia la sala, a la derecha, con una puerta trabada de frente (sala común en el Alfa:
## según el mapa, la sala común sigue hacia la derecha, al resto de la nave).
func _salida_trabada(s) -> void:
	var xa: int = s.pos_tiles.x + s.ancho   # columna de la pared derecha de la sala
	var y0: int = s.pos_tiles.y
	var p := _nuevo_pasillo(s.codigo, s.codigo)
	p["salida"] = true
	var id: String = p["id"]
	for y in [y0 + 7, y0 + 8]:
		_piso_pasillo(p, Vector2i(xa, y))      # abertura en la pared de la sala
		_piso_pasillo(p, Vector2i(xa + 1, y))
		_piso_pasillo(p, Vector2i(xa + 2, y))
	for x in [xa + 1, xa + 2, xa + 3]:
		_poner(Vector2i(x, y0 + 3), "tapa", id)
		_poner(Vector2i(x, y0 + 4), "tapa", id)
		_poner(Vector2i(x, y0 + 9), "tapa", id)
	for y in range(y0 + 5, y0 + 9):
		_poner(Vector2i(xa + 3, y), "tapa", id)
	_crear_puerta(Vector2i(xa + 1, y0 + 5), id, PARED_PASILLO, null)


func _pasillo_arriba(arriba, abajo) -> void:
	var c: int = abajo.pos_tiles.x + abajo.ancho / 2 - 1   # columna izquierda de la puerta doble
	var y_pared: int = arriba.pos_tiles.y + arriba.alto     # pared de abajo de la sala de arriba
	var y_frente_b: int = abajo.pos_tiles.y - F             # frente de la sala de abajo
	if arriba.pos_tiles.x + arriba.ancho / 2 - 1 != c or y_frente_b - (y_pared + 1 + F) < 1:
		push_error("Pasillo %s-%s: las salas tienen que estar centradas y con lugar para el pasillo" % [arriba.codigo, abajo.codigo])
		return
	var p := _nuevo_pasillo(arriba.codigo, abajo.codigo)
	var id: String = p["id"]
	for x in [c, c + 1]:
		_piso_pasillo(p, Vector2i(x, y_pared))  # abertura en la pared de la sala de arriba
		for y in range(y_pared + 1 + F, y_frente_b):
			_piso_pasillo(p, Vector2i(x, y))
	for y in range(y_pared + 1, y_frente_b):
		_poner(Vector2i(c - 1, y), "tapa", id)
		_poner(Vector2i(c + 2, y), "tapa", id)
	_crear_puerta(Vector2i(c, y_pared + 1), id, PARED_PASILLO, p)
	_crear_puerta(Vector2i(c, y_frente_b), id, abajo.pared, p)


func _crear_puerta(t: Vector2i, dueno: String, pared: int, pasillo) -> void:
	for dx in 2:
		for dy in F:
			_poner(t + Vector2i(dx, dy), "puerta", dueno)
	var pu = Puerta.new()
	pu.position = Vector2(t) * T
	pu.pared = pared
	pu.pasillo = pasillo
	pu.aviso.connect(func(txt): aviso.emit(txt))
	add_child(pu)
	puertas.append(pu)
	if pasillo != null:
		pasillo["puertas"].append(pu)


## Rectángulos (en px de la nave) de las celdas de un dueño, juntando tramos de cada fila.
func _rects_de(dueno: String) -> Array:
	var por_fila := {}
	for t in celdas:
		if celdas[t]["dueno"] == dueno:
			if not por_fila.has(t.y):
				por_fila[t.y] = []
			por_fila[t.y].append(t.x)
	var lista := []
	for y in por_fila:
		var xs: Array = por_fila[y]
		xs.sort()
		var desde: int = xs[0]
		var hasta: int = xs[0]
		for x in xs.slice(1):
			if x == hasta + 1:
				hasta = x
			else:
				lista.append(Rect2(desde * T, y * T, (hasta - desde + 1) * T, T))
				desde = x
				hasta = x
		lista.append(Rect2(desde * T, y * T, (hasta - desde + 1) * T, T))
	return lista


# ============================================================
# Colisión
# ============================================================

func _solida(t: Vector2i) -> bool:
	return celdas.has(t) and celdas[t]["tipo"] in ["tapa", "frente"]


func _crear_colision() -> void:
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	var filas := {}
	for t in celdas:
		if _solida(t):
			if not filas.has(t.y):
				filas[t.y] = []
			filas[t.y].append(t.x)
	for y in filas:
		var xs: Array = filas[y]
		xs.sort()
		var desde: int = xs[0]
		var hasta: int = xs[0]
		for x in xs.slice(1) + [INF]:
			if typeof(x) == TYPE_INT and x == hasta + 1:
				hasta = x
				continue
			var r := Rect2(desde * T, y * T, (hasta - desde + 1) * T, T)
			var forma := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = r.size
			forma.shape = rect
			forma.position = r.get_center()
			cuerpo.add_child(forma)
			if typeof(x) == TYPE_INT:
				desde = x
				hasta = x


# ============================================================
# Pasillos abiertos o cerrados
# ============================================================

## Del lado de la sala actual: ¿se puede ir a la otra punta del pasillo? "" = sí.
func _motivo_cerrado(pasillo: Dictionary) -> String:
	if pasillo.get("salida", false):
		return ""  # el recoveco se pisa siempre; la puerta trabada es la que no deja pasar
	var actual := Estado.sala_actual
	if actual == pasillo["a"]:
		return Estado.motivo_no_movible(pasillo["b"])
	if actual == pasillo["b"]:
		return Estado.motivo_no_movible(pasillo["a"])
	return "no estás en ninguna de las dos salas"


## Recalcula qué pasillos están abiertos, la niebla y la grilla de caminos.
func actualizar() -> void:
	for p in pasillos:
		p["motivo"] = _motivo_cerrado(p)
		p["abierto"] = p["motivo"] == ""
	_niebla_pasillos.queue_redraw()
	queue_redraw()
	_armar_grilla()


# ============================================================
# Dibujo
# ============================================================

func _transitable(t: Vector2i) -> bool:
	return celdas.has(t) and celdas[t]["tipo"] in ["piso", "puerta"]


func _draw() -> void:
	var pisos := ArteNave.tex_pisos()
	var paredes := ArteNave.tex_paredes()
	for t in celdas:
		var d: Dictionary = celdas[t]
		var r := Rect2(Vector2(t) * T, Vector2(T, T))
		match d["tipo"]:
			"piso":
				if salas.has(d["dueno"]):
					draw_texture_rect_region(pisos, r, ArteNave.region_placa(d["material"], d["u"], d["v"]))
				else:
					draw_texture_rect_region(pisos, r, ArteNave.region_tile(d["material"]))
			"frente":
				draw_texture_rect_region(paredes, r, ArteNave.region_frente(d["pared"], d["u"], d["v"]))
				if d["v"] == 0 and not _solida(t + Vector2i.UP):  # filo de arriba, contra el vacío o un piso
					draw_rect(Rect2(r.position, Vector2(T, 3 * E)), ArteNave.COLOR_TAPA)
			"tapa":
				var lados := []
				for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
					if _transitable(t + dir):
						lados.append(dir)
				ArteNave.dibujar_tapa(self, r, lados)


func _dibujar_niebla_pasillos() -> void:
	for p in pasillos:
		var a: String = p["a"]
		var b: String = p["b"]
		if Estado.sala_actual in [a, b]:
			continue
		var visto := Estado.visitadas.has(a) or Estado.visitadas.has(b)
		for r in _rects_de(p["id"]):
			_niebla_pasillos.draw_rect(r, Color(0, 0, 0, 0.6) if visto else Color.BLACK)


# ============================================================
# Caminos (click derecho)
# ============================================================

## Celdas (tiles) por donde se puede caminar ahora: pisos de salas desbloqueadas y pasillos
## (con sus puertas) entre salas desbloqueadas.
func _tile_libre(t: Vector2i) -> bool:
	if not _transitable(t):
		return false
	var dueno: String = celdas[t]["dueno"]
	if salas.has(dueno):
		return Estado.desbloqueadas.has(dueno) and celdas[t]["tipo"] == "piso"
	for p in pasillos:
		if p["id"] == dueno:
			return Estado.desbloqueadas.has(p["a"]) and Estado.desbloqueadas.has(p["b"])
	return false


func _armar_grilla() -> void:
	var minimo := Vector2i(1 << 20, 1 << 20)
	var maximo := -minimo
	for t in celdas:
		minimo = Vector2i(mini(minimo.x, t.x), mini(minimo.y, t.y))
		maximo = Vector2i(maxi(maximo.x, t.x), maxi(maximo.y, t.y))
	if celdas.is_empty():
		return
	var sub := T / CELDA  # celdas de camino por tile
	var region := Rect2i(minimo * sub - Vector2i(1, 1), (maximo - minimo + Vector2i(1, 1)) * sub + Vector2i(2, 2))
	grilla.region = region
	grilla.cell_size = Vector2(CELDA, CELDA)
	grilla.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grilla.update()
	var libre := {}
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var t := Vector2i(floori(float(x) / sub), floori(float(y) / sub))
			if _tile_libre(t):
				libre[Vector2i(x, y)] = true
	# Se achica un borde de una celda para que el personaje no roce las paredes.
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var id := Vector2i(x, y)
			var ok := libre.has(id)
			if ok:
				for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					if not libre.has(id + dir):
						ok = false
						break
			grilla.set_point_solid(id, not ok)
	# Muebles sólidos: sus celdas (con un margen para el cuerpo del personaje) no se pisan.
	for c in salas:
		for r in salas[c].rects_solidos():
			var g: Rect2 = r.grow(5 * E)
			for x in range(int(floor(g.position.x / CELDA)), int(ceil(g.end.x / CELDA))):
				for y in range(int(floor(g.position.y / CELDA)), int(ceil(g.end.y / CELDA))):
					if grilla.is_in_bounds(x, y):
						grilla.set_point_solid(Vector2i(x, y), true)


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


## Camino hasta la celda libre más cercana a un rectángulo (un objeto, quizás sobre un mueble).
func camino_a_rect(desde: Vector2, r: Rect2) -> PackedVector2Array:
	var c := Vector2i((r.get_center() / CELDA).floor())
	var mejor = null
	var mejor_d := INF
	for dx in range(-10, 11):
		for dy in range(-10, 11):
			var id := c + Vector2i(dx, dy)
			if grilla.is_in_boundsv(id) and not grilla.is_point_solid(id):
				var p := Vector2(id) * CELDA + Vector2(CELDA, CELDA) / 2.0
				var cerca := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
				# distancia al borde del objeto; a igualdad, la más cercana al centro
				var d := p.distance_to(cerca) * 1000.0 + p.distance_to(r.get_center())
				if d < mejor_d:
					mejor = id
					mejor_d = d
	var a = _celda_libre(desde)
	if a == null or mejor == null:
		return PackedVector2Array()
	var puntos := PackedVector2Array()
	for id in grilla.get_id_path(a, mejor):
		puntos.append(Vector2(id) * CELDA + Vector2(CELDA, CELDA) / 2.0)
	if puntos.size() > 0:
		puntos.remove_at(0)
	return puntos


## Celda libre más cercana al punto (distancia real, hasta 8 celdas alrededor).
func _celda_libre(punto: Vector2):
	var c := Vector2i((punto / CELDA).floor())
	var mejor = null
	var mejor_d := INF
	for dx in range(-8, 9):
		for dy in range(-8, 9):
			var id := c + Vector2i(dx, dy)
			if grilla.is_in_boundsv(id) and not grilla.is_point_solid(id):
				var d := (Vector2(id) * CELDA + Vector2(CELDA, CELDA) / 2.0).distance_squared_to(punto)
				if d < mejor_d:
					mejor = id
					mejor_d = d
	return mejor
