import clsx from "clsx";

/** Pixel-style cursor mark used as the TapDesk logo. */
export function Logo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      className={clsx(className)}
      role="img"
      aria-label="TapDesk logo"
    >
      <rect width="32" height="32" rx="8" fill="#0A0A0A" />
      <g fill="#16A34A">
        <rect x="8" y="5" width="4" height="4" rx="1" />
        <rect x="14" y="5" width="4" height="4" rx="1" />
        <rect x="20" y="5" width="4" height="4" rx="1" />
        <rect x="5" y="11" width="4" height="4" rx="1" />
        <rect x="23" y="11" width="4" height="4" rx="1" />
        <rect x="5" y="17" width="4" height="4" rx="1" />
        <rect x="14" y="11" width="4" height="4" rx="1" />
        <rect x="20" y="17" width="4" height="4" rx="1" />
        <rect x="23" y="23" width="4" height="4" rx="1" />
        <rect x="14" y="23" width="4" height="4" rx="1" />
        <rect x="8" y="23" width="4" height="4" rx="1" />
        <rect x="11" y="17" width="4" height="4" rx="1" />
      </g>
      <rect x="26" y="26" width="4" height="4" rx="1" fill="#86EFAC" />
    </svg>
  );
}