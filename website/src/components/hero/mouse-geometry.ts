/**
 * Geometry for the TapDesk mouse artwork.
 *
 * The same path data drives two renderers:
 *  - an inline SVG (no-JS / reduced-motion fallback)
 *  - a 2D canvas used by the pixel-explosion hero, which rasterises the mouse
 *    into an offscreen buffer and samples it on a pixel grid.
 */

export const MOUSE_W = 260;
export const MOUSE_H = 340;

/** Outer silhouette of a top-down mouse, in viewBox coordinates. */
export const MOUSE_OUTLINE =
  "M130 18 C166 18 190 46 197 96 C206 158 208 220 196 268 " +
  "C184 316 160 332 130 332 C100 332 76 316 64 268 " +
  "C52 220 54 158 63 96 C70 46 94 18 130 18 Z";

/** Seam separating the left and right buttons. */
export const MOUSE_SEAM = "M130 20 L130 196";

/** Arc separating the button panels from the body of the mouse. */
export const MOUSE_SPLIT =
  "M63 150 C88 176 108 186 130 186 C152 186 172 176 197 150";

/** Scroll wheel. */
export const MOUSE_WHEEL =
  "M130 46 m-12 0 a12 12 0 0 1 24 0 l0 40 a12 12 0 0 1 -24 0 Z";

/** Where the buttons sit, in viewBox coordinates. */
export const LEFT_BUTTON_CENTRE = { x: 92, y: 116 };
export const RIGHT_BUTTON_CENTRE = { x: 168, y: 116 };

/** Top-left offset that draws the mouse centred on (cx, cy) at a uniform scale. */
export function mouseOrigin(cx: number, cy: number, scale: number) {
  return {
    ox: cx - (MOUSE_W * scale) / 2,
    oy: cy - (MOUSE_H * scale) / 2,
    scale,
  };
}

/**
 * Paints the mouse into a 2D context that has already been scaled so that
 * viewBox coordinates map 1:1 to the context. Shared by the canvas renderer.
 */
export function paintMouse(ctx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D) {
const grad = ctx.createLinearGradient(48, 0, 212, 340);
grad.addColorStop(0, "#ECFDF5");
grad.addColorStop(0.26, "#BBF7D0");
grad.addColorStop(0.55, "#4ADE80");
grad.addColorStop(0.82, "#16A34A");
grad.addColorStop(1, "#15803D");

  ctx.fillStyle = grad;
  ctx.fill(new Path2D(MOUSE_OUTLINE));

  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  ctx.strokeStyle = "rgba(10,10,10,0.16)";
  ctx.lineWidth = 6;
  ctx.stroke(new Path2D(MOUSE_SPLIT));

  ctx.strokeStyle = "rgba(10,10,10,0.34)";
  ctx.lineWidth = 7;
  ctx.stroke(new Path2D(MOUSE_SEAM));

  ctx.fillStyle = "#0A0A0A";
  ctx.fill(new Path2D(MOUSE_WHEEL));

  ctx.strokeStyle = "rgba(134,239,172,0.5)";
  ctx.lineWidth = 2.5;
  ctx.stroke(new Path2D(MOUSE_WHEEL));

  ctx.beginPath();
  ctx.arc(MOUSE_W / 2, 206, 7, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(10,10,10,0.8)";
  ctx.fill();

  ctx.strokeStyle = "rgba(10,10,10,0.16)";
  ctx.lineWidth = 3;
  ctx.stroke(new Path2D(MOUSE_OUTLINE));
}