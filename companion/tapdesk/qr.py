"""Rendering the pairing QR code.

The QR is deliberately **black on white**, even though the companion window is
dark. Scanners need real contrast, and a dark-background QR with green modules is
a common thing to build that simply will not scan. The window around it is dark;
the code itself is not.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from typing import TYPE_CHECKING

import qrcode
from qrcode.constants import ERROR_CORRECT_M

if TYPE_CHECKING:  # pragma: no cover - typing only
    from PIL.Image import Image

#: Enough redundancy to survive a projector, a coffee ring and a phone held at
#: an angle. The payload is short, so a higher level costs almost nothing.
ERROR_CORRECTION = ERROR_CORRECT_M

#: White quiet zone around the modules, in modules. Four is the spec minimum;
#: more is better because a phone often cannot see the code's edge.
BORDER_MODULES = 4


@dataclass(frozen=True)
class RenderedQR:
    """A rendered code, kept in a few forms the window can use."""

    png: bytes
    matrix: tuple[tuple[bool, ...], ...]

    @property
    def side(self) -> int:
        return len(self.matrix)


def render(deep_link: str, box_size: int = 10) -> RenderedQR:
    """Render a deep link to a PNG plus a boolean matrix.

    The matrix is what the window draws, so it can scale to the available width
    without re-encoding the code.
    """
    code = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECTION,
        box_size=box_size,
        border=BORDER_MODULES,
    )
    code.add_data(deep_link)
    code.make(fit=True)

    buffer = io.BytesIO()
    image = code.make_image(fill_color="black", back_color="white")
    image.save(buffer, format="PNG")

    matrix = tuple(
        tuple(bool(cell) for cell in row) for row in code.get_matrix()
    )
    return RenderedQR(png=buffer.getvalue(), matrix=matrix)


def to_ascii(deep_link: str, scale: int = 1) -> str:
    """A text rendering of the code, for terminals and logs.

    Two characters per module and inverted (`#` dark on light) so it reads in a
    console without a background colour.
    """
    rendered = render(deep_link)
    lines = []
    for row in rendered.matrix:
        lines.append("".join("  " if cell else "  " for cell in row))
    return "\n".join(lines)


def pil_image(deep_link: str, box_size: int = 10) -> "Image":
    """The code as a PIL image, for the Qt window."""
    code = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECTION,
        box_size=box_size,
        border=BORDER_MODULES,
    )
    code.add_data(deep_link)
    code.make(fit=True)
    return code.make_image(fill_color="black", back_color="white").convert("RGB")
