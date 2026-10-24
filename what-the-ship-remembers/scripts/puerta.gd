extends Node2D
## Puerta de 3x2 tiles en una pared que se ve de frente (arte/tiles/nave_puertas.png). La crea la nave (nave.gd).
## El sprite trae el marco: los tiles de los costados son pared (sólidos) y solo se pasa por el medio.
## Debajo del vano se pinta oscuro.
## Se abre sola cuando el personaje se acerca y el pasillo está abierto; si no, queda cerrada y avisa por qué.
## Sin pasillo = puerta trabada (nunca se abre).

signal aviso(texto: String)

const T := Medidas.TILE
const TAMANO := Vector2(Medidas.ANCHO_PUERTA, T * Medidas.FRENTE)
const VELOCIDAD := 10.0  # cuadros por segundo

var pasillo = null          # Dictionary del pasillo (nave.gd), o null si está trabada
var avisar := true          # false: no avisa al acercarse (la puerta de la sala de la puerta la maneja su objeto)
var _cuadro := 0.0
var _cerca := 0             # personajes dentro del área de cercanía
var _cuerpo: CollisionShape2D


func es_puerta() -> bool:
	return true


func rect_global() -> Rect2:
	return Rect2(position, TAMANO)


func trabada() -> bool:
	return pasillo == null


func se_puede_pasar() -> bool:
	return pasillo != null and pasillo["abierto"]


func _ready() -> void:
	z_index = 1  # debajo de los objetos (2) y de la oscuridad de la sala (3): con poca luz también se oscurece
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	# Marco: sólido siempre, hasta el borde del vano del dibujo (un poco más angosto que su tile,
	# así el paso queda algo más ancho que 1 tile y el personaje no se engancha en las esquinas).
	var a := float(Medidas.ARTE)
	cuerpo.add_child(_forma(Rect2(0, 0, ArteNave.VANO_X0 * a, TAMANO.y)))
	cuerpo.add_child(_forma(Rect2(ArteNave.VANO_X1 * a, 0, TAMANO.x - ArteNave.VANO_X1 * a, TAMANO.y)))
	_cuerpo = _forma(Rect2(ArteNave.VANO_X0 * a, 0, (ArteNave.VANO_X1 - ArteNave.VANO_X0) * a, TAMANO.y))  # la hoja
	cuerpo.add_child(_cuerpo)
	# Área de cercanía: abre la puerta, o avisa por qué no se puede pasar.
	var area := Area2D.new()
	area.add_child(_forma(Rect2(Vector2(T, 0), Vector2(T, TAMANO.y)).grow(T * 0.75)))
	add_child(area)
	area.body_entered.connect(func(b):
		if b.has_method("es_personaje"):
			_cerca += 1
			if trabada():
				if avisar:
					aviso.emit("No cede. Algo la traba.")
			elif not se_puede_pasar():
				aviso.emit("No puedo pasar: " + str(pasillo.get("motivo", "")) + "."))
	area.body_exited.connect(func(b):
		if b.has_method("es_personaje"):
			_cerca = maxi(0, _cerca - 1))


func _forma(r: Rect2) -> CollisionShape2D:
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	forma.shape = rect
	forma.position = r.get_center()
	return forma


func _process(delta: float) -> void:
	if trabada():
		set_process(false)  # nunca se abre: queda siempre en el primer cuadro, sin animación
		return
	var abrir := _cerca > 0 and se_puede_pasar()
	var antes := int(_cuadro)
	if abrir:
		_cuadro = minf(_cuadro + delta * VELOCIDAD, ArteNave.CUADROS_PUERTA - 1)
	else:
		_cuadro = maxf(_cuadro - delta * VELOCIDAD, 0.0)
	# Se puede pasar desde que está casi abierta; vuelve a ser sólida recién cerrada del todo.
	var solida := _cuadro < ArteNave.CUADROS_PUERTA - 1.5
	if _cuerpo.disabled == solida:
		_cuerpo.set_deferred("disabled", not solida)
	if int(_cuadro) != antes:
		queue_redraw()


func _draw() -> void:
	var a := float(Medidas.ARTE)
	draw_rect(Rect2(ArteNave.VANO_X0 * a, ArteNave.VANO_Y0 * a,
			(ArteNave.VANO_X1 - ArteNave.VANO_X0) * a, TAMANO.y - ArteNave.VANO_Y0 * a), ArteNave.COLOR_VANO)
	draw_texture_rect_region(ArteNave.tex_puertas(), Rect2(Vector2.ZERO, TAMANO), ArteNave.region_puerta(int(_cuadro)))
