class_name ArteNave
## Pisos, paredes y puertas de la nave (arte/tiles). Los archivos están en una grilla de 48 px
## (Medidas.TILE_ARTE); las regiones de acá son en píxeles del archivo y se dibujan en tiles del mundo
## (Medidas.TILE = 48 x Medidas.ARTE).
##
## nave_paredes.png (384x576, grilla de 8x12 tiles; lo que no está pintado no se usa):
##   pisos de 1x1, arriba a la izquierda:
##     0 liso (col 1, fila 1)            1 rejilla (col 2, fila 1)
##     2 franja amarilla arriba (col 1, fila 2)   3 franja amarilla abajo (col 2, fila 2)
##   paredes (frente) de 1 tile de ancho x 2 de alto, en las filas 3 y 4:
##     0 lisa (col 1)                     1 cables con abrazadera (col 2)
##     2 pantalla con cables (col 3)      3 cables solos (col 4)
##   Casi todo es pared lisa. Los cables y la pantalla solo van en los pasillos, con un diseño fijo
##   (nave.gd, PATRONES_PASILLO). La abrazadera espejada cierra un tramo de cables del lado derecho.
## nave_puertas.png (144x288): 3 cuadros de 3x2 tiles (144x96), de arriba a abajo:
##   cerrada, a medio abrir, abierta. Incluye la pared de los costados (el marco).
##   El vano (lo que en el original estaba pintado de blanco) es transparente: debajo se pinta oscuro.

const RUTA_NAVE := "res://arte/tiles/nave_paredes.png"
const RUTA_PUERTAS := "res://arte/tiles/nave_puertas.png"

const T := Medidas.TILE_ARTE  # en el archivo

const PISO_LISO := 0
const PISO_REJILLA := 1
const PISO_FRANJA_ARRIBA := 2  # delante de una puerta (la franja toca la puerta)
const PISO_FRANJA_ABAJO := 3   # detrás de una puerta
const CANT_PISOS := 4

const PARED_LISA := 0
const PARED_ABRAZADERA := 1
const PARED_PANTALLA := 2
const PARED_CABLES := 3
const CANT_PAREDES := 4

const CUADROS_PUERTA := 3
## Vano de la puerta abierta, en píxeles del archivo dentro de un cuadro (x desde, x hasta, y desde).
const VANO_X0 := 44
const VANO_X1 := 100
const VANO_Y0 := 16

const COLOR_TAPA := Color(0.11, 0.12, 0.13)        # pared vista desde arriba (costados y abajo)
const COLOR_TAPA_BORDE := Color(0.3, 0.33, 0.35)   # filo de la tapa, del lado del piso
const COLOR_VANO := Color(0.03, 0.03, 0.04)        # lo que se ve por la puerta abierta

static var _cache := {}


static func _tex(ruta: String) -> Texture2D:
	if not _cache.has(ruta):
		_cache[ruta] = load(ruta)
	return _cache[ruta]


static func tex_nave() -> Texture2D:
	return _tex(RUTA_NAVE)


static func tex_puertas() -> Texture2D:
	return _tex(RUTA_PUERTAS)


## Tile de piso n (0..3).
static func region_piso(n: int) -> Rect2:
	n = clampi(n, 0, CANT_PISOS - 1)
	return Rect2((n % 2) * T, (n / 2) * T, T, T)


## Mitad v (0 arriba, 1 abajo) de la pared k (0..3).
static func region_frente(k: int, v: int) -> Rect2:
	k = clampi(k, 0, CANT_PAREDES - 1)
	return Rect2(k * T, (2 + v) * T, T, T)


## Cuadro k de la puerta (0 cerrada, 1 a medio abrir, 2 abierta): 3x2 tiles.
static func region_puerta(k: int) -> Rect2:
	return Rect2(0, clampi(k, 0, CUADROS_PUERTA - 1) * 2 * T, 3 * T, 2 * T)


## Tapa de pared: oscura, con un filo claro en cada lado que da a un piso.
static func dibujar_tapa(lienzo: CanvasItem, celda: Rect2, lados_piso: Array) -> void:
	lienzo.draw_rect(celda, COLOR_TAPA)
	var g := Medidas.ESCALA
	for lado in lados_piso:
		var filo: Rect2
		match lado:
			Vector2i.RIGHT: filo = Rect2(celda.end.x - g, celda.position.y, g, celda.size.y)
			Vector2i.LEFT: filo = Rect2(celda.position.x, celda.position.y, g, celda.size.y)
			Vector2i.UP: filo = Rect2(celda.position.x, celda.position.y, celda.size.x, g)
			_: filo = Rect2(celda.position.x, celda.end.y - g, celda.size.x, g)
		lienzo.draw_rect(filo, COLOR_TAPA_BORDE)
