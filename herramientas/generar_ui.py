"""Genera las piezas de interfaz en pixel art (arte/ui/*.png).
Inspiradas en el pack "Futuristic infographic element collection" (Freepik): marco con esquinas,
marco de esquinas redondeadas, barra a rayas y batería. Se dibujan a mano por código para que
queden simétricas y en la grilla de píxeles. Blancas: el color se pone en Godot (modulate).
Uso: python herramientas/generar_ui.py
"""
from pathlib import Path
from PIL import Image

SALIDA = Path(__file__).resolve().parent.parent / "what-the-ship-remembers" / "arte" / "ui"
B = (255, 255, 255, 255)
FONDO = (13, 17, 26, 236)


def nuevo(w, h, fondo=None):
    return Image.new("RGBA", (w, h), fondo or (0, 0, 0, 0))


def rect(im, x0, y0, x1, y1, c=B):
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            im.putpixel((x, y), c)


def marco_dialogo():
    """24x24, márgenes 9-slice de 8. Borde de 2 px + esquinas en L por dentro."""
    s = 24
    im = nuevo(s, s)
    rect(im, 2, 2, s - 3, s - 3, FONDO)
    rect(im, 0, 0, s - 1, 1); rect(im, 0, s - 2, s - 1, s - 1)
    rect(im, 0, 0, 1, s - 1); rect(im, s - 2, 0, s - 1, s - 1)
    i, L = 4, 4  # esquinas interiores
    for (x, y, dx, dy) in [(i, i, 1, 1), (s - 1 - i, i, -1, 1), (i, s - 1 - i, 1, -1), (s - 1 - i, s - 1 - i, -1, -1)]:
        for k in range(L):
            im.putpixel((x + dx * k, y), B); im.putpixel((x, y + dy * k), B)
    return im


def marco_nora():
    """24x24, márgenes 8. Solo esquinas redondeadas (sin lados), como el marco de corchetes del pack."""
    s = 24
    im = nuevo(s, s)
    rect(im, 2, 2, s - 3, s - 3, FONDO)
    esquina = [  # 8x8, arriba a la izquierda (2 px de grosor, curva)
        "....####",
        "..######",
        ".###....",
        ".##.....",
        "##......",
        "##......",
        "##......",
        "##......",
    ]
    for y, fila in enumerate(esquina):
        for x, ch in enumerate(fila):
            if ch == "#":
                for (px, py) in [(x, y), (s - 1 - x, y), (x, s - 1 - y), (s - 1 - x, s - 1 - y)]:
                    im.putpixel((px, py), B)
    return im


def segmento():
    """Segmento inclinado de la barra de energía (5x7), como la barra a rayas del pack."""
    im = nuevo(5, 7)
    for y in range(7):
        x0 = 2 - (y * 2) // 6  # se corre hacia la izquierda al bajar
        rect(im, x0, y, x0 + 2, y)
    return im


def bateria():
    """Ícono de batería 12x8 (borne a la izquierda, como en el pack) con una flecha."""
    im = nuevo(12, 8)
    rect(im, 2, 0, 11, 0); rect(im, 2, 7, 11, 7); rect(im, 2, 0, 2, 7); rect(im, 11, 0, 11, 7)
    rect(im, 0, 2, 1, 5)
    for y, w in [(2, 1), (3, 2), (4, 2), (5, 1)]:
        rect(im, 5, y, 4 + w, y)
    return im


def bombilla():
    """Ícono de luz 8x8."""
    im = nuevo(8, 8)
    for y, fila in enumerate(["..####..", ".#....#.", "#......#", "#......#", ".#....#.", "..#..#..", "..####..", "...##..."]):
        for x, ch in enumerate(fila):
            if ch == "#":
                im.putpixel((x, y), B)
    return im


if __name__ == "__main__":
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre, f in [("marco_dialogo", marco_dialogo), ("marco_nora", marco_nora), ("segmento_energia", segmento),
                      ("icono_bateria", bateria), ("icono_luz", bombilla)]:
        f().save(SALIDA / f"{nombre}.png")
        print("ok", nombre)
