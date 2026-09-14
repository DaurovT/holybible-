"""Убирает альфа-канал у скриншотов App Store.

Кадры с симулятора приходят в RGBA, а App Store Connect отклоняет скриншоты с
прозрачностью. Фон подкладывается белый: прозрачных пикселей в кадрах нет, так
что картинка не меняется, меняется только формат.

    python3 tool/flatten_screenshots.py

Нужен Pillow.
"""

from pathlib import Path

from PIL import Image

for path in sorted(Path('docs/screenshots').glob('*.png')):
    image = Image.open(path)
    if image.mode == 'RGB':
        continue
    flat = Image.new('RGB', image.size, (255, 255, 255))
    flat.paste(image, mask=image.getchannel('A') if 'A' in image.getbands() else None)
    flat.save(path, optimize=True)
    print(f'{path.name}: {image.mode} → RGB, {image.size[0]}×{image.size[1]}')
