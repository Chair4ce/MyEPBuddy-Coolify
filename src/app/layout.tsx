import type { Metadata, Viewport } from "next";
import { JetBrains_Mono } from "next/font/google";
import { ThemeProvider } from "@/components/providers/theme-provider";
import { Toaster } from "@/components/ui/sonner";
import "./globals.css";

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-sans",
});

export const metadata: Metadata = {
  title: "My EPBuddy | Air Force Performance Brief Tool",
  description:
    "Track accomplishments and generate myEval-ready Enlisted Performance Brief (EPB) narrative statements compliant with AFI 36-2406.",
  keywords: [
    "Air Force",
    "EPB",
    "myEval",
    "Performance Brief",
    "Enlisted",
    "AFI 36-2406",
  ],
  authors: [{ name: "My EPBuddy" }],
  openGraph: {
    title: "My EPBuddy",
    description:
      "Air Force EPB narrative statement generator for supervisors and subordinates",
    type: "website",
    siteName: "My EPBuddy",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#0a0a0a" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${jetbrainsMono.variable} font-sans antialiased min-h-screen`}
      >
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {children}
          <Toaster position="top-center" />
        </ThemeProvider>
      </body>
    </html>
  );
}

