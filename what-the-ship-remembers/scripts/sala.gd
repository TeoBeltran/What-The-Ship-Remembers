extends Node2D
## Una sala de la nave. Medidas en tiles, del PISO (lo caminable): las paredes van alrededor
## (frente de 2 tiles arriba, 1 tile a los costados y abajo). El piso, las paredes, las puertas y
## los pasillos los arma y dibuja la nave (nave.gd), a partir de estas medidas.
## Acá se dibuja lo que va encima del piso: manchas según el tiempo y muebles; y las capas de
## oscuridad (luz, paso 6) y niebla, que tapan las zonas de la sala que le pasa la nave.
## El tiempo NUNCA se marca con un color: pasado sin manchas, presente pocas, futuro muchas y con óxido.

const TILE := Medidas.TILE
const E := Medidas.ESCALA  # detalles chicos pensados a 16 px

@export var codigo: String = "MAN"       ## Código de la sala en la planilla (MAN, COM, SCO, PTA)
@export var ancho: int = 20              ## Piso en tiles. PAR, para que las placas del piso no queden cortadas
@export var alto: int = 12               ## Piso en tiles. PAR
@export var pos_tiles: Vector2i = Vector2i.ZERO  ## Esquina de arriba a la izquierda del piso, en tiles de la nave
@export_range(0, 15) var piso: int = 0     ## Material del piso (arte/tiles/pisos.png, ver arte_nave.gd)
@export_range(0, 23) var pared: int = 3    ## Frente de la pared de arriba (arte/tiles/paredes.png)
## Puertas trabadas en la pared de arriba: columna (en tiles, PAR) de la mitad izquierda de cada puerta doble.
@export var puertas_trabadas: Array[int] = []

# Manchas semitransparentes: se ve el piso del tileset debajo.
const COLOR_MANCHA := Color(0.12, 0.12, 0.13, 0.35)
const COLOR_MANCHA_OSCURA := Color(0.08, 0.07, 0.06, 0.5)
const COLOR_OXIDO := Color(0.45, 0.25, 0.12, 0.55)
const COLOR_OXIDO_CLARO := Color(0.58, 0.36, 0.18, 0.45)
const COLOR_MUEBLE := Color(0.31, 0.3, 0.29)  # muebles: iguales en todos los tiempos

var manchas: Array = []  # [Rect2, Color]
## Zonas de la sala (piso y sus paredes, sin los pasillos), en coordenadas de la sala. Las arma la nave.
var zonas: Array = []


func tamano() -> Vector2:
	return Vector2(ancho * TILE, alto * TILE)


func centro() -> Vector2:
	return tamano() / 2.0


## Piso de la sala en coordenadas de la nave. Estar acá adentro = estar en la sala
## (las puertas, los pasillos y las aberturas entre sala y pasillo son del pasillo).
func rect_global() -> Rect2:
	return Rect2(position, tamano())


func _ready() -> void:
	if ancho % 2 or alto % 2:
		push_warning("Sala %s: ancho y alto tienen que ser pares (placas de piso de 2x2 tiles)" % codigo)
	position = Vector2(pos_tiles * TILE)
	_crear_muebles()
	_crear_objetos()
	_crear_oscuridad()
	_crear_niebla()
	actualizar_tiempo()
	Estado.turno_empezado.connect(func(_t): actualizar_tiempo())
	Estado.sala_cambiada.connect(func(_s): _niebla.queue_redraw())


## La nave avisa qué zonas son de la sala (cuando ya armó los pasillos).
func poner_zonas(lista: Array) -> void:
	zonas = lista
	_oscuridad.queue_redraw()
	_niebla.queue_redraw()


# ---------------- muebles (fijos en todos los tiempos) ----------------

func _muebles() -> Array:
	return Estado.muebles.filter(func(m): return m["sala"] == codigo)


func _rect_mueble(m: Dictionary) -> Rect2:
	var p: Array = m["pos"]
	return Rect2(p[0] * TILE, p[1] * TILE, p[2] * TILE, p[3] * TILE)


## Colisión de los muebles sólidos (se rodean caminando).
func _crear_muebles() -> void:
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	for r in rects_solidos(false):
		var forma := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		forma.shape = rect
		forma.position = r.get_center()
		cuerpo.add_child(forma)


## Rectángulos de los muebles sólidos (en la sala, o en coordenadas de la nave si global = true).
func rects_solidos(global := true) -> Array:
	var lista := []
	for m in _muebles():
		if m.get("solido", false):
			var r := _rect_mueble(m)
			lista.append(Rect2(r.position + (position if global else Vector2.ZERO), r.size))
	return lista


# ---------------- objetos (paso 4) ----------------

var objetos_nodos: Array = []

func _crear_objetos() -> void:
	var Objeto := preload("res://scripts/objeto.gd")
	var consola := []
	for id in Estado.objetos:
		var o: Dictionary = Estado.objetos[id]
		if o["sala"] != codigo:
			continue
		if codigo == "MAN" and str(o["letra"]).begins_with("N"):
			consola.append(id)  # las conversaciones de NORA van todas en la consola
			continue
		var n = Objeto.new()
		n.configurar([id], o["pos"])
		add_child(n)
		objetos_nodos.append(n)
	if not consola.is_empty():
		consola.sort_custom(func(a, b): return int(a.trim_prefix("MAN_N")) < int(b.trim_prefix("MAN_N")))
		var n = Objeto.new()
		n.configurar(consola, Estado.objetos[consola[0]]["pos"], true)
		add_child(n)
		objetos_nodos.append(n)


# ---------------- oscuridad (luz, paso 6) ----------------
# 0 apagada: no se ve nada · 1 baja: bastante oscura · 2 media: tenue · 3 máxima: nada.
# La luz es de la sala, no del tiempo: no cambia al cambiar de turno.

const OSCURIDAD := [1.0, 0.72, 0.4, 0.0]

var _oscuridad: Node2D
var _tween_luz: Tween

func _crear_oscuridad() -> void:
	_oscuridad = Node2D.new()
	_oscuridad.z_index = 3  # objetos 2 · oscuridad 3 · puertas 4 · personaje 5 · niebla 20
	add_child(_oscuridad)
	_oscuridad.draw.connect(func():
		for r in zonas:
			_oscuridad.draw_rect(r, Color.BLACK))
	_oscuridad.modulate.a = _alfa_oscuridad()
	Estado.luz_cambiada.connect(func(s, _n): if s == codigo: _animar_oscuridad())
	Estado.sala_desbloqueada.connect(func(s): if s == codigo: _animar_oscuridad())
	Estado.turno_empezado.connect(func(_t): _oscuridad.modulate.a = _alfa_oscuridad())


func _alfa_oscuridad() -> float:
	return OSCURIDAD[clampi(int(Estado.luz.get(codigo, 0)), 0, 3)]


## La luz cambia con un fundido corto (los objetos aparecen o desaparecen al instante, debajo).
func _animar_oscuridad() -> void:
	if _tween_luz:
		_tween_luz.kill()
	_tween_luz = create_tween()
	_tween_luz.tween_property(_oscuridad, "modulate:a", _alfa_oscuridad(), 0.35)


# ---------------- niebla ----------------
# Sala actual: se ve normal. Visitada alguna vez: se ve con niebla. Nunca visitada: no se ve.

var _niebla: Node2D

func _crear_niebla() -> void:
	_niebla = Node2D.new()
	_niebla.z_index = 20
	add_child(_niebla)
	_niebla.draw.connect(func():
		if codigo == Estado.sala_actual:
			return
		var color := Color(0, 0, 0, 0.6) if Estado.visitadas.has(codigo) else Color.BLACK
		for r in zonas:
			_niebla.draw_rect(r, color))


func actualizar_tiempo() -> void:
	_generar_manchas(Estado.tiempo_de(codigo))
	queue_redraw()


# ---------------- manchas por tiempo ----------------

func _generar_manchas(tiempo: String) -> void:
	manchas.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(codigo + tiempo)
	var s := tamano()
	var cantidad := 0
	match tiempo:
		"presente": cantidad = 10
		"futuro": cantidad = 40
	for i in cantidad:
		var grande := tiempo == "futuro" and rng.randf() < 0.35
		var w := (rng.randi_range(3, 5) if not grande else rng.randi_range(5, 12)) * E
		var h := (rng.randi_range(2, 4) if not grande else rng.randi_range(3, 8)) * E
		var pos := Vector2(rng.randf_range(2 * E, s.x - 2 * E - w), rng.randf_range(2 * E, s.y - 2 * E - h))
		var color := COLOR_MANCHA
		if tiempo == "futuro":
			var r := rng.randf()
			color = COLOR_OXIDO if r < 0.4 else (COLOR_OXIDO_CLARO if r < 0.55 else COLOR_MANCHA_OSCURA)
		manchas.append([Rect2((pos / E).floor() * E, Vector2(w, h)), color])  # alineadas a la grilla de 16
	# En el futuro también se oxida la pared de arriba (abajo del frente, donde toca el piso).
	if tiempo == "futuro":
		var alto_frente := Medidas.FRENTE * TILE
		for i in 10:
			var largo := rng.randi_range(4, 14) * E
			var h := rng.randi_range(4, 12) * E
			manchas.append([Rect2(rng.randf_range(0, s.x - largo), -h, largo, h), COLOR_OXIDO.darkened(0.3)])
		for i in 4:
			var largo := rng.randi_range(6, 20) * E
			manchas.append([Rect2(rng.randf_range(0, s.x - largo), -alto_frente, largo, rng.randi_range(3, 8) * E), COLOR_MANCHA_OSCURA])


func _draw() -> void:
	for m in manchas:
		draw_rect(m[0], m[1])
	# Muebles fijos (hoja muebles): están en todos los tiempos; en el futuro pueden estar caídos o rotos.
	var futuro := Estado.tiempo_de(codigo) == "futuro"
	var tinte := ArteObjetos.tinte(Estado.tiempo_de(codigo))
	for m in _muebles():
		var r := _rect_mueble(m)
		var estado = m.get("en_futuro") if futuro else null
		# Con sprite: el del futuro si tiene; si no, el mismo caído (girado) o roto (más oscuro y con grieta).
		var spec = m.get("sprite")
		if estado and m.get("sprite_futuro"):
			spec = m["sprite_futuro"]
			estado = null
		elif spec and estado == "caído" and not str(spec).contains("girado"):
			spec = str(spec) + " girado"
		if spec:
			ArteObjetos.dibujar(self, spec, r, tinte.darkened(0.2) if estado == "roto" else tinte, true)
			if estado == "roto" and str(spec) != "ninguno":
				var gx := r.position.x + r.size.x * 0.45
				draw_polyline(PackedVector2Array([Vector2(gx, r.position.y), Vector2(gx + 4 * E, r.get_center().y), Vector2(gx - 2 * E, r.end.y)]), Color(0.1, 0.1, 0.1), 2.0 * E)
			continue
		var c := COLOR_MUEBLE.darkened(0.2) if estado else COLOR_MUEBLE
		draw_rect(r, c)
		draw_rect(r, c.darkened(0.45), false, E)
		match estado:
			"caído":  # silla volcada: patas hacia un costado
				draw_line(r.position + Vector2(2, 2) * E, r.end - Vector2(2, 2) * E, c.darkened(0.6), 2.0 * E)
				draw_line(r.position + Vector2(2 * E, r.size.y - 4 * E), r.end - Vector2(2, 4) * E, c.darkened(0.6), E)
			"roto":  # grieta
				var x := r.position.x + r.size.x * 0.45
				draw_polyline(PackedVector2Array([Vector2(x, r.position.y), Vector2(x + 4 * E, r.get_center().y), Vector2(x - 2 * E, r.end.y)]), c.darkened(0.7), 2.0 * E)
