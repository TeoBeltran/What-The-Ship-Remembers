extends Node2D
## Puerta doble (2x2 tiles) en una pared que se ve de frente. La crea la nave (nave.gd).
## Se dibuja: la pared de esa sala/pasillo (se ve en los 24 px de arriba), el vano oscuro y
## dos sprites de puerta (el de la derecha espejado, para que quede simétrica).
## Se abre sola cuando el personaje se acerca y el pasillo está abierto; si no, queda cerrada y avisa por qué.
## Sin pasillo = puerta trabada (nunca se abre).

signal aviso(texto: String)

const T := Medidas.TILE
const TAMANO := Vector2(Medidas.ANCHO_PUERTA, T * Medidas.FRENTE)
const VELOCIDAD := 14.0  # cuadros por segundo

var pasillo = null          # Dictionary del pasillo (nave.gd), o null si está trabada
var pared := 3              # bloque de pared que va detrás (arte_nave.gd)
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
	z_index = 4  # por encima de la oscuridad de la sala: las salidas se ven aunque esté apagada
	var cuerpo := StaticBody2D.new()
	add_child(cuerpo)
	_cuerpo = _forma(Rect2(Vector2.ZERO, TAMANO))
	cuerpo.add_child(_cuerpo)
	# Área de cercanía: abre la puerta, o avisa por qué no se puede pasar.
	var area := Area2D.new()
	area.add_child(_forma(Rect2(Vector2.ZERO, TAMANO).grow(T * 0.75)))
	add_child(area)
	area.body_entered.connect(func(b):
		if b.has_method("es_personaje"):
			_cerca += 1
			if trabada():
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
	# Pared detrás (se ve arriba de la hoja de la puerta) y vano oscuro.
	draw_texture_rect_region(ArteNave.tex_paredes(), Rect2(Vector2.ZERO, TAMANO), ArteNave.region_pared(pared))
	draw_rect(Rect2(Vector2(0, T / 2.0), Vector2(TAMANO.x, TAMANO.y - T / 2.0)), ArteNave.COLOR_VANO)
	var tex := ArteNave.tex_puerta()
	var region := ArteNave.region_puerta(int(_cuadro))
	draw_texture_rect_region(tex, Rect2(0, 0, T, TAMANO.y), region)
	draw_set_transform(Vector2(TAMANO.x, 0), 0.0, Vector2(-1, 1))  # hoja derecha espejada
	draw_texture_rect_region(tex, Rect2(0, 0, T, TAMANO.y), region)
	draw_set_transform(Vector2.ZERO)
