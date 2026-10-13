import { useId } from "react";
import clsx from "clsx";
import {
  LEFT_BUTTON_CENTRE,
  MOUSE_H,
  MOUSE_OUTLINE,
  MOUSE_SEAM,
  MOUSE_SPLIT,
  MOUSE_W,
  MOUSE_WHEEL,
  RIGHT_BUTTON_CENTRE,
} from "./mouse-geometry";

const VB = `0 0 ${MOUSE_W} ${MOUSE_H}`;

export function MouseSvg({
  className,
  glow = true,
}: {
  className?: string;
  glow?: boolean;
}) {
  const g = useId().replace(/:/g, "");

  return (
    <svg
      viewBox={VB}
      className={clsx("block", className)}
      role="img"
      aria-label="Illustration of a TapDesk wireless mouse"
    >
      <defs>
        <linearGradient id={`${g}-body`} x1="0" y1="0" x2="0.8" y2="1">
          <stop offset="0%" stopColor="#ECFDF5" />
          <stop offset="26%" stopColor="#BBF7D0" />
          <stop offset="55%" stopColor="#4ADE80" />
          <stop offset="82%" stopColor="#16A34A" />
          <stop offset="100%" stopColor="#15803D" />
        </linearGradient>
        <radialGradient id={`${g}-halo`} cx="0.5" cy="0.5" r="0.5">
          <stop offset="0%" stopColor="#86EFAC" stopOpacity="0.45" />
          <stop offset="100%" stopColor="#86EFAC" stopOpacity="0" />
        </radialGradient>
      </defs>

      {glow ? (
        <ellipse
          cx={MOUSE_W / 2}
          cy={MOUSE_H / 2 + 24}
          rx={165}
          ry={210}
          fill={`url(#${g}-halo)`}
        />
      ) : null}

      <path d={MOUSE_OUTLINE} fill={`url(#${g}-body)`} />
      <g strokeLinecap="round" fill="none">
        <path d={MOUSE_SPLIT} stroke="#0A0A0A" strokeOpacity="0.16" strokeWidth="6" />
        <path d={MOUSE_SEAM} stroke="#0A0A0A" strokeOpacity="0.34" strokeWidth="7" />
        <path d={MOUSE_OUTLINE} stroke="#0A0A0A" strokeOpacity="0.16" strokeWidth="3" />
      </g>
      <path d={MOUSE_WHEEL} fill="#0A0A0A" />
      <path
        d={MOUSE_WHEEL}
        fill="none"
        stroke="#86EFAC"
        strokeOpacity="0.5"
        strokeWidth="2.5"
      />
      <circle cx={MOUSE_W / 2} cy="206" r="7" fill="#0A0A0A" opacity="0.8" />

      <circle
        cx={LEFT_BUTTON_CENTRE.x}
        cy={LEFT_BUTTON_CENTRE.y}
        r="5"
        fill="#ffffff"
        opacity="0.55"
      />
      <circle
        cx={RIGHT_BUTTON_CENTRE.x}
        cy={RIGHT_BUTTON_CENTRE.y}
        r="5"
        fill="#ffffff"
        opacity="0.55"
      />
    </svg>
  );
}