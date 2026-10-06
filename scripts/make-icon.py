#!/usr/bin/env python3
"""生成 VoiceInput 的 App 图标（可复现，不依赖设计工具）。

用法（需要 numpy + Pillow；DSH 捆绑的 python 已自带）：
    ~/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3 \
        scripts/make-icon.py

产物：
    VoiceInputMacApp/Resources/AppIcon.icns    ← build.sh 会打包进 .app
    build/icon/icon_master.png                 ← 1024×1024 预览
    build/icon/preview_sizes.png               ← 各尺寸对照，检查小图标可读性

设计：macOS 原生风格圆角方块（squircle）+ 蓝→紫三色对角渐变 + 居中白色声波。
波形取 5 根圆角竖条、中间最高，整体约占方块一半，保证缩到 16px 仍认得出。
"""

import os
import shutil
import subprocess
import sys

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit(
        "需要 Pillow 与 numpy。DSH 捆绑的 python 已自带：\n"
        "  ~/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3 "
        "scripts/make-icon.py"
    )

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES_DIR = os.path.join(PROJECT_DIR, "VoiceInputMacApp", "Resources")
BUILD_DIR = os.path.join(PROJECT_DIR, "build", "icon")

CANVAS = 1024
# macOS 图标规范：图形约占画布 80%，四周留白给投影
MARGIN = 100
SIZE = CANVAS - 2 * MARGIN          # 824
# Big Sur 以后的圆角比例约 22.37%
RADIUS = int(SIZE * 0.2237)

# 对角渐变，三色过渡
GRADIENT_STOPS = [
    (0.00, (86, 132, 255)),         # 亮蓝
    (0.55, (122, 104, 246)),        # 靛紫
    (1.00, (163, 84, 232)),         # 紫
]

# 波形：5 根竖条，高度按方块边长比例。整体压在 50% 以内，留出呼吸感。
BAR_COUNT = 5
BAR_HEIGHTS = [0.18, 0.36, 0.50, 0.36, 0.18]
BAR_WIDTH = SIZE * 0.062
BAR_GAP = SIZE * 0.050


def diagonal_gradient(size: int) -> Image.Image:
    """沿对角线做多段线性渐变。"""
    y, x = np.mgrid[0:size, 0:size]
    t = (x + y) / (2.0 * (size - 1))

    rgb = np.zeros((size, size, 3), dtype=float)
    for i in range(len(GRADIENT_STOPS) - 1):
        t0, c0 = GRADIENT_STOPS[i]
        t1, c1 = GRADIENT_STOPS[i + 1]
        seg = (t >= t0) & (t <= t1)
        span = (t1 - t0) or 1.0
        local = np.zeros_like(t)
        local[seg] = (t[seg] - t0) / span
        for ch in range(3):
            blended = c0[ch] * (1 - local) + c1[ch] * local
            rgb[..., ch] = np.where(seg, blended, rgb[..., ch])

    # 浮点边界兜底：超过最后一段的用末色
    last = GRADIENT_STOPS[-1][1]
    for ch in range(3):
        rgb[..., ch] = np.where(t > GRADIENT_STOPS[-1][0], last[ch], rgb[..., ch])
    return Image.fromarray(rgb.astype("uint8"), "RGB")


def squircle_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    return mask


def draw_waveform(size: int) -> Image.Image:
    """白色声波，单独一层。"""
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)

    total_w = BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP
    x = (size - total_w) / 2.0
    cy = size / 2.0

    for ratio in BAR_HEIGHTS:
        h = size * ratio
        y0 = cy - h / 2.0
        draw.rounded_rectangle(
            [x, y0, x + BAR_WIDTH, y0 + h],
            radius=BAR_WIDTH / 2.0,
            fill=255,
        )
        x += BAR_WIDTH + BAR_GAP

    return layer


def build_canvas() -> Image.Image:
    mask = squircle_mask(SIZE, RADIUS)

    # 1) 渐变底
    art = diagonal_gradient(SIZE)
    art = Image.composite(art, Image.new("RGB", (SIZE, SIZE), (0, 0, 0)), mask)

    # 2) 顶部玻璃高光
    gloss = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(gloss).ellipse(
        [-SIZE * 0.35, -SIZE * 0.78, SIZE * 1.35, SIZE * 0.40], fill=70
    )
    gloss = gloss.filter(ImageFilter.GaussianBlur(SIZE * 0.07))
    gloss = Image.composite(gloss, Image.new("L", (SIZE, SIZE), 0), mask)
    art = Image.composite(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), art, gloss)

    # 3) 底部暗角
    vignette = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(vignette).ellipse(
        [-SIZE * 0.2, SIZE * 0.60, SIZE * 1.2, SIZE * 1.9], fill=48
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(SIZE * 0.10))
    vignette = Image.composite(vignette, Image.new("L", (SIZE, SIZE), 0), mask)
    art = Image.composite(Image.new("RGB", (SIZE, SIZE), (26, 22, 78)), art, vignette)

    # 4) 波形 + 柔和内阴影
    wave = draw_waveform(SIZE)
    wave_shadow = wave.filter(ImageFilter.GaussianBlur(SIZE * 0.010))
    shadow_layer = Image.new("L", (SIZE, SIZE), 0)
    shadow_layer.paste(wave_shadow, (0, int(SIZE * 0.010)))
    shadow_layer = Image.composite(shadow_layer, Image.new("L", (SIZE, SIZE), 0), mask)
    art = Image.composite(
        Image.new("RGB", (SIZE, SIZE), (34, 40, 96)),
        art,
        shadow_layer.point(lambda v: int(v * 0.18)),
    )
    art = Image.composite(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), art, wave)

    # 5) 玻璃描边（顶端更亮的细白边）
    edge = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(edge).rounded_rectangle(
        [3, 3, SIZE - 4, SIZE - 4], radius=RADIUS - 3, outline=255, width=3
    )
    vert = np.linspace(1.0, 0.35, SIZE).reshape(-1, 1)
    edge = Image.fromarray((np.asarray(edge, dtype=float) * vert).astype("uint8"), "L")
    art = Image.composite(
        Image.new("RGB", (SIZE, SIZE), (255, 255, 255)),
        art,
        edge.point(lambda v: int(v * 0.30)),
    )

    # 6) 放到画布中央 + 投影
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_mask.paste(mask, (MARGIN, MARGIN + int(CANVAS * 0.012)))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(CANVAS * 0.022))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(shadow_mask.point(lambda v: int(v * 0.28)))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(art.convert("RGBA"), (MARGIN, MARGIN), mask)
    return canvas


def main() -> None:
    os.makedirs(BUILD_DIR, exist_ok=True)
    os.makedirs(RESOURCES_DIR, exist_ok=True)

    canvas = build_canvas()
    master = os.path.join(BUILD_DIR, "icon_master.png")
    canvas.save(master)
    print(f"✅ 主图：{master}")

    iconset = os.path.join(BUILD_DIR, "AppIcon.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            canvas.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))

    icns = os.path.join(RESOURCES_DIR, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    print(f"✅ 图标：{icns} ({os.path.getsize(icns) // 1024} KB)")

    sizes = [16, 32, 48, 64, 128, 256]
    pad = 16
    sheet = Image.new(
        "RGBA",
        (sum(sizes) + pad * (len(sizes) + 1), max(sizes) + pad * 2),
        (245, 245, 247, 255),
    )
    x = pad
    for s in sizes:
        thumb = canvas.resize((s, s), Image.LANCZOS)
        sheet.paste(thumb, (x, (sheet.height - s) // 2), thumb)
        x += s + pad
    preview = os.path.join(BUILD_DIR, "preview_sizes.png")
    sheet.save(preview)
    print(f"✅ 尺寸对照：{preview}")


if __name__ == "__main__":
    main()
