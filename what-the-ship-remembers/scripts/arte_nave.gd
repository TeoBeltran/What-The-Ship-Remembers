class_name ArteNave
## Pisos, paredes y puertas del tileset (arte/tiles). Todo en la grilla de 48 px (Medidas.TILE).
##
## pisos.png (384x576): 16 materiales en 4 columnas x 4 grupos. Cada material ocupa 96x144:
##   arriba dos tiles sueltos de 48x48 y abajo una placa de 96x96.
##   Las salas usan la placa (por eso miden un número PAR de tiles: nunca queda una placa cortada).
##   Los pasillos usan el tile suelto de 48 (sirve para cualquier medida).
##   Número de material: columna + 4 * grupo (0 arriba a la izquierda ... 15 abajo a la derecha).
## paredes.png (768x288): 24 frentes de pared de 96x96 (2x2 tiles), 8 por fila.
##   Número: columna + 8 * fila (0 arriba a la izquierda ... 23 abajo a la derecha).
## puerta.png (48x384): 4 cuadros de 48x96 (cerrada → abierta). La hoja de la puerta mide 72 px;
##   los 24 px de arriba son transparentes y ahí se ve la pared que va debajo.

const RUTA_PISOS := "res://arte/tiles/pisos.png"
const RUTA_PAREDES := "res://arte/tiles/paredes.png"
const RUTA_PUERTA := "res://arte/tiles/puerta.png"

const T := Medidas.TILE
const BLOQUE := T * 2  # 96: placa de piso y frente de pared
const CANT_PISOS := 16
const CANT_PAREDES := 24
const CUADROS_PUERTA := 4

const COLOR_TAPA := Color(0.11, 0.12, 0.13)        # pared vista desde arriba (costados y abajo)
const COLOR_TAPA_BORDE := Color(0.3, 0.33, 0.35)   # filo de la tapa, del lado del piso
const COLOR_VANO := Color(0.03, 0.03, 0.04)        # lo que se ve por la puerta abierta

static var _cache := {}


static func _tex(ruta: String) -> Texture2D:
	if not _cache.has(ruta):
		_cache[ruta] = load(ruta)
	return _cache[ruta]


static func tex_pisos() -> Texture2D:
	return _tex(RUTA_PISOS)


static func tex_paredes() -> Texture2D:
	return _tex(RUTA_PAREDES)


static func tex_puerta() -> Texture2D:
	return _tex(RUTA_PUERTA)


## Parte (u, v) de la placa de 96x96 del material n (u, v = 0 o 1).
static func region_placa(n: int, u: int, v: int) -> Rect2:
	n = clampi(n, 0, CANT_PISOS - 1)
	return Rect2((n % 4) * BLOQUE + u * T, (n / 4) * (BLOQUE + T) + T + v * T, T, T)


## Tile suelto de 48x48 del material n.
static func region_tile(n: int) -> Rect2:
	n = clampi(n, 0, CANT_PISOS - 1)
	return Rect2((n % 4) * BLOQUE, (n / 4) * (BLOQUE + T), T, T)


## Bloque de pared n (96x96).
static func region_pared(n: int) -> Rect2:
	n = clampi(n, 0, CANT_PAREDES - 1)
	return Rect2((n % 8) * BLOQUE, (n / 8) * BLOQUE, BLOQUE, BLOQUE)


## Parte (u, v) del bloque de pared n.
static func region_frente(n: int, u: int, v: int) -> Rect2:
	var r := region_pared(n)
	return Rect2(r.position + Vector2(u, v) * T, Vector2(T, T))


## Cuadro k de la puerta (0 cerrada ... 3 abierta).
static func region_puerta(k: int) -> Rect2:
	return Rect2(0, clampi(k, 0, CUADROS_PUERTA - 1) * BLOQUE, T, BLOQUE)


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
