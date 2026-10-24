class_name Medidas
## Medidas del juego en un solo lugar (paso 5.5).
## Todo lo que se dibuja o choca en el mundo depende de TILE: si el arte cambiara de tamaño,
## se cambia TILE (y la resolución base en project.godot) y nada más.
## La planilla (objetos, muebles) y las salas (ancho, alto, pos_tiles) están en tiles, no en píxeles.
## Desde el arte de pisos y paredes, todo va en la grilla de tiles: ancho, alto y posición de las
## salas son del PISO (lo caminable); las paredes van alrededor (ver nave.gd).

## El arte (tilesets, sprites, personaje) está dibujado en una grilla de 48 px y se muestra al doble
## (pedido del usuario, 22/10/2026): cada píxel del arte ocupa 2x2 en pantalla, nítido.
## Para cambiar el tamaño del arte en pantalla alcanza con cambiar ARTE; los archivos no se tocan.
const ARTE := 2

## Tamaño de un tile del arte, en píxeles del archivo.
const TILE_ARTE := 48

## Tamaño de un tile en el mundo (en pantalla, con la cámara a x1).
const TILE := TILE_ARTE * ARTE

## Relación con el greybox original de 16 px. Sirve para escalar detalles chicos
## (grosores de línea, márgenes, velocidad) que se pensaron a 16 px.
const ESCALA := TILE / 16.0

## Grosor de las paredes de los costados y de abajo (1 tile).
const PARED := TILE

## Alto del frente de la pared de arriba, en tiles (se ve de frente, como en un RPG visto desde arriba).
const FRENTE := 2

## Ancho de una puerta, en tiles: 3 (arte/tiles/nave_puertas.png, cuadros de 144x96 del archivo:
## marco a los costados y la hoja que se abre en el tile del medio, el único por donde se pasa).
const PUERTA_TILES := 3
const ANCHO_PUERTA := TILE * PUERTA_TILES

## Celda de la grilla de caminos del click derecho (medio tile).
const CELDA := TILE / 2

## Resolución en la que está pensada la interfaz (se escala sola a la resolución real).
const UI_BASE := Vector2(960, 540)


## Convierte una posición/tamaño en tiles a píxeles.
static func px(tiles: Vector2) -> Vector2:
	return tiles * TILE
