import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("host") ?? "riverviewadventist.org";
  const forwardedProtocol = requestHeaders.get("x-forwarded-proto");
  const protocol =
    forwardedProtocol ?? (host.includes("localhost") ? "http" : "https");
  const origin = `${protocol}://${host}`;

  return {
    metadataBase: new URL(origin),
    title: "Ministry Volunteers",
    description:
      "Free volunteer management for participating churches.",
    icons: {
      icon: "/ministry-logo.png",
      shortcut: "/ministry-logo.png",
      apple: "/ministry-logo.png",
    },
    openGraph: {
      title: "Volunteer Ministry Directory",
      description:
        "Church volunteer roles and terms.",
      type: "website",
      images: [
        {
          url: `${origin}/ministry-logo.png`,
          width: 1024,
          height: 1024,
          alt: "Ministry Volunteers",
        },
      ],
    },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  colorScheme: "light",
  themeColor: "#1f5f8b",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
