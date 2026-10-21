extends Node2D
## Una sala en greybox (paso 3): piso, paredes con colisión, manchas según el tiempo, puertas y niebla.
## Las salas se ubican dentro de la nave (escenas/nave.tscn); los pasillos los arma la nave.
## Lenguaje visual (doc 07): piso gris medio, paredes gris oscuro, vacío negro.
## El tiempo NUNCA se marca con un color: pasado sin manchas, presente pocas, futuro muchas y con óxido.

const TILE := 16
const PARED := 8

@export var codigo: String = "MAN"       ## Código de la sala en la planilla (MAN, COM, SCO, PTA)
@export var ancho: int = 20              ## En tiles de 16 px
@export var alto: int = 12

const COLOR_PISO := Color(0.42, 0.42, 0.44)
const COLOR_PARED := Color(0.2, 0.2, 0.22)
const COLOR_MANCHA := Color(0.3, 0.3, 0.31)
const COLOR_MANCHA_OSCURA := Color(0.24, 0.23, 0.22)
const COLOR_OXIDO := Color(0.45, 0.28, 0.17)
const COLOR_OXIDO_CLARO := Color(0.55, 0.36, 0.2)

var manchas: Array = []  # [Rect2, Color]


func tamano() -> Vector2:
	return Vector2(ancho * TILE, alto * TILE)


func centro() -> Vector2:
	return tamano() / 2.0


func puertas() -> Array:
	return get_children().filter(func(n): return n.has_method("es_puerta"))


func puerta_hacia(destino: String) -> Node:
	for p in puertas():
		if p.destino == destino:
			return p
	return null


## Rectángulo de la sala (paredes incluidas) en coordenadas de la nave.
func rect_global() -> Rect2:
	return Rect2(position, tamano())


## Hueco de una puerta en la pared, en coordenadas de la nave.
func hueco_puerta(p) -> Rect2:
	var t: Vector2 = p.tamano_hueco()
	return Rect2(position + p.position - t / 2.0, t)


func _ready() -> void:
	for p in puertas():
		p.ubicar(tamano(), PARED)
	_crear_paredes()
	_crear_objetos()
	_crear_niebla()
	actualizar_tiempo()
	Estado.turno_empezado.connect(func(_t): actualizar_tiempo())
	Estado.sala_cambiada.connect(func(_s): _niebla.queue_redraw())


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
		_niebla.draw_rect(Rect2(Vector2.ZERO, tamano()), color))


func actualizar_tiempo() -> void:
	_generar_manchas(Estado.tiempo_de(codigo))
	queue_redraw()


# ---------------- paredes ----------------

func _crear_paredes() -> void:
	var s := tamano()
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	# Cada lado se arma con tramos, dejando huecos donde hay puertas.
	for lado in ["arriba", "abajo", "izquierda", "derecha"]:
		var horizontal: bool = lado in ["arriba", "abajo"]
		var largo: float = s.x if horizontal else s.y
		var huecos := []
		for p in puertas():
			if p.lado == lado:
				huecos.append(Vector2(p.centro * largo - p.ANCHO / 2.0, p.centro * largo + p.ANCHO / 2.0))
		huecos.sort_custom(func(a, b): return a.x < b.x)
		var desde := 0.0
		var tramos := []
		for h in huecos:
			tramos.append(Vector2(desde, h.x))
			desde = h.y
		tramos.append(Vector2(desde, largo))
		for t in tramos:
			if t.y - t.x <= 0:
				continue
			var r: Rect2
			match lado:
				"arriba": r = Rect2(t.x, 0, t.y - t.x, PARED)
				"abajo": r = Rect2(t.x, s.y - PARED, t.y - t.x, PARED)
				"izquierda": r = Rect2(0, t.x, PARED, t.y - t.x)
				"derecha": r = Rect2(s.x - PARED, t.x, PARED, t.y - t.x)
			var forma := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = r.size
			forma.shape = rect
			forma.position = r.get_center()
			cuerpo.add_child(forma)


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
		var w := rng.randi_range(3, 5) if not grande else rng.randi_range(5, 12)
		var h := rng.randi_range(2, 4) if not grande else rng.randi_range(3, 8)
		var pos := Vector2(rng.randf_range(PARED + 2, s.x - PARED - 2 - w), rng.randf_range(PARED + 2, s.y - PARED - 2 - h))
		var color := COLOR_MANCHA
		if tiempo == "futuro":
			var r := rng.randf()
			color = COLOR_OXIDO if r < 0.4 else (COLOR_OXIDO_CLARO if r < 0.55 else COLOR_MANCHA_OSCURA)
		manchas.append([Rect2(pos.floor(), Vector2(w, h)), color])
	# En el futuro también se manchan las paredes (óxido en los bordes).
	if tiempo == "futuro":
		for i in 14:
			var lado := rng.randi_range(0, 3)
			var largo := rng.randi_range(6, 20)
			var r: Rect2
			match lado:
				0: r = Rect2(rng.randf_range(0, s.x - largo), 0, largo, PARED)
				1: r = Rect2(rng.randf_range(0, s.x - largo), s.y - PARED, largo, PARED)
				2: r = Rect2(0, rng.randf_range(0, s.y - largo), PARED, largo)
				3: r = Rect2(s.x - PARED, rng.randf_range(0, s.y - largo), PARED, largo)
			manchas.append([r.abs(), COLOR_OXIDO.darkened(0.35)])


func _draw() -> void:
	var s := tamano()
	draw_rect(Rect2(Vector2.ZERO, s), COLOR_PARED)
	draw_rect(Rect2(Vector2(PARED, PARED), s - Vector2(PARED, PARED) * 2), COLOR_PISO)
	for m in manchas:
		draw_rect(m[0], m[1])
