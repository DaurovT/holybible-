#!/usr/bin/env python3
"""Нарезает иконки приложения из assets/icon/app_icon.png.

Запуск: python3 tool/make_icons.py

iOS и Android накладывают маску на иконку сами. Если у исходника свои
закруглённые углы или светлая кромка, после маски они остаются светлыми
уголками: маска iOS скрывает по диагонали около 6,5 % стороны, а у нынешнего
мастера светлое уходило на 7 %. Поэтому скрипт не доверяет исходнику: всё
светлое, что соединено с краем, он заливает продолжением соседнего фона.

Что получается:
- iOS — все размеры из Contents.json, без прозрачности (App Store отклоняет
  иконку с альфа-каналом);
- Android — legacy-иконка для Android 7 и адаптивная для 8+. Рисунок в
  адаптивной уменьшен до безопасной зоны: лаунчер показывает только середину
  слоя и режет её кругом или скруглённым квадратом, а края книги иначе
  срезались бы;
- docs/store/play-icon-512.png — иконка для карточки Google Play.

Нужен Pillow.
"""

import json
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'assets/icon/app_icon.png')
IOS_SET = os.path.join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')
ANDROID_RES = os.path.join(ROOT, 'android/app/src/main/res')
PLAY_ICON = os.path.join(ROOT, 'docs/store/play-icon-512.png')

# Рабочий размер: крупнее не нужно ни одной платформе, а заливка по пикселям на
# 2048 px заметно дольше.
WORK = 1024

# Legacy-иконка Android, 48 dp.
ANDROID_LEGACY = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# Слой адаптивной иконки, 108 dp.
ANDROID_ADAPTIVE = {folder: px * 108 // 48 for folder, px in ANDROID_LEGACY.items()}

# Какую долю слоя 108 dp занимает рисунок. Видна середина 72 dp, и маска-круг
# режет её по радиусу 36 dp; кончики книги лежат на 0,52 стороны рисунка от
# центра, так что 0,62 оставляет их внутри круга с запасом.
ADAPTIVE_ART = 0.62


def load_source():
    im = Image.open(SOURCE)
    if im.width != im.height:
        sys.exit(f'иконка должна быть квадратной, а не {im.width}x{im.height}')
    if im.width < 1024:
        sys.exit(f'исходник {im.width}px — для App Store нужен минимум 1024px')
    return im.convert('RGB').resize((WORK, WORK), Image.LANCZOS)


def _extend(im, keep):
    """Заливает пиксели вне [keep] продолжением ближайших сохранённых.

    Идём от границы внутрь заливки слоями: каждый пиксель берёт среднее уже
    известных соседей. Получается тот же фон, растянутый наружу, без резкой
    ступеньки на стыке.
    """
    w, h = im.size
    px = im.load()
    known = bytearray(keep)
    queue = deque()
    queued = bytearray(w * h)
    neighbours = ((1, 0), (-1, 0), (0, 1), (0, -1),
                  (1, 1), (-1, -1), (1, -1), (-1, 1))

    for y in range(h):
        row = y * w
        for x in range(w):
            if known[row + x]:
                continue
            for dx, dy in neighbours[:4]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and known[ny * w + nx]:
                    queue.append((x, y))
                    queued[row + x] = 1
                    break

    while queue:
        x, y = queue.popleft()
        r = g = b = n = 0
        for dx, dy in neighbours:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if known[i]:
                    pr, pg, pb = px[nx, ny]
                    r, g, b, n = r + pr, g + pg, b + pb, n + 1
                elif not queued[i]:
                    queued[i] = 1
                    queue.append((nx, ny))
        if n:
            px[x, y] = (r // n, g // n, b // n)
        known[y * w + x] = 1
    return im


def _soften(im, filled, radius):
    """Размывает только залитое, чтобы следы заливки не читались полосами."""
    mask = Image.frombytes('L', im.size, bytes(255 if f else 0 for f in filled))
    mask = mask.filter(ImageFilter.MaxFilter(3))
    return Image.composite(im.filter(ImageFilter.GaussianBlur(radius)), im, mask)


def clean(src):
    """Иконка «в край»: светлая кромка и углы исходника заменены фоном."""
    w, h = src.size
    px = src.load()

    # Светлое, соединённое с краем. Внутри рисунка светлые лучи и книга с краем
    # не соединены, их заливка не трогает.
    def light(x, y):
        return px[x, y][1] > 55

    edge = bytearray(w * h)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if light(x, y) and not edge[y * w + x]:
                edge[y * w + x] = 1
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if light(x, y) and not edge[y * w + x]:
                edge[y * w + x] = 1
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not edge[ny * w + nx] and light(nx, ny):
                edge[ny * w + nx] = 1
                queue.append((nx, ny))

    # Кромку сглаживания по краю светлого пятна тоже заменяем — иначе остаётся
    # светлая нитка.
    grown = Image.frombytes('L', src.size, bytes(255 if e else 0 for e in edge))
    grown = grown.filter(ImageFilter.MaxFilter(7))
    remove = grown.tobytes()
    keep = bytes(0 if r else 1 for r in remove)

    out = _extend(src.copy(), keep)
    return _soften(out, [not k for k in keep], 4)


def adaptive_background(icon):
    """Слой 108 dp: рисунок в безопасной зоне, фон продолжен до краёв."""
    art = round(WORK * ADAPTIVE_ART)
    canvas = Image.new('RGB', (WORK, WORK))
    offset = (WORK - art) // 2
    canvas.paste(icon.resize((art, art), Image.LANCZOS), (offset, offset))
    keep = bytearray(WORK * WORK)
    for y in range(offset, offset + art):
        keep[y * WORK + offset:y * WORK + offset + art] = b'\x01' * art
    out = _extend(canvas, keep)
    return _soften(out, [not k for k in keep], 24)


def write(im, path, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.resize((px, px), Image.LANCZOS).save(path, 'PNG', optimize=True)


def main():
    icon = clean(load_source())

    sizes = {}
    contents = json.load(open(os.path.join(IOS_SET, 'Contents.json')))
    for entry in contents['images']:
        side = float(entry['size'].split('x')[0])
        scale = int(entry['scale'][0])
        sizes[entry['filename']] = round(side * scale)
    for filename, px in sorted(sizes.items()):
        write(icon, os.path.join(IOS_SET, filename), px)
    print(f'iOS: {len(sizes)} файлов в AppIcon.appiconset')

    for folder, px in ANDROID_LEGACY.items():
        write(icon, os.path.join(ANDROID_RES, folder, 'ic_launcher.png'), px)

    background = adaptive_background(icon)
    for folder, px in ANDROID_ADAPTIVE.items():
        write(background,
              os.path.join(ANDROID_RES, folder, 'ic_launcher_background.png'), px)
    xml = os.path.join(ANDROID_RES, 'mipmap-anydpi-v26', 'ic_launcher.xml')
    os.makedirs(os.path.dirname(xml), exist_ok=True)
    with open(xml, 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<!-- Собирается tool/make_icons.py. Рисунок целиком в фоновом слое: отдельного
     переднего плана у мастера нет, а разрезать его на слои незачем. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@android:color/transparent" />
</adaptive-icon>
''')
    print(f'Android: {len(ANDROID_LEGACY)} плотностей, legacy и адаптивная')

    write(icon, PLAY_ICON, 512)
    print(f'Google Play: {os.path.relpath(PLAY_ICON, ROOT)}')


if __name__ == '__main__':
    main()
