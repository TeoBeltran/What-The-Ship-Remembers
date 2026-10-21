class_name TemaUI
## Estilo de la interfaz (prueba de arte de UI): fuente pixel y marcos en pixel art.
## La fuente BoldsPixels está dibujada en una grilla de 16: se ve nítida SOLO en tamaño 16 (o 32, 48…).
## La interfaz se arma a 960x540 y se escala x2, así que cada pixel de la letra son 2 píxeles de pantalla.
## Fuente: "BoldsPixels" de YukiPixels, licencia CC BY-SA 4.0 (hay que nombrarla en los créditos).
## Marcos: arte/ui/*.png (los genera herramientas/generar_ui.py). Son blancos: el color se pone acá.

const TAM := 16                     # único tamaño de texto (múltiplo de 16)
const TAM_GRANDE := 32

const C_BORDE := Color(0.45, 0.85, 0.95)          # cian principal de la interfaz
const C_BORDE_SUAVE := Color(0.35, 0.55, 0.62)
const C_BOTON := Color(0.07, 0.09, 0.13, 0.95)
const C_BOTON_HOVER := Color(0.12, 0.2, 0.26, 0.95)

static var fuente: FontFile
static var tema: Theme


## Se llama una vez al crear la interfaz.
static func preparar() -> void:
	if tema != null:
		return
	fuente = load("res://arte/fuentes/BoldsPixels.ttf")
	fuente.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	fuente.hinting = TextServer.HINTING_NONE
	fuente.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	fuente.generate_mipmaps = false
	# Todo lo que no tenga tema propio (labels sueltos, draw_string del mapa) usa esta fuente.
	ThemeDB.fallback_font = fuente
	ThemeDB.fallback_font_size = TAM
	tema = Theme.new()
	tema.default_font = fuente
	tema.default_font_size = TAM
	tema.set_stylebox("normal", "Button", _caja_boton(C_BOTON, C_BORDE_SUAVE))
	tema.set_stylebox("hover", "Button", _caja_boton(C_BOTON_HOVER, C_BORDE))
	tema.set_stylebox("pressed", "Button", _caja_boton(C_BOTON_HOVER, Color.WHITE))
	tema.set_stylebox("hover_pressed", "Button", _caja_boton(C_BOTON_HOVER, Color.WHITE))
	tema.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	tema.set_stylebox("disabled", "Button", _caja_boton(C_BOTON, Color(0.25, 0.25, 0.28)))
	for estado in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		tema.set_color(estado, "Button", Color(0.9, 0.95, 1.0))


static func _caja_boton(fondo: Color, borde: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(1)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	return s


## Marco en pixel art que se estira sin deformarse (9 partes). nombre: "marco_dialogo" o "marco_nora".
static func marco(nombre: String, color := C_BORDE, margen := 14) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load("res://arte/ui/%s.png" % nombre)
	s.set_texture_margin_all(8)
	s.set_content_margin_all(margen)
	s.modulate_color = color
	return s


## Botón sin caja (para las opciones del menú de NORA): solo cambia el color del texto.
static func boton_plano(b: Button) -> void:
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
