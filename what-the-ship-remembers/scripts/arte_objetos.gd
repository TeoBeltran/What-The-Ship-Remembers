class_name ArteObjetos
## Dibuja objetos y muebles con los sprites de las hojas de arte (catálogo: hoja "sprites" de la planilla).
## Un sprite se escribe como "nombre [opciones]":
##   girado  → rotado 90° (una silla caída)
##   espejo  → dado vuelta horizontalmente
##   repetir → se repite a lo ancho del rectángulo (dos mesas juntas)
##   doble   → dos copias, la segunda espejada (puerta doble)
##   pared   → apoyado en la pared de arriba (su base queda en el borde de arriba del rectángulo)
## "ninguno" = no se dibuja nada. Vacío = cuadro de color (greybox).
## El arte está hecho a 48 px por tile, igual que Medidas.TILE: se dibuja 1:1, sin escalar.

const HOJAS := {
	"cosas": "res://arte/tiles/objetos/cosas.png",
	"cosas2": "res://arte/tiles/objetos/cosas2.png",
	"pantallas": "res://arte/tiles/objetos/pantallas.png",
	"puerta": "res://arte/tiles/puerta.png",
}
## Cómo se ve cada tiempo (los objetos y muebles envejecen con la sala).
const TINTE_TIEMPO := {
	"pasado": Color(1, 1, 1),
	"presente": Color(0.9, 0.9, 0.9),
	"futuro": Color(0.72, 0.66, 0.6),
}

static var _texturas := {}


static func tinte(tiempo: String) -> Color:
	return TINTE_TIEMPO.get(tiempo, Color.WHITE)


## Dibuja el sprite en el rectángulo. Devuelve false si no hay sprite (el que llama dibuja el cuadro).
## Objetos: centrados en el rectángulo. Muebles (apoyar = true): apoyados en el borde de abajo.
static func dibujar(ci: CanvasItem, spec, rect: Rect2, color := Color.WHITE, apoyar := false) -> bool:
	if spec == null or str(spec) == "":
		return false
	var partes := str(spec).split(" ", false)
	var nombre := partes[0]
	if nombre == "ninguno":
		return true
	if not Estado.sprites.has(nombre):
		push_warning("Sprite desconocido: " + nombre)
		return false
	var s: Dictionary = Estado.sprites[nombre]
	var tex := _textura(s["hoja"])
	if tex == null:
		return false
	var r: Array = s["region"]
	var origen := Rect2(r[0], r[1], r[2], r[3])
	var girado := partes.has("girado")
	var tam := Vector2(origen.size.y, origen.size.x) if girado else origen.size
	var n := 1
	if partes.has("doble"):
		n = 2
	elif partes.has("repetir"):
		n = maxi(1, int(floor(rect.size.x / tam.x + 0.1)))  # tolera unos píxeles de más
	var x0 := roundf(rect.get_center().x - tam.x * n / 2.0)
	var y0: float
	if partes.has("pared"):
		y0 = rect.position.y - tam.y
	elif apoyar:
		y0 = rect.end.y - tam.y
	else:
		y0 = rect.get_center().y - tam.y / 2.0
	y0 = roundf(y0)
	for i in n:
		var espejo := partes.has("espejo") != (partes.has("doble") and i == 1)
		var centro := Vector2(x0 + tam.x * (i + 0.5), y0 + tam.y / 2.0)
		ci.draw_set_transform(centro, PI / 2.0 if girado else 0.0, Vector2(-1 if espejo else 1, 1))
		ci.draw_texture_rect_region(tex, Rect2(-origen.size / 2.0, origen.size), origen, color)
	ci.draw_set_transform(Vector2.ZERO)
	return true


static func _textura(hoja: String) -> Texture2D:
	if not _texturas.has(hoja):
		_texturas[hoja] = load(HOJAS[hoja]) if HOJAS.has(hoja) else null
	return _texturas[hoja]
