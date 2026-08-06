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
    title: "Volunteer Ministry Directory | Pasco Riverview",
    description:
      "Search and print the Pasco Riverview Adventist Church volunteer ministry directory.",
    icons: {
      icon: "/favicon.svg",
      shortcut: "/favicon.svg",
    },
    openGraph: {
      title: "Volunteer Ministry Directory",
      description:
        "Pasco Riverview Adventist Church volunteer roles and terms.",
      type: "website",
      images: [
        {
          url: `${origin}/og-blue.png`,
          width: 1730,
          height: 909,
          alt: "Pasco Riverview volunteer ministry directory",
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
