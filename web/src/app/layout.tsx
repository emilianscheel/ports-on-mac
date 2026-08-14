import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
    variable: "--font-sans",
    subsets: ["latin"],
});

const geistMono = Geist_Mono({
    variable: "--font-geist-mono",
    subsets: ["latin"],
});

export const metadata: Metadata = {
    title: "Ports on Mac",
    description: "minimal macos menu bar app for inspecting used ports and freeing them quickly",
    icons: {
        icon: "/icon.png",
    },
};

export const viewport: Viewport = {
    width: "device-width",
    initialScale: 1,
    viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
    return (
        <html
            lang="en"
            className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
        >
            <head>
                <link rel="describedby" href="/llms.txt" />
            </head>
            <body className="min-h-full flex flex-col bg-white text-black">{children}</body>
        </html>
    );
}
