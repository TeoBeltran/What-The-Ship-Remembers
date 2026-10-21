extends Node2D
## Puerta en el borde de una sala (paso 3). Es el hueco en la pared: la nave arma el pasillo
## hacia la sala "destino" y decide si se puede pasar. Sin destino = puerta trabada (no se pasa).

const ANCHO := float(Medidas.ANCHO_PUERTA)

@export var destino: String = ""                                   ## Sala a la que lleva (vacío = trabada)
@export_enum("arriba", "abajo", "izquierda", "derecha") var lado: String = "derecha"
@export_range(0.0, 1.0) var centro: float = 0.5                    ## Posición a lo largo del lado (0 a 1)

const COLOR_ABIERTA := Color(0.55, 0.6, 0.66)
const COLOR_BLOQUEADA := Color(0.5, 0.16, 0.16)

var _grosor := float(Medidas.PARED)


func es_puerta() -> bool:
	return true


## La ubica sobre el lado que corresponde (la llama la sala).
func ubicar(tamano_sala: Vector2, grosor_pared: float) -> void:
	_grosor = grosor_pared
	match lado:
		"arriba": position = Vector2(centro * tamano_sala.x, grosor_pared / 2.0)
		"abajo": position = Vector2(centro * tamano_sala.x, tamano_sala.y - grosor_pared / 2.0)
		"izquierda": position = Vector2(grosor_pared / 2.0, centro * tamano_sala.y)
		"derecha": position = Vector2(tamano_sala.x - grosor_pared / 2.0, centro * tamano_sala.y)
	queue_redraw()


func _ready() -> void:
	z_index = 4  # por encima de la oscuridad de la sala: las salidas se ven aunque esté apagada
	Estado.sala_desbloqueada.connect(func(_s): queue_redraw())


## Hacia afuera de la sala.
func normal_afuera() -> Vector2:
	match lado:
		"arriba": return Vector2.UP
		"abajo": return Vector2.DOWN
		"izquierda": return Vector2.LEFT
	return Vector2.RIGHT


func bloqueada() -> bool:
	return destino == "" or not Estado.desbloqueadas.has(destino)


func tamano_hueco() -> Vector2:
	return Vector2(ANCHO, _grosor) if lado in ["arriba", "abajo"] else Vector2(_grosor, ANCHO)


func _draw() -> void:
	var t := tamano_hueco()
	draw_rect(Rect2(-t / 2.0, t), COLOR_BLOQUEADA if bloqueada() else COLOR_ABIERTA)
