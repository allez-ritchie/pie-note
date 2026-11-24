#!/usr/bin/env python3
"""从 `assets/branding/app_icon.svg` 生成各平台的应用图标。

设计约定（改图标时只需要替换 SVG，然后重跑本脚本）：

- 底板：暖白纸色 `#FBF8F1`，桌面端为圆角方块（圆角 22.5%），Android 传统图标满幅；
- 图案：SVG 内容按 66% 的宽度居中（Android 自适应图标前景按 108dp 画布的 61%，
  保证落在系统 66dp 安全区内，不被圆形/方形遮罩切到）；
- Android：mipmap 各密度传统图标 + adaptive icon（背景色 + 前景 + 单色）。

依赖：Python 3 + Pillow + 本机 Chrome/Chromium（用于把 SVG 光栅化）。
用法：`python3 scripts/generate_app_icons.py`
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "assets" / "branding" / "app_icon.svg"
BG_COLOR = (251, 248, 241, 255)
PLATE_RADIUS = 0.225
LAST_ICON_SIZE = 512

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
ANDROID_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
ADAPTIVE_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
WINDOWS_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
LINUX_ICON = ROOT / "assets" / "branding" / "app_icon.png"


def _find_chrome() -> str:
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
        path = shutil.which(name)
        if path:
            return path
    raise SystemExit("未找到 Chrome/Chromium，无法把 SVG 光栅化。")


def _render_svg(svg_text: str, out_png: Path, size: int = 256) -> Image.Image:
    """用无头 Chrome 以 4 倍分辨率渲染 SVG，返回 RGBA 图。"""
    chrome = _find_chrome()
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.html"
        page.write_text(
            "<!doctype html><html><body style='margin:0;background:transparent;overflow:hidden'>"
            f"<div style='width:{size}px;height:{size}px'>{svg_text}</div>"
            "</body></html>",
            encoding="utf-8",
        )
        subprocess.run(
            [
                chrome,
                "--headless",
                "--disable-gpu",
                "--no-sandbox",
                "--hide-scrollbars",
                "--default-background-color=00000000",
                "--force-device-scale-factor=4",
                f"--window-size={size},{size}",
                f"--screenshot={out_png}",
                f"file://{page}",
            ],
            check=True,
            capture_output=True,
        )
    return Image.open(out_png).convert("RGBA")


def _artwork(monochrome: bool = False) -> Image.Image:
    """渲染图案并裁到内容边界（正方形）。"""
    svg_text = SVG.read_text(encoding="utf-8")
    if monochrome:
        svg_text = svg_text.replace('fill="#2E6B4F"', 'fill="#FFFFFF"')
        svg_text = svg_text.replace('fill="#0E7268"', 'fill="#FFFFFF"')
        svg_text = svg_text.replace('fill="#A97B12"', 'fill="#FFFFFF"')
    with tempfile.TemporaryDirectory() as tmp:
        raw = _render_svg(svg_text, Path(tmp) / "raw.png")
    box = raw.getbbox()
    if box is None:
        raise SystemExit("SVG 渲染结果为空，检查 assets/branding/app_icon.svg。")
    art = raw.crop(box)
    side = max(art.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(art, ((side - art.width) // 2, (side - art.height) // 2))
    return square


def _plate(size: int, radius_ratio: float = PLATE_RADIUS) -> Image.Image:
    plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(plate)
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=int(size * radius_ratio),
        fill=BG_COLOR,
    )
    return plate


def _compose(
    size: int,
    art: Image.Image,
    art_ratio: float,
    *,
    rounded: bool,
    background: tuple[int, int, int, int] | None = BG_COLOR,
) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if rounded:
        canvas = _plate(size)
    elif background is not None:
        canvas = Image.new("RGBA", (size, size), background)
    art_size = max(1, round(size * art_ratio))
    scaled = art.resize((art_size, art_size), Image.LANCZOS)
    canvas.alpha_composite(scaled, ((size - art_size) // 2, (size - art_size) // 2))
    return canvas


def _write_android(logo: Image.Image, mono: Image.Image) -> None:
    for density, size in ANDROID_DENSITIES.items():
        out_dir = ANDROID_RES / f"mipmap-{density}"
        out_dir.mkdir(parents=True, exist_ok=True)
        # 传统图标：满幅底板（启动器会自己套遮罩），图案留安全边。
        _compose(size, logo, 0.66, rounded=False).save(out_dir / "ic_launcher.png")
        # 自适应图标前景：透明画布，图案落在 66/108 安全区内。
        foreground = _compose(size, logo, 0.61, rounded=False, background=None)
        foreground.save(out_dir / "ic_launcher_foreground.png")
        monochrome = _compose(size, mono, 0.61, rounded=False, background=None)
        monochrome.save(out_dir / "ic_launcher_monochrome.png")

    adaptive_dir = ANDROID_RES / "mipmap-anydpi-v26"
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    (adaptive_dir / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
""",
        encoding="utf-8",
    )
    values_dir = ANDROID_RES / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    (values_dir / "ic_launcher_background.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- 与 assets/branding/app_icon.svg 的暖白底板保持一致 -->
    <color name="ic_launcher_background">#FBF8F1</color>
</resources>
""",
        encoding="utf-8",
    )


def _write_windows(logo: Image.Image) -> None:
    WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    # ICO 从 256 的母图逐级缩小，比从 16 放大清晰得多。
    base = _compose(256, logo, 0.66, rounded=True)
    base.save(
        WINDOWS_ICO,
        format="ICO",
        sizes=[(size, size) for size in sizes],
    )


def main() -> None:
    logo = _artwork()
    mono = _artwork(monochrome=True)

    _write_android(logo, mono)
    _write_windows(logo)

    LINUX_ICON.parent.mkdir(parents=True, exist_ok=True)
    _compose(LAST_ICON_SIZE, logo, 0.66, rounded=True).save(LINUX_ICON)
    print("图标已生成：Android mipmap / Windows app_icon.ico / assets/branding/app_icon.png")


if __name__ == "__main__":
    main()
