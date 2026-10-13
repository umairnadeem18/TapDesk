import { ImageResponse } from "next/og";

export const alt = "TapDesk — your phone is the mouse, clicker and keyboard";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          background: "#ffffff",
          padding: "72px",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", maxWidth: 700 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div
              style={{
                width: 56,
                height: 56,
                borderRadius: 16,
                background: "#0A0A0A",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#16A34A",
                fontSize: 32,
                fontWeight: 700,
              }}
            >
              T
            </div>
            <div
              style={{
                fontSize: 34,
                fontWeight: 700,
                color: "#0A0A0A",
                display: "flex",
              }}
            >
              Tap
              <span style={{ color: "#16A34A" }}>Desk</span>
            </div>
          </div>
          <div
            style={{
              marginTop: 36,
              fontSize: 60,
              lineHeight: 1.1,
              fontWeight: 800,
              color: "#0A0A0A",
              display: "flex",
              flexDirection: "column",
            }}
          >
            <div>Your phone is the mouse,</div>
            <div style={{ color: "#16A34A" }}>clicker &amp; keyboard.</div>
          </div>
          <div style={{ marginTop: 24, fontSize: 28, color: "#6B7280" }}>
            Pair by QR code in under 10 seconds. No cables, no cloud.
          </div>
        </div>

        <div
          style={{
            width: 250,
            height: 330,
            borderRadius: 125,
            background: "linear-gradient(160deg, #86EFAC 0%, #16A34A 45%, #15803D 100%)",
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              width: 34,
              height: 68,
              borderRadius: 17,
              background: "#0A0A0A",
              marginTop: 56,
            }}
          />
        </div>
      </div>
    ),
    size,
  );
}