import { ImageResponse } from "next/og";

export const runtime = "edge";

export const alt = "My EPBuddy - Air Force EPB Statement Generator";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(135deg, #0f172a 0%, #1e3a5f 50%, #0f172a 100%)",
          fontFamily: "system-ui, sans-serif",
        }}
      >
        {/* Background pattern */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23ffffff' fill-opacity='0.03'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
            opacity: 0.5,
          }}
        />

        {/* Main content */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            textAlign: "center",
            padding: "0 60px",
          }}
        >
          {/* Logo/Title */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              marginBottom: 24,
            }}
          >
            <div
              style={{
                width: 70,
                height: 70,
                borderRadius: 14,
                background: "linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                marginRight: 20,
                boxShadow: "0 8px 32px rgba(59, 130, 246, 0.4)",
              }}
            >
              <span style={{ fontSize: 36, color: "white", fontWeight: "bold" }}>
                EP
              </span>
            </div>
            <span
              style={{
                fontSize: 64,
                fontWeight: "bold",
                color: "white",
                letterSpacing: "-0.02em",
              }}
            >
              My EPBuddy
            </span>
          </div>

          {/* Tagline */}
          <div
            style={{
              fontSize: 28,
              color: "#94a3b8",
              marginBottom: 32,
              maxWidth: 800,
              lineHeight: 1.4,
            }}
          >
            AI-Powered EPB Statement Generator for Air Force Enlisted
          </div>

          {/* Features */}
          <div
            style={{
              display: "flex",
              gap: 24,
            }}
          >
            {["Track Accomplishments", "Generate Statements", "myEval Ready"].map(
              (feature) => (
                <div
                  key={feature}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    padding: "10px 20px",
                    background: "rgba(255, 255, 255, 0.1)",
                    borderRadius: 24,
                    border: "1px solid rgba(255, 255, 255, 0.2)",
                  }}
                >
                  <span style={{ color: "#22c55e", fontSize: 18 }}>✓</span>
                  <span style={{ color: "#e2e8f0", fontSize: 18 }}>{feature}</span>
                </div>
              )
            )}
          </div>
        </div>
      </div>
    ),
    {
      ...size,
    }
  );
}

