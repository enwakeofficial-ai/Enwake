import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ENWAKE — Candles & Quiet Rituals",
  description: "Discover a quieter kind of luxury. Explore scented candles and thoughtful gifts in warm ivory, burgundy and charcoal.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
