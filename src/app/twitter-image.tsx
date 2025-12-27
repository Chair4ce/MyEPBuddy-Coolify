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
              flexDirection: "column",
              alignItems: "center",
              marginBottom: 24,
            }}
          >
            <svg
              width="80"
              height="80"
              viewBox="0 0 37 37"
              fill="none"
              style={{ marginBottom: 16 }}
            >
              <path
                fillRule="evenodd"
                clipRule="evenodd"
                d="M11.7466 3.14335L27.7568 3.14298C27.7653 3.14335 28.7277 3.09104 29.279 3.42715C29.6496 3.65313 30.0172 3.95001 30.2599 4.4462C30.3802 4.69208 30.4036 4.84942 30.4688 5.11529C30.552 5.45518 30.5759 5.65177 30.612 5.99985C30.6529 6.39409 30.6511 6.55074 30.6511 7.01403C30.6511 7.01403 32.5718 7.026 33.1853 7.15399C34.0366 7.3316 34.4594 7.58646 35.1221 8.21286C35.7649 8.82042 36.0674 9.4158 36.389 10.3233C36.801 11.4859 36.7254 12.3006 36.5871 13.5546C36.4768 14.5556 36.301 15.1051 35.9615 16.0273C35.6777 16.7983 35.4901 17.2271 35.0721 17.9026C34.7742 18.3837 34.2255 19.0477 34.2159 19.0593C34.2156 19.0476 34.2005 18.3113 34.1428 17.8953C34.0761 17.4147 33.9551 16.9702 33.6338 16.4414C33.3587 15.9886 33.1098 15.6443 32.6687 15.4693C31.7686 15.1126 30.0548 15.1887 28.388 15.3485C26.7993 15.5008 24.3777 16.2158 24.3388 16.2273C23.7778 16.4564 23.3234 16.6199 22.8769 16.7917C22.6303 16.8865 22.386 16.9841 22.1273 17.0968L36.6973 36.6812L21.2432 33.2017L5.57314 12.1833V7.67329L22.3503 30.253L30.141 32.1402L8.28705 2.74527H0V0H9.40825L11.7466 3.14335ZM26.9058 5.37773H13.4089L20.7713 15.2739C20.9747 15.1876 21.2148 15.087 21.5063 14.9669C21.6382 14.9125 21.7811 14.8543 21.9354 14.791C22.9203 14.3863 24.4866 13.8787 24.5024 13.8736C24.5121 13.871 26.1425 13.4386 27.2026 13.2747C29.193 12.9671 29.8445 12.8874 31.7811 12.9749C32.547 13.0095 33.0174 13.1315 33.6568 13.5546C34.0044 13.7847 34.6116 14.5166 34.6116 14.5166C34.6116 14.5166 34.836 13.2808 34.874 12.5975C34.9132 11.8872 34.9136 11.4124 34.6116 10.8017C34.3155 10.2029 34.0461 9.98168 33.5268 9.67937C32.8765 9.3011 32.3118 9.17653 31.5356 9.17652H25.8948L24.4906 7.01403H28.6408C28.6408 6.83469 28.6382 6.58876 28.5945 6.36968C28.5323 6.05747 28.4251 5.71901 28.1246 5.53681C27.8108 5.34663 26.9058 5.37773 26.9058 5.37773Z"
                fill="#3b82f6"
              />
              <path
                d="M10.3448 27.5399L15.5726 28.866L18.2184 32.4327L9.23808 30.4882L0 17.4552V13.2682L10.3448 27.5399Z"
                fill="#3b82f6"
              />
            </svg>
            <span
              style={{
                fontSize: 64,
                fontWeight: "bold",
                color: "white",
                letterSpacing: "-0.02em",
              }}
            >
              myEPBuddy
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


