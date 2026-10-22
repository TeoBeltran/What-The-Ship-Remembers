extends CharacterBody2D
## Personaje con sprite (arte/personaje/personaje.png: 4 cuadros de 30x75, en orden
## abajo, derecha, arriba, izquierda). Se dibuja a escala Medidas.ARTE, como todo el arte.
## Se mueve con flechas/WASD o siguiendo una ruta (click derecho). Las teclas cancelan la ruta.
## La colisión es solo la zona de los pies: la cabeza y el torso pueden tapar paredes y muebles.

const E := Medidas.ESCALA
const VELOCIDAD := 90.0 * E   # ~5,6 tiles por segundo
const TAMANO := Vector2(24, 18) * Medidas.ARTE  # colisión (pies), en píxeles del mundo

const HOJA := "res://arte/personaje/personaje.png"
const CUADRO := Vector2(30, 75)  # en el archivo
const DIBUJO := CUADRO * Medidas.ARTE  # en el mundo
enum { ABAJO, DERECHA, ARRIBA, IZQUIERDA }
const PASO_SEG := 0.16  # cada cuánto alterna el balanceo al caminar
const PASO_PX := 2.0 * Medidas.ARTE  # cuánto sube en el balanceo

var ruta := PackedVector2Array()
var bloqueado := false  # por ejemplo, mientras hay un diálogo abierto
var cinematica := false  # camina solo siguiendo la ruta; las teclas no lo mueven
var objetivo := Rect2()     # si se va hacia un objeto: se frena apenas queda a distancia de interactuar
var alcance_objetivo := 0.0
var _trabado := 0.0  # tiempo sin avanzar siguiendo una ruta (por ejemplo, contra una barrera)

var _hoja: Texture2D
var _mira := ABAJO
var _t_paso := 0.0
var _arriba := false  # fase del balanceo


func es_personaje() -> bool:
	return true


func _ready() -> void:
	z_index = 5
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = TAMANO
	forma.shape = rect
	add_child(forma)
	if ResourceLoader.exists(HOJA):
		_hoja = load(HOJA)


func seguir(nueva_ruta: PackedVector2Array, hacia := Rect2(), alcance := 0.0) -> void:
	ruta = nueva_ruta
	objetivo = hacia
	alcance_objetivo = alcance
	_trabado = 0.0
	queue_redraw()


func detener() -> void:
	ruta = PackedVector2Array()
	velocity = Vector2.ZERO
	queue_redraw()


func _physics_process(delta: float) -> void:
	if bloqueado:
		velocity = Vector2.ZERO
		_animar(delta)
		return
	var dir := Vector2.ZERO
	if not cinematica:
		dir = Vector2(
			_tecla(KEY_D, KEY_RIGHT) - _tecla(KEY_A, KEY_LEFT),
			_tecla(KEY_S, KEY_DOWN) - _tecla(KEY_W, KEY_UP))
	if dir != Vector2.ZERO:
		if not ruta.is_empty():
			detener()
		velocity = dir.normalized() * VELOCIDAD
	elif not ruta.is_empty():
		if alcance_objetivo > 0 and objetivo.grow(alcance_objetivo).has_point(position):
			ruta.clear()  # ya llegó al objeto
		while not ruta.is_empty() and position.distance_to(ruta[0]) < 2.0 * E:
			ruta.remove_at(0)
		if ruta.is_empty():
			velocity = Vector2.ZERO
		else:
			velocity = position.direction_to(ruta[0]) * VELOCIDAD
	else:
		velocity = Vector2.ZERO
	var antes := position
	move_and_slide()
	# Si sigue una ruta y no avanza (barrera cerrada), la abandona.
	if not ruta.is_empty():
		_trabado = _trabado + delta if position.distance_to(antes) < VELOCIDAD * delta * 0.25 else 0.0
		if _trabado > (0.12 if ruta.size() == 1 else 0.3):
			detener()
	_animar(delta)
	queue_redraw()


## Hacia dónde mira (según la velocidad) y balanceo al caminar.
func _animar(delta: float) -> void:
	if velocity.length() < 1.0:
		_t_paso = 0.0
		if _arriba:
			_arriba = false
			queue_redraw()
		return
	if absf(velocity.x) > absf(velocity.y) * 1.1:
		_mira = DERECHA if velocity.x > 0 else IZQUIERDA
	else:
		_mira = ABAJO if velocity.y > 0 else ARRIBA
	_t_paso += delta
	if _t_paso >= PASO_SEG:
		_t_paso -= PASO_SEG
		_arriba = not _arriba


## Mira hacia un punto (por ejemplo, el objeto que investiga).
func mirar_a(punto: Vector2) -> void:
	var d := punto - position
	if absf(d.x) > absf(d.y):
		_mira = DERECHA if d.x > 0 else IZQUIERDA
	else:
		_mira = ABAJO if d.y > 0 else ARRIBA
	queue_redraw()


func _tecla(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _draw() -> void:
	if _hoja:
		# Los pies (última fila del cuadro) apoyan en el borde de abajo de la colisión.
		var arriba_izq := Vector2(-DIBUJO.x / 2.0, TAMANO.y / 2.0 - DIBUJO.y)
		if _arriba:
			arriba_izq.y -= PASO_PX
		# Redondeado al píxel para que el pixel art no tiemble.
		arriba_izq = (arriba_izq + global_position).round() - global_position
		var region := Rect2(Vector2(_mira * CUADRO.x, 0), CUADRO)
		draw_texture_rect_region(_hoja, Rect2(arriba_izq, DIBUJO), region)
	else:
		draw_rect(Rect2(-TAMANO / 2.0, TAMANO), Color.WHITE)
	# Destino del click derecho: una crucecita.
	if not ruta.is_empty():
		var d := to_local(ruta[ruta.size() - 1])
		draw_line(d + Vector2(-3, -3) * E, d + Vector2(3, 3) * E, Color(1, 1, 1, 0.6), E)
		draw_line(d + Vector2(-3, 3) * E, d + Vector2(3, -3) * E, Color(1, 1, 1, 0.6), E)
