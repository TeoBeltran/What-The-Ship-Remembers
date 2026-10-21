extends Node2D
## Objeto investigable en greybox (paso 4): un rectángulo de color en su lugar de la sala.
## Se dibuja si el núcleo dice que se ve (activo, en su tiempo, no desdibujado y con luz suficiente).
## Los objetos que ocupan el mismo lugar (por ejemplo, la tijera en los tres tiempos) tienen el mismo color.
## La consola de NORA es un solo objeto que agrupa todas las conversaciones (MAN_N1…N13).

const TILE := 16

var ids: Array[String] = []   # un id, o varios si es la consola de NORA
var rect := Rect2()           # en coordenadas de la sala
var color := Color.WHITE
var es_consola := false
var mostrar_id := false       # modo depuración (F1)


func configurar(lista: Array, pos: Array, consola := false) -> void:
	ids.assign(lista)
	es_consola = consola
	rect = Rect2(pos[0] * TILE, pos[1] * TILE, pos[2] * TILE, pos[3] * TILE)
	# Color estable según el lugar: lo que está en el mismo lugar se ve igual en todos los tiempos.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4i(pos[0], pos[1], pos[2], pos[3]))
	color = Color.from_hsv(rng.randf(), 0.45, 0.8)
	if consola:
		color = Color(0.3, 0.75, 0.85)


func _ready() -> void:
	z_index = 2
	for s in [Estado.objeto_activado, Estado.objeto_usado, Estado.sala_cambiada, Estado.luz_cambiada, Estado.turno_empezado]:
		s.connect(func(_a = null, _b = null): queue_redraw())


## Id que se usaría al interactuar ahora ("" = ninguno). En la consola, la primera conversación disponible.
func id_usable() -> String:
	for id in ids:
		if Estado.se_puede_usar(id):
			return id
	return ""


## Id para explicar por qué no se puede usar (el primero que se ve y no está usado).
func id_visible_pendiente() -> String:
	for id in ids:
		if Estado.se_ve(id) and not Estado.obj[id]["usado"] and not Estado.es_solo_visual(id):
			return id
	return ""


func se_ve() -> bool:
	if es_consola:
		return Estado.sala_actual == "MAN" or Estado.visitadas.has("MAN")  # la consola siempre está
	for id in ids:
		if Estado.se_ve(id):
			return true
	return false


func rect_global() -> Rect2:
	return Rect2(get_parent().position + rect.position, rect.size)


func _draw() -> void:
	if not se_ve():
		return
	var c := color
	# Ya usado (y no hay nada más para hacer): más apagado.
	if id_visible_pendiente() == "":
		c = c.darkened(0.35)
	draw_rect(rect, c)
	draw_rect(rect, c.darkened(0.5), false, 1.0)
	if mostrar_id:
		var texto := "NORA" if es_consola else ids[0]
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, -2), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.YELLOW)
