#!/usr/bin/env python3
"""Disegna l'icona dell'app (radio d'epoca su fondo arrotondato) e scrive resources/RadioTray.icns.

Uso: python3 -I tools/make_icon.py [percorso.icns]   (richiede Pillow)
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def draw_icon():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # fondo: quadrato arrotondato con sfumatura verticale
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    top, bottom = (255, 138, 76, 255), (214, 52, 70, 255)
    for y in range(S):
        gd.line([(0, y), (S, y)], fill=lerp(top, bottom, y / (S - 1)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([72, 72, S - 72, S - 72], radius=190, fill=255)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([72, 92, S - 72, S - 52], radius=190, fill=(0, 0, 0, 90))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    cream = (255, 247, 236, 255)
    dark = (120, 34, 48, 255)

    # antenna
    d.line([(330, 420), (700, 210)], fill=cream, width=34)
    d.ellipse([680, 190, 730, 240], fill=cream)

    # corpo della radio
    d.rounded_rectangle([190, 400, 834, 820], radius=70, fill=cream)

    # altoparlante con griglia
    cx, cy, r = 380, 610, 140
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=dark)
    for k in range(-3, 4):
        x = cx + k * 34
        h = int((r * r - (k * 34) ** 2) ** 0.5) - 14
        if h > 0:
            d.line([(x, cy - h), (x, cy + h)], fill=cream, width=10)

    # quadrante e manopole
    d.rounded_rectangle([580, 480, 770, 560], radius=18, fill=dark)
    d.line([(650, 490), (650, 550)], fill=(255, 138, 76, 255), width=10)
    for x in (620, 730):
        d.ellipse([x - 42, 640, x + 42, 724], fill=dark)
        d.ellipse([x - 12, 652, x + 12, 676], fill=cream)
    return img


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "resources" / "RadioTray.icns")
    icon = draw_icon()
    icon.save(out, format="ICNS", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    icon.resize((256, 256), Image.LANCZOS).save(out.parent.parent / "docs" / "icona.png")
    print(f"scritto {out}")


if __name__ == "__main__":
    main()
