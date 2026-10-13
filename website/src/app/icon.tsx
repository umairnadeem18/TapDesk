import { ImageResponse } from "next/og";

export const size = { width: 64, height: 64 };
export const contentType = "image/png";

const PIXELS: [number, number][] = [
  [16, 10],
  [28, 10],
  [40, 10],
  [10, 22],
  [46, 22],
  [10, 34],
  [28, 22],
  [40, 34],
  [46, 46],
  [28, 46],
  [16, 46],
  [22, 34],
];

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0A0A0A",
          borderRadius: 14,
        }}
      >
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            width: 56,
            gap: 2,
          }}
        >
          {PIXELS.map(([x, y]) => (
            <div
              key={`${x}-${y}`}
              style={{
                width: 10,
                height: 10,
                background: "#16A34A",
              }}
            />
          ))}
        </div>
      </div>
    ),
    size,
  );
}