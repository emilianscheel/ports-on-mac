"use client";

import { ThemeProvider as NextThemesProvider, useTheme } from "next-themes";
import { useEffect, type ComponentProps } from "react";

function SystemThemeSync() {
    const { setTheme } = useTheme();

    useEffect(() => {
        setTheme("system");
    }, [setTheme]);

    return null;
}

export function ThemeProvider({
    children,
    ...props
}: ComponentProps<typeof NextThemesProvider>) {
    return (
        <NextThemesProvider {...props}>
            <SystemThemeSync />
            {children}
        </NextThemesProvider>
    );
}
