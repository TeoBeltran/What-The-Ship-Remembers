class_name Medidas
## Medidas del juego en un solo lugar (paso 5.5).
## Todo lo que se dibuja o choca en el mundo depende de TILE: si el arte cambiara de tamaño,
## se cambia TILE (y la resolución base en project.godot) y nada más.
## La planilla (objetos, muebles) y las salas (ancho, alto, pos_tiles) están en tiles, no en píxeles.
## Desde el arte de pisos y paredes, todo va en la grilla de tiles: ancho, alto y posición de las
## salas son del PISO (lo caminable); las paredes van alrededor (ver nave.gd).

## Tamaño de un tile en píxeles. El tileset del juego es de 48x48.
const TILE := 48

## Relación con el greybox original de 16 px. Sirve para escalar detalles chicos
## (grosores de línea, márgenes, velocidad) que se pensaron a 16 px.
const ESCALA := TILE / 16.0

## Grosor de las paredes de los costados y de abajo (1 tile).
const PARED := TILE

## Alto del frente de la pared de arriba, en tiles (se ve de frente, como en un RPG visto desde arriba).
const FRENTE := 2

## Ancho de una puerta: puerta doble, 2 tiles (dos sprites de 48x96, el de la derecha espejado).
const ANCHO_PUERTA := TILE * 2

## Celda de la grilla de caminos del click derecho (medio tile).
const CELDA := TILE / 2

## Resolución en la que está pensada la interfaz (se escala sola a la resolución real).
const UI_BASE := Vector2(960, 540)


## Convierte una posición/tamaño en tiles a píxeles.
static func px(tiles: Vector2) -> Vector2:
	return tiles * TILE
