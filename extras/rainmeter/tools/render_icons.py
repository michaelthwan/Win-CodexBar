"""Render the provider SVG logos to tinted PNGs for the Rainmeter skin.

Rainmeter cannot draw SVG, so this rasterises the upstream dashboard icons with
headless Edge and tints the white glyphs with each provider's chart colour
(apps/desktop-tauri/src/styles.css). Re-run after upstream changes a logo:

    python extras/rainmeter/tools/render_icons.py
"""

import pathlib
import subprocess
import tempfile
import time

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "rust/src/cli/serve/dashboard/icons"
OUT = ROOT / "extras/rainmeter/CodexBarUsage/@Resources/icons"
EDGE = pathlib.Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
SIZE = 64

# Grok's chart colour is black, which vanishes on the dark panel; keep it white.
COLORS = {
    "claude": (204, 124, 94),
    "codex": (73, 163, 176),
    "grok": (235, 235, 235),
}


def render(provider: str, color: tuple[int, int, int], tmp: pathlib.Path) -> None:
    svg = (SRC / f"ProviderIcon-{provider}.svg").read_text(encoding="utf-8")
    page = tmp / f"{provider}.html"
    page.write_text(
        "<html><body style='margin:0;background:transparent'>"
        f"<div style='width:{SIZE}px;height:{SIZE}px'>"
        + svg.replace("<svg ", f"<svg style='width:{SIZE}px;height:{SIZE}px' ", 1)
        + "</div></body></html>",
        encoding="utf-8",
    )
    shot = tmp / f"{provider}.png"
    subprocess.run(
        [
            str(EDGE), "--headless=new", "--disable-gpu", "--hide-scrollbars",
            f"--user-data-dir={tmp / 'edge-profile'}", "--no-first-run",
            "--default-background-color=00000000", f"--window-size={SIZE},{SIZE}",
            f"--screenshot={shot}", page.as_uri(),
        ],
        check=True, capture_output=True, timeout=60,
    )
    # msedge.exe hands off to a child process and returns before the file exists.
    deadline = time.monotonic() + 30
    while not shot.exists() or shot.stat().st_size == 0:
        if time.monotonic() > deadline:
            raise RuntimeError(f"Edge did not write {shot}")
        time.sleep(0.2)
    time.sleep(0.3)
    img = Image.open(shot).convert("RGBA").crop((0, 0, SIZE, SIZE))
    # Glyphs are white on transparent: use luminance*alpha as the new alpha.
    tinted = Image.new("RGBA", img.size, color + (0,))
    px, out = img.load(), tinted.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = px[x, y]
            out[x, y] = color + (round(a * (r + g + b) / 765),)
    tinted.save(OUT / f"{provider}.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for provider, color in COLORS.items():
            render(provider, color, pathlib.Path(tmp))
            print(f"wrote {OUT / (provider + '.png')}")


if __name__ == "__main__":
    main()
