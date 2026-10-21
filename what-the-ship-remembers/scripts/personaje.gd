extends CharacterBody2D
## Personaje en greybox (paso 3): rectángulo blanco.
## Se mueve con flechas/WASD o siguiendo una ruta (click derecho). Las teclas cancelan la ruta.

const VELOCIDAD := 90.0
const TAMANO := Vector2(10, 14)

var ruta := PackedVector2Array()
var bloqueado := false  # por ejemplo, mientras hay un diálogo abierto
var cinematica := false  # camina solo siguiendo la ruta; las teclas no lo mueven
var objetivo := Rect2()     # si se va hacia un objeto: se frena apenas queda a distancia de interactuar
var alcance_objetivo := 0.0
var _trabado := 0.0  # tiempo sin avanzar siguiendo una ruta (por ejemplo, contra una barrera)


func es_personaje() -> bool:
	return true


func _ready() -> void:
	z_index = 5
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = TAMANO
	forma.shape = rect
	add_child(forma)


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
		while not ruta.is_empty() and position.distance_to(ruta[0]) < 2.0:
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
	queue_redraw()


func _tecla(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _draw() -> void:
	draw_rect(Rect2(-TAMANO / 2.0, TAMANO), Color.WHITE)
	# Destino del click derecho: una crucecita.
	if not ruta.is_empty():
		var d := to_local(ruta[ruta.size() - 1])
		draw_line(d + Vector2(-3, -3), d + Vector2(3, 3), Color(1, 1, 1, 0.6))
		draw_line(d + Vector2(-3, 3), d + Vector2(3, -3), Color(1, 1, 1, 0.6))
