extends Node2D
## La nave del Alfa como un solo espacio continuo, armado en una grilla de tiles (como un map maker).
## Las salas (escenas/salas/) dicen dónde está su piso y qué arte usan; acá se arma todo lo demás:
## - las paredes de cada sala: frente de 2 tiles arriba (se ve de frente), 1 tile a los costados y abajo;
## - los pasillos entre salas conectadas (datos/conexiones.json) y sus puertas (siempre puertas dobles
##   en una pared que se ve de frente: nunca puertas de costado);
## - la colisión, el dibujo del piso y las paredes, la niebla de los pasillos y la grilla de caminos.
## Vista: se ve solo la zona donde está parado el personaje. Cada celda tiene una "zona": la sala, o el
## pasillo. Lo que está del lado de una sala hasta su puerta (recoveco, abertura, la puerta misma) es de
## esa sala; lo que queda entre las dos puertas es del pasillo. Parado en una sala, el interior de los
## pasillos se ve negro; parado en un pasillo, las salas se ven negras.
## Moverse de sala se cobra al ENTRAR al piso de la otra sala (lo detecta el juego con sala_en()).
##
## Las puertas miden 3x2 tiles (Medidas.PUERTA_TILES): marco a los costados (sólido) y el paso en el
## tile del medio. Los pisos de adelante y de atrás de cada puerta llevan la franja amarilla.
##
## Pasillo de costado (sala A a la izquierda, sala B a la derecha, misma altura), visto en tiles:
##   entre la pared de A y la de B hay 8 columnas (puerta de 3, tabique de 2, puerta de 3).
##   Se arma desde abajo (b = fila de la pared de abajo de las salas), así entra en salas de 6 de alto:
##     filas b-8, b-7  frente de pared (a la altura del frente de las salas si miden 6)
##     filas b-6, b-5  pasillo de arriba (une las dos puertas)
##     filas b-4, b-3  pared de frente con una puerta de cada lado (en el medio, pared con el panel)
##     filas b-2, b-1  dos recovecos abiertos hacia su sala (la abertura en la pared es del pasillo)
##                     separados por un tabique de 2 tiles
##     fila b          pared de abajo
##   Así, vayas para donde vayas, siempre entrás por una puerta que se ve de frente.
## Salida trabada a la derecha (sala.salida_trabada_derecha): la mitad izquierda de un pasillo de costado,
##   el recoveco y la puerta de frente, que nunca abre.
## Pasillo hacia arriba (sala A arriba, sala B abajo): 3 tiles de ancho, en el medio de B (si B mide par,
##   medio tile a la izquierda); tiene que caer entero dentro de A. Una puerta en el frente de B y otra en
##   el frente propio del pasillo, justo debajo de la pared de A.

signal aviso(texto: String)

const T := Medidas.TILE
const CELDA := Medidas.CELDA  # grilla de caminos (px)
const E := Medidas.ESCALA
const F := Medidas.FRENTE     # alto del frente de pared, en tiles

const P := Medidas.PUERTA_TILES  # ancho de una puerta, en tiles

## Arte de los pasillos (números de arte_nave.gd).
const PISO_PASILLO := ArteNave.PISO_REJILLA

## Pared de arriba de los pasillos de costado (8 columnas): un diseño fijo por pasillo, no al azar.
## Lisa a los costados y un tramo de cables con la pantalla en el medio. [pared, espejada].
const _L := [ArteNave.PARED_LISA, false]
const _A := [ArteNave.PARED_ABRAZADERA, false]
const _A2 := [ArteNave.PARED_ABRAZADERA, true]   # abrazadera espejada: cierra el tramo a la derecha
const _C := [ArteNave.PARED_CABLES, false]
const _S := [ArteNave.PARED_PANTALLA, false]
const PATRONES_PASILLO := [
	[_L, _L, _A, _S, _C, _A2, _L, _L],
	[_L, _L, _A, _C, _S, _A2, _L, _L],
]

const Puerta := preload("res://scripts/puerta.gd")

var salas: Dictionary = {}     # codigo -> nodo sala
var pasillos: Array = []       # {id, a, b, piso: Rect2, abierto, motivo, puertas}
var puertas: Array = []
var grilla := AStarGrid2D.new()

## Plano de la nave: Vector2i (tile) -> {tipo, dueno, ...}
## tipo: "piso" | "tapa" (pared vista desde arriba) | "frente" (pared vista de frente)
##       | "marco" (costado de una puerta: lo dibuja y lo choca la puerta) | "puerta" (el paso de una puerta)
## dueno: código de sala, o id del pasillo ("P0", "P1"...)
## zona: qué se ve junto (ver arriba): código de sala, o id del pasillo para su interior
## puerta_de: en las celdas de una puerta que da a un pasillo, el id del pasillo. Esas puertas se ven
##   desde los dos lados: desde su sala y desde adentro del pasillo.
var celdas: Dictionary = {}

var _niebla_pasillos: Node2D
var _puertas_tiles: Array = []  # esquina de arriba a la izquierda (tile) de cada puerta
var _zona := ""                 # zona de las celdas que se están armando ("" = la del dueño)
var _patron := 0                # próximo diseño de pared de pasillo
## Zona donde está parado el personaje (sala o pasillo). La usa la niebla.
var vista := ""


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
	_marcar_umbrales()
	_crear_colision()
	for c in salas:
		var sala = salas[c]
		var a_sala := func(r): return Rect2(r.position - sala.position, r.size)
		sala.poner_zonas(_rects_de(c).map(a_sala), _rects_de(c, "", true).map(a_sala))
	_niebla_pasillos = Node2D.new()
	_niebla_pasillos.z_index = 20
	add_child(_niebla_pasillos)
	_niebla_pasillos.draw.connect(_dibujar_niebla_pasillos)
	vista = Estado.sala_actual
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


## Zona (sala o pasillo) de la celda donde está el punto, o "" si no hay nada.
func zona_en(punto: Vector2) -> String:
	var t := Vector2i((punto / T).floor())
	return celdas[t]["zona"] if celdas.has(t) else ""


## El juego avisa dónde está el personaje (sus pies): si cambió de zona, se rehace la niebla.
func poner_vista(punto: Vector2) -> void:
	var z := zona_en(punto)
	if z == "" or z == vista:
		return
	vista = z
	_niebla_pasillos.queue_redraw()
	for c in salas:
		salas[c].refrescar_niebla()


## ¿El personaje está en el interior de un pasillo?
func en_pasillo() -> bool:
	return not salas.has(vista)


# ============================================================
# Plano
# ============================================================

func _poner(t: Vector2i, tipo: String, dueno: String, extra := {}) -> void:
	var d := {"tipo": tipo, "dueno": dueno, "zona": _zona if _zona != "" else dueno}
	d.merge(extra, true)
	celdas[t] = d


func _armar_sala(s) -> void:
	var o: Vector2i = s.pos_tiles
	var w: int = s.ancho
	var h: int = s.alto
	for x in w:
		for y in h:
			_poner(o + Vector2i(x, y), "piso", s.codigo, {"material": s.piso})
		for v in F:  # frente de arriba
			_poner(o + Vector2i(x, v - F), "frente", s.codigo, {"pared": ArteNave.PARED_LISA, "v": v})
	for y in range(-F, h + 1):  # costados
		_poner(o + Vector2i(-1, y), "tapa", s.codigo)
		_poner(o + Vector2i(w, y), "tapa", s.codigo)
	for x in range(-1, w + 1):  # abajo
		_poner(o + Vector2i(x, h), "tapa", s.codigo)
	for col in s.puertas_trabadas:
		_crear_puerta(o + Vector2i(col, -F), s.codigo, null, false)  # la maneja el objeto de la planilla


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
	var cols := 2 * P + 2  # puerta, tabique de 2, puerta
	if xb - xa != cols + 1 or der.pos_tiles.y != y0 or izq.alto != der.alto or izq.alto < 6:
		push_error("Pasillo %s-%s: las salas tienen que estar a la misma altura, medir lo mismo de alto (>= 6) y tener %d tiles entre sus paredes" % [izq.codigo, der.codigo, cols])
		return
	var p := _nuevo_pasillo(izq.codigo, der.codigo)
	var id: String = p["id"]
	y0 = izq.pos_tiles.y + izq.alto - 9  # así b (pared de abajo) = y0 + 9
	var patron: Array = PATRONES_PASILLO[_patron % PATRONES_PASILLO.size()]
	_patron += 1
	for i in cols:
		var x := xa + 1 + i
		var pared: Array = patron[i] if i < patron.size() else _L
		_zona = ""  # interior del pasillo: pared de arriba y pasillo de arriba
		_poner(Vector2i(x, y0 + 1), "frente", id, {"pared": pared[0], "espejo": pared[1], "v": 0})
		_poner(Vector2i(x, y0 + 2), "frente", id, {"pared": pared[0], "espejo": pared[1], "v": 1})
		_piso_pasillo(p, Vector2i(x, y0 + 3))
		_piso_pasillo(p, Vector2i(x, y0 + 4))
		_zona = izq.codigo if i <= P else der.codigo  # de la puerta para abajo: lado de cada sala
		if i in [P, P + 1]:  # pared del medio, entre las dos puertas
			_poner(Vector2i(x, y0 + 5), "frente", id, {"pared": ArteNave.PARED_LISA, "v": 0})
			_poner(Vector2i(x, y0 + 6), "frente", id, {"pared": ArteNave.PARED_LISA, "v": 1})
			_poner(Vector2i(x, y0 + 7), "tapa", id)  # tabique entre los recovecos
			_poner(Vector2i(x, y0 + 8), "tapa", id)
		else:
			_piso_pasillo(p, Vector2i(x, y0 + 7))
			_piso_pasillo(p, Vector2i(x, y0 + 8))
		_poner(Vector2i(x, y0 + 9), "tapa", id)
	# Aberturas en las paredes de las salas (son parte del pasillo).
	for y in [y0 + 7, y0 + 8]:
		_zona = izq.codigo
		_piso_pasillo(p, Vector2i(xa, y))
		_zona = der.codigo
		_piso_pasillo(p, Vector2i(xb, y))
	_zona = izq.codigo
	_crear_puerta(Vector2i(xa + 1, y0 + 5), id, p)
	_zona = der.codigo
	_crear_puerta(Vector2i(xa + 1 + P + 2, y0 + 5), id, p)
	_zona = ""


## Recoveco abierto hacia la sala, a la derecha, con una puerta trabada de frente (sala común en el Alfa:
## según el mapa, la sala común sigue hacia la derecha, al resto de la nave).
func _salida_trabada(s) -> void:
	var xa: int = s.pos_tiles.x + s.ancho   # columna de la pared derecha de la sala
	var y0: int = s.pos_tiles.y + s.alto - 9  # mismas filas que un pasillo de costado (b = y0 + 9)
	var p := _nuevo_pasillo(s.codigo, s.codigo)
	p["salida"] = true
	var id: String = p["id"]
	_zona = s.codigo  # se ve con la sala
	for y in [y0 + 7, y0 + 8]:
		for x in range(xa, xa + 1 + P):        # abertura en la pared de la sala + recoveco
			_piso_pasillo(p, Vector2i(x, y))
	for x in range(xa + 1, xa + 2 + P):
		_poner(Vector2i(x, y0 + 3), "tapa", id)
		_poner(Vector2i(x, y0 + 4), "tapa", id)
		_poner(Vector2i(x, y0 + 9), "tapa", id)
	for y in range(y0 + 5, y0 + 9):
		_poner(Vector2i(xa + 1 + P, y), "tapa", id)
	_crear_puerta(Vector2i(xa + 1, y0 + 5), id, null)
	_zona = ""


func _pasillo_arriba(arriba, abajo) -> void:
	var c: int = abajo.pos_tiles.x + (abajo.ancho - P) / 2   # columna izquierda de la puerta
	var y_pared: int = arriba.pos_tiles.y + arriba.alto     # pared de abajo de la sala de arriba
	var y_frente_b: int = abajo.pos_tiles.y - F             # frente de la sala de abajo
	if c < arriba.pos_tiles.x or c + P > arriba.pos_tiles.x + arriba.ancho or y_frente_b - (y_pared + 1 + F) < 1:
		push_error("Pasillo %s-%s: la puerta (columnas %d a %d) tiene que caer dentro de la sala de arriba, y tiene que haber lugar para el pasillo" % [arriba.codigo, abajo.codigo, c, c + P - 1])
		return
	var p := _nuevo_pasillo(arriba.codigo, abajo.codigo)
	var id: String = p["id"]
	for x in range(c, c + P):
		_zona = arriba.codigo
		_piso_pasillo(p, Vector2i(x, y_pared))  # abertura en la pared de la sala de arriba
		_zona = ""
		for y in range(y_pared + 1 + F, y_frente_b):
			_piso_pasillo(p, Vector2i(x, y))
	for y in range(y_pared + 1, y_frente_b):
		_zona = arriba.codigo if y < y_pared + 1 + F else ""
		_poner(Vector2i(c - 1, y), "tapa", id)
		_poner(Vector2i(c + P, y), "tapa", id)
	_zona = arriba.codigo
	_crear_puerta(Vector2i(c, y_pared + 1), id, p)
	_zona = abajo.codigo
	_crear_puerta(Vector2i(c, y_frente_b), id, p)
	_zona = ""


func _crear_puerta(t: Vector2i, dueno: String, pasillo, avisar := true) -> void:
	var extra := {"puerta_de": pasillo["id"]} if pasillo != null else {}
	for dx in P:
		for dy in F:
			_poner(t + Vector2i(dx, dy), "puerta" if dx == P / 2 else "marco", dueno, extra)
	_puertas_tiles.append(t)
	var pu = Puerta.new()
	pu.position = Vector2(t) * T
	pu.pasillo = pasillo
	pu.avisar = avisar
	pu.aviso.connect(func(txt): aviso.emit(txt))
	add_child(pu)
	puertas.append(pu)
	if pasillo != null:
		pasillo["puertas"].append(pu)


## Franja amarilla en el piso de adelante (franja arriba, tocando la puerta) y de atrás de cada puerta.
func _marcar_umbrales() -> void:
	for t in _puertas_tiles:
		for dx in P:
			var abajo: Vector2i = t + Vector2i(dx, F)
			var arriba: Vector2i = t + Vector2i(dx, -1)
			if celdas.has(abajo) and celdas[abajo]["tipo"] == "piso":
				celdas[abajo]["material"] = ArteNave.PISO_FRANJA_ARRIBA
			if celdas.has(arriba) and celdas[arriba]["tipo"] == "piso":
				celdas[arriba]["material"] = ArteNave.PISO_FRANJA_ABAJO


## Rectángulos (en px de la nave) de las celdas de una zona, juntando tramos de cada fila.
## Sin las puertas que dan a un pasillo (esas tienen su propia niebla, ver _dibujar_niebla_pasillos).
## todas = true: todas las celdas de la zona, puertas incluidas (para la oscuridad).
func _rects_de(zona: String, puerta_de := "", todas := false) -> Array:
	var por_fila := {}
	for t in celdas:
		if celdas[t]["zona"] == zona and (todas or celdas[t].get("puerta_de", "") == puerta_de):
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
	return celdas.has(t) and celdas[t]["tipo"] in ["tapa", "frente", "marco"]


func _crear_colision() -> void:
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	var filas := {}
	for t in celdas:
		if _solida(t) and celdas[t]["tipo"] != "marco":  # el marco lo choca la puerta (ver puerta.gd)
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
	var tex := ArteNave.tex_nave()
	for t in celdas:
		var d: Dictionary = celdas[t]
		var r := Rect2(Vector2(t) * T, Vector2(T, T))
		match d["tipo"]:
			"piso":
				draw_texture_rect_region(tex, r, ArteNave.region_piso(d["material"]))
			"frente":
				if d.get("espejo", false):
					draw_set_transform(r.position + Vector2(T, 0), 0.0, Vector2(-1, 1))
					draw_texture_rect_region(tex, Rect2(Vector2.ZERO, r.size), ArteNave.region_frente(d["pared"], d["v"]))
					draw_set_transform(Vector2.ZERO)
				else:
					draw_texture_rect_region(tex, r, ArteNave.region_frente(d["pared"], d["v"]))
			"tapa":
				var lados := []
				for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
					if _transitable(t + dir):
						lados.append(dir)
				ArteNave.dibujar_tapa(self, r, lados)


## El interior de un pasillo se ve solo estando adentro; desde cualquier otro lado, negro.
## Sus puertas se ven desde su sala y desde adentro del pasillo; si no, como la sala de su lado.
func _dibujar_niebla_pasillos() -> void:
	for p in pasillos:
		var id: String = p["id"]
		if id != vista:
			for r in _rects_de(id):
				_niebla_pasillos.draw_rect(r, Color.BLACK)
		for sala in [p["a"], p["b"]]:
			if vista in [id, sala]:
				continue
			var color := Color.BLACK if en_pasillo() or not Estado.visitadas.has(sala) else Color(0, 0, 0, 0.6)
			for r in _rects_de(sala, id):
				_niebla_pasillos.draw_rect(r, color)


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
				# El paso de una puerta mide 1 tile: ahí no se achica a los costados (son el marco).
				var t := Vector2i(floori(float(x) / sub), floori(float(y) / sub))
				var dirs := [Vector2i.UP, Vector2i.DOWN] if celdas[t]["tipo"] == "puerta" else [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
				for dir in dirs:
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
