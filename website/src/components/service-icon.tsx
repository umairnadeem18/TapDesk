"use client";

import {
  Keyboard,
  MousePointer2,
  Presentation,
  QrCode,
  ShieldCheck,
  Wifi,
} from "lucide-react";
import clsx from "clsx";

export const SERVICE_ICONS = {
  MousePointer2,
  Presentation,
  Keyboard,
  QrCode,
  ShieldCheck,
  Wifi,
} as const;

export type ServiceIconName = keyof typeof SERVICE_ICONS;

export function ServiceIcon({
  name,
  className,
}: {
  name: ServiceIconName;
  className?: string;
}) {
  const Icon = SERVICE_ICONS[name];
  return (
    <Icon
      className={clsx("h-6 w-6", className)}
      strokeWidth={1.75}
      aria-hidden
    />
  );
}