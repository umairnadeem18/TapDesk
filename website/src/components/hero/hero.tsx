"use client";

import { useCallback, useEffect, useRef } from "react";
import Link from "next/link";
import { ArrowDown, Monitor, Smartphone } from "lucide-react";
import { usePrefersReducedMotion } from "@/components/reveal";
import { MouseSvg } from "./mouse-svg";
import {
  MOUSE_H,
  MOUSE_W,
  RIGHT_BUTTON_CENTRE,
  mouseOrigin,
  paintMouse,
} from "./mouse-geometry";

/* ------------------------------------------------------------------ */
/*  Scroll choreography                                                */
/* ------------------------------------------------------------------ */

const TRAVEL_END = 0.42;
const EXPLODE_START = 0.46;
const EXPLODE_END = 0.88;
const CTA_START = 0.8;

const GRID_W = 40;
const GRID_H = 52;
const SS = 5;

type Cell = {
  nx: number;
  ny: number;
  r: number;
  g: number;
  b: number;
  delay: number;
  angle: number;
  rot: number;
  size: number;
  hot: boolean;
  right: boolean;
};

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smoothstep = (a: number, b: number, v: number) => {
  const t = clamp01((v - a) / (b - a || 1));
  return t * t * (3 - 2 * t);
};
const easeInOutCubic = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3);

/* ------------------------------------------------------------------ */
/*  Rasterise the mouse once, then sample it on a pixel grid            */
/* ------------------------------------------------------------------ */

function buildCells(): Cell[] {
  const w = GRID_W * SS;
  const h = GRID_H * SS;
  const off = document.createElement("canvas");
  off.width = w;
  off.height = h;
  const ctx = off.getContext("2d", { willReadFrequently: true });
  if (!ctx) return [];

  const scale = Math.min(w / MOUSE_W, h / MOUSE_H);
  const ox = (w - MOUSE_W * scale) / 2;
  const oy = (h - MOUSE_H * scale) / 2;

  ctx.save();
  ctx.translate(ox, oy);
  ctx.scale(scale, scale);
  paintMouse(ctx);
  ctx.restore();

  const data = ctx.getImageData(0, 0, w, h).data;
  const cells: Cell[] = [];
  const area = SS * SS;

  for (let cy = 0; cy < GRID_H; cy++) {
    for (let cx = 0; cx < GRID_W; cx++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let cov = 0;
      for (let y = 0; y < SS; y++) {
        for (let x = 0; x < SS; x++) {
          const idx = ((cy * SS + y) * w + (cx * SS + x)) * 4;
          const a = data[idx + 3] / 255;
          if (a <= 0.02) continue;
          cov += a;
          r += data[idx] * a;
          g += data[idx + 1] * a;
          b += data[idx + 2] * a;
        }
      }
      if (cov / area < 0.35) continue;

      const nx = (cx + 0.5) / GRID_W;
      const ny = (cy + 0.5) / GRID_H;
      const jitter = (Math.random() - 0.5) * 0.42;

      cells.push({
        nx,
        ny,
        r: Math.round(r / cov),
        g: Math.round(g / cov),
        b: Math.round(b / cov),
        delay: Math.random() * 0.3,
        angle: Math.atan2(ny - 0.5, nx - 0.5) + jitter,
        rot: (Math.random() - 0.5) * 5,
        size: 0.85 + Math.random() * 0.3,
        hot: Math.random() < 0.018,
        right:
          Math.abs(nx * MOUSE_W - RIGHT_BUTTON_CENTRE.x) < 42 &&
          Math.abs(ny * MOUSE_H - RIGHT_BUTTON_CENTRE.y) < 30,
      });
    }
  }
  return cells;
}

/* ------------------------------------------------------------------ */
/*  Shared copy                                                        */
/* ------------------------------------------------------------------ */

function HeroCopy() {
  return (
    <>
      <p className="inline-flex items-center gap-2 rounded-full bg-surface px-4 py-2 text-sm font-medium text-brand-dark">
        <span className="h-2 w-2 animate-pulse-dot rounded-full bg-brand" />
        QR pairing in under 10 seconds
      </p>
      <h1 className="mt-6 font-display text-[2.05rem] leading-[1.08] font-bold tracking-tight text-balance sm:text-5xl lg:text-6xl">
        Your phone is the
        <br />
        <span className="td-gradient-text">mouse, clicker &amp; keyboard.</span>
      </h1>
      <p className="mt-6 max-w-lg text-lg leading-relaxed text-muted">
        TapDesk turns your Android phone into a wireless mouse, presentation
        remote and full keyboard for your PC. Walk the room, click the board,
        advance the deck — no cables, no receivers, no walking back to the desk.
      </p>
      <ul className="mt-7 hidden flex-wrap gap-x-6 gap-y-2 text-sm font-medium text-ink/70 sm:flex">
        <li className="flex items-center gap-2">
          <span className="h-1.5 w-1.5 rounded-full bg-brand" /> Works on your
          own Wi-Fi
        </li>
        <li className="flex items-center gap-2">
          <span className="h-1.5 w-1.5 rounded-full bg-brand" /> No account, no
          cloud
        </li>
        <li className="flex items-center gap-2">
          <span className="h-1.5 w-1.5 rounded-full bg-brand" /> Android 8+
        </li>
      </ul>
    </>
  );
}

function HeroCta({ heading = false }: { heading?: boolean }) {
  return (
    <div className="flex flex-col items-center gap-5 text-center">
      {heading ? (
        <div className="max-w-xl">
          <p className="font-display text-3xl font-bold tracking-tight sm:text-4xl">
            One phone. One scan.
            <span className="td-gradient-text"> You own the room.</span>
          </p>
        </div>
      ) : null}
      <div className="flex flex-col gap-3 sm:flex-row">
        <Link
          href="/download"
          className="inline-flex min-h-14 items-center justify-center gap-2.5 rounded-full bg-brand px-8 text-lg font-semibold text-white transition-all hover:bg-brand-dark hover:shadow-xl hover:shadow-brand/30"
        >
          <Smartphone className="h-5 w-5" aria-hidden />
          Download the Android app
        </Link>
        <Link
          href="/download#desktop"
          className="inline-flex min-h-14 items-center justify-center gap-2.5 rounded-full border border-ink/15 px-8 text-lg font-semibold text-ink transition-all hover:border-brand hover:text-brand-dark"
        >
          <Monitor className="h-5 w-5" aria-hidden />
          Get the desktop app
        </Link>
      </div>
      <p className="text-sm text-muted">
        Free · Windows 10/11 + Android 8.0+ · iOS and macOS coming soon
      </p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Hero                                                               */
/* ------------------------------------------------------------------ */

export function Hero() {
  const reduced = usePrefersReducedMotion();
  const enhanced = !reduced;

  const trackRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const copyRef = useRef<HTMLDivElement>(null);
  const ctaRef = useRef<HTMLDivElement>(null);
  const cueRef = useRef<HTMLDivElement>(null);
  const progressRef = useRef(0);
  const cellsRef = useRef<Cell[] | null>(null);

  const draw = useCallback((p: number) => {
    const canvas = canvasRef.current;
    const cells = cellsRef.current;
    if (!canvas || !cells || cells.length === 0) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    const narrow = w < 768;
    const minDim = Math.min(w, h);

    /* --- position + scale ------------------------------------- */
    const travel = easeInOutCubic(clamp01(p / TRAVEL_END));
    const targetH = (narrow ? 0.44 : 0.68) * h;
    const grow = 1 + 0.1 * smoothstep(0.1, TRAVEL_END, p);
    const scale = (targetH / MOUSE_H) * grow;

    const fromX = narrow ? w / 2 : w * 0.2;
    const fromY = narrow ? h * 0.84 : h * 0.5;
    const toY = narrow ? h * 0.5 : h * 0.5;
    const cx = fromX + (w / 2 - fromX) * travel;
    const cy = fromY + (toY - fromY) * travel;

    const { ox, oy } = mouseOrigin(cx, cy, scale);
    const cellSize = (MOUSE_W * scale) / GRID_W;

    /* --- explosion progress ------------------------------------ */
    const rawT = clamp01(
      (p - EXPLODE_START) / (EXPLODE_END - EXPLODE_START),
    );
    const exploded = p > EXPLODE_START;

    /* --- click pulse on the right button ----------------------- */
    const clickAmt =
      smoothstep(0.12, 0.2, p) * (1 - smoothstep(0.34, 0.42, p)) * (1 - rawT);

    /* --- cells ------------------------------------------------- */
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      const bx = ox + c.nx * MOUSE_W * scale;
      const by = oy + c.ny * MOUSE_H * scale;

      let px = bx;
      let py = by;
      let alpha = 1;
      let size = cellSize * c.size;
      let rot = 0;

      if (c.hot) {
        ctx.fillStyle = "#86EFAC";
      } else if (c.right && clickAmt > 0.02) {
        ctx.fillStyle = `rgb(${Math.round(
          c.r + (134 - c.r) * clickAmt,
        )},${Math.round(c.g + (239 - c.g) * clickAmt)},${Math.round(
          c.b + (172 - c.b) * clickAmt,
        )})`;
      } else {
        ctx.fillStyle = `rgb(${c.r},${c.g},${c.b})`;
      }

      if (exploded) {
        const tp = clamp01((rawT - c.delay) / (1 - c.delay));
        const e = easeOutCubic(clamp01((tp - 0.08) / 0.92));
        const dx = c.nx - 0.5;
        const dy = c.ny - 0.5;
        const len = Math.hypot(dx, dy) || 0.001;
        const dirX = dx / len;
        const dirY = dy / len;
        const k = minDim / 900;
        const reach = (200 + len * 1500) * k;
        px = bx + dirX * reach * e + Math.sin(c.rot * 3) * 40 * tp * k;
        py = by + dirY * reach * 0.82 * e + 560 * k * tp * tp;
        alpha = tp < 0.72 ? 1 : 1 - (tp - 0.72) / 0.28;
        size = cellSize * c.size * (1 - 0.4 * tp);
        rot = c.rot * tp;
      }

      if (alpha <= 0.01) continue;

      ctx.globalAlpha = alpha;
      if (rot !== 0) {
        ctx.save();
        ctx.translate(px, py);
        ctx.rotate(rot);
        ctx.fillRect(-size / 2 - 0.5, -size / 2 - 0.5, size + 1, size + 1);
        ctx.restore();
      } else {
        ctx.fillRect(px - size / 2 - 0.5, py - size / 2 - 0.5, size + 1, size + 1);
      }
    }
    ctx.globalAlpha = 1;

    /* --- shockwave ring at the moment of the burst ------------ */
    if (p > EXPLODE_START - 0.02 && rawT < 0.55) {
      const ringT = easeOutCubic(clamp01(rawT / 0.55));
      const radius = ringT * Math.max(w, h) * 0.62;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(22,163,74,${(1 - ringT) * 0.5})`;
      ctx.lineWidth = 3 * (1 - ringT) + 0.5;
      ctx.stroke();
    }

    /* --- pointer + highlight ring on the right button ---------- */
    if (clickAmt > 0.02) {
      const ringX = ox + (RIGHT_BUTTON_CENTRE.x / MOUSE_W) * MOUSE_W * scale;
      const ringY = oy + (RIGHT_BUTTON_CENTRE.y / MOUSE_H) * MOUSE_H * scale;
      const rad = cellSize * 3.4 * (0.8 + clickAmt * 0.5);
      ctx.beginPath();
      ctx.arc(ringX, ringY, rad, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(22,163,74,${0.55 * clickAmt})`;
      ctx.lineWidth = 2;
      ctx.stroke();

      /* classic arrow cursor gliding onto the button */
      const k = smoothstep(0.12, 0.26, p);
      const px0 = cx + (1 - k) * -minDim * 0.22;
      const py0 = cy + (1 - k) * -minDim * 0.18;
      const s = Math.max(10, minDim * 0.026);
      ctx.save();
      ctx.translate(px0, py0);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, s * 1.7);
      ctx.lineTo(s * 0.42, s * 1.28);
      ctx.lineTo(s * 0.72, s * 1.95);
      ctx.lineTo(s * 1.02, s * 1.8);
      ctx.lineTo(s * 0.73, s * 1.15);
      ctx.lineTo(s * 1.28, s * 1.05);
      ctx.closePath();
      ctx.fillStyle = "#0A0A0A";
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = "#ffffff";
      ctx.stroke();
      ctx.restore();
    }
  }, []);

  /* --- animation loop ---------------------------------------- */
  useEffect(() => {
    if (!enhanced) return;
    cellsRef.current = buildCells();
    let frame = 0;
    let running = true;

    const loop = () => {
      if (!running) return;
      draw(progressRef.current);
      frame = requestAnimationFrame(loop);
    };
    frame = requestAnimationFrame(loop);

    const onScroll = () => {
      const el = trackRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const total = rect.height - window.innerHeight;
      const p = total <= 0 ? 0 : clamp01(-rect.top / total);
      progressRef.current = p;

      const away = smoothstep(0.04, 0.34, p);
      if (copyRef.current) {
        copyRef.current.style.opacity = String(1 - away);
        copyRef.current.style.transform = `translate3d(${away * 64}px, ${
          -away * 40
        }px, 0)`;
        copyRef.current.style.filter = `blur(${away * 6}px)`;
      }
      if (ctaRef.current) {
        const show = smoothstep(CTA_START, CTA_START + 0.1, p);
        ctaRef.current.style.opacity = String(show);
        ctaRef.current.style.transform = `translate3d(0, ${(1 - show) * 48}px, 0) scale(${0.92 + show * 0.08})`;
        ctaRef.current.style.pointerEvents = show > 0.6 ? "auto" : "none";
      }
      if (cueRef.current) {
        cueRef.current.style.opacity = String(1 - smoothstep(0, 0.1, p));
      }
    };

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);

    return () => {
      running = false;
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, [enhanced, draw]);

  /* --- static hero (pre-hydration + reduced motion) ---------- */
  if (!enhanced) {
    return (
      <section className="relative overflow-hidden pt-28 pb-16 sm:pt-32">
        <div className="td-grid pointer-events-none absolute inset-0" />
        <div className="relative mx-auto grid max-w-7xl items-center gap-10 px-5 sm:px-8 lg:grid-cols-2">
          <MouseSvg className="mx-auto w-full max-w-[19rem] lg:max-w-none lg:order-1" />
          <div className="lg:order-2">
            <HeroCopy />
            <div className="mt-9">
              <HeroCta />
            </div>
          </div>
        </div>
      </section>
    );
  }

  return (
    <div ref={trackRef} className="relative h-[340vh]">
      <div className="sticky top-0 h-[100svh] overflow-hidden">
        <div className="td-grid pointer-events-none absolute inset-0" />

        <canvas
          ref={canvasRef}
          aria-hidden
          className="pointer-events-none absolute inset-0 h-full w-full"
        />

        <div
          ref={copyRef}
          className="pointer-events-none absolute inset-0 flex justify-center px-5 will-change-transform sm:px-8 lg:justify-end"
        >
          <div className="hidden w-full max-w-xl flex-col justify-center lg:flex">
            <HeroCopy />
          </div>
          <div className="flex w-full max-w-lg flex-col justify-start pt-16 lg:hidden">
            <div className="rounded-3xl border border-black/8 bg-white p-6 shadow-xl shadow-black/5">
              <HeroCopy />
            </div>
          </div>
        </div>

        <div
          ref={ctaRef}
          className="pointer-events-none absolute inset-x-0 top-1/2 flex -translate-y-1/2 justify-center px-5 opacity-0 will-change-transform"
        >
          <HeroCta heading />
        </div>

        <div
          ref={cueRef}
          className="pointer-events-none absolute inset-x-0 bottom-5 flex flex-col items-center gap-1.5 text-center"
        >
          <span className="flex flex-col items-center gap-1.5 rounded-full bg-white/85 px-4 py-2 backdrop-blur-sm">
            <span className="text-[11px] font-medium tracking-widest text-muted uppercase">
              Scroll
            </span>
            <ArrowDown className="h-4 w-4 animate-bounce text-brand" aria-hidden />
          </span>
        </div>
      </div>
    </div>
  );
}