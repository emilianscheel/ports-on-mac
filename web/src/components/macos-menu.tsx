"use client";

import { useState, type ComponentProps, type ReactNode } from "react";
import {
    Check,
    ChevronRight,
    Eye,
    Info,
    Key,
    Minus,
    MoveUpRight,
    Power,
    RefreshCw,
    RotateCw,
    ShoppingBag,
    Square,
} from "lucide-react";

import { cn } from "@/lib/utils";
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const menuFont =
    "font-[-apple-system,BlinkMacSystemFont,'SF_Pro_Text','Helvetica_Neue',sans-serif]";

const menuSurface = cn(
    menuFont,
    "w-[280px] rounded-[10px] bg-[#f6f6f6]/80 p-[5px] text-[13px] text-black/85 shadow-[0_0_0_0.5px_rgba(0,0,0,0.18),0_12px_40px_rgba(0,0,0,0.18)] backdrop-blur-xl backdrop-saturate-150",
);

const subSurface = cn(
    menuFont,
    "w-[220px] rounded-[10px] bg-[#f6f6f6]/80 p-[5px] text-[13px] text-black/85 shadow-[0_0_0_0.5px_rgba(0,0,0,0.18),0_12px_40px_rgba(0,0,0,0.18)] backdrop-blur-xl backdrop-saturate-150",
);

const itemClass = cn(
    "flex h-auto w-full items-center justify-start gap-2 rounded-[5px] border-0 bg-transparent px-2 py-[4px] text-left text-[13px] leading-[16px] font-normal text-black/90 shadow-none outline-none",
    "[&_svg]:size-[14px] [&_svg]:shrink-0 [&_svg]:text-black/65",
    "hover:bg-[#007AFF] hover:text-white hover:[&_svg]:text-white",
    "focus-visible:bg-[#007AFF] focus-visible:text-white focus-visible:[&_svg]:text-white",
);

const selectedItemClass =
    "bg-[#007AFF] text-white [&_svg]:text-white hover:bg-[#007AFF] hover:text-white";

const separatorClass = "mx-1 my-1 h-px bg-black/10";

type PortEntry = {
    id: string;
    kind: "service" | "inbound";
    domain?: string;
    port: number;
    process: string;
    icon: string;
    command: string;
    pid: number;
    user: string;
    fd: string;
};

const serviceEntry: PortEntry = {
    id: "service-3000",
    kind: "service",
    domain: "ports-on-mac.com",
    port: 3000,
    process: "node",
    icon: "/icons/ports-on-mac.png",
    command: "node",
    pid: 93252,
    user: "coderdojo",
    fd: "17u",
};

const inboundEntries: PortEntry[] = [
    {
        id: "inbound-1053",
        kind: "inbound",
        port: 1053,
        process: "container",
        icon: "/icons/terminal.png",
        command: "container",
        pid: 18401,
        user: "coderdojo",
        fd: "12u",
    },
    {
        id: "inbound-19820",
        kind: "inbound",
        port: 19820,
        process: "Ports",
        icon: "/icons/ports-on-mac.png",
        command: "Ports",
        pid: 44120,
        user: "coderdojo",
        fd: "21u",
    },
    {
        id: "inbound-29979",
        kind: "inbound",
        port: 29979,
        process: "Paper",
        icon: "/icons/paper.png",
        command: "Paper",
        pid: 55210,
        user: "coderdojo",
        fd: "18u",
    },
    {
        id: "inbound-50123",
        kind: "inbound",
        port: 50123,
        process: "Cursor",
        icon: "/icons/cursor.png",
        command: "Cursor",
        pid: 61002,
        user: "coderdojo",
        fd: "24u",
    },
];

function AppIcon({ src }: { src: string }) {
    return (
        <img
            src={src}
            alt=""
            width={18}
            height={18}
            className="size-[18px] rounded-[4px] object-cover"
        />
    );
}

function MenuButton({
    selected,
    className,
    ...props
}: ComponentProps<"button"> & { selected?: boolean }) {
    return (
        <button
            type="button"
            className={cn(itemClass, selected && selectedItemClass, className)}
            {...props}
        />
    );
}

function PortRow({
    entry,
    selected,
    onSelect,
    submenu,
}: {
    entry: PortEntry;
    selected: boolean;
    onSelect: () => void;
    submenu: ReactNode;
}) {
    return (
        <div className="relative">
            <DropdownMenu
                open={selected}
                modal={false}
                onOpenChange={(next) => {
                    if (next) onSelect();
                }}
            >
                <DropdownMenuTrigger
                    className={cn(itemClass, selected && selectedItemClass)}
                    onPointerEnter={onSelect}
                    onClick={onSelect}
                >
                    <AppIcon src={entry.icon} />
                    {entry.kind === "service" ? (
                        <span className="flex min-w-0 flex-1 flex-col items-start leading-tight">
                            <span className="font-medium">{entry.domain}</span>
                            <span
                                className={cn(
                                    "text-[11px]",
                                    selected ? "text-white/85" : "text-black/45",
                                )}
                            >
                                :{entry.port} {entry.process}
                            </span>
                        </span>
                    ) : (
                        <span className="flex-1 text-left">
                            :{entry.port} {entry.process}
                        </span>
                    )}
                    <ChevronRight
                        className={cn(
                            "ml-auto size-3.5",
                            selected ? "text-white" : "text-black/30",
                        )}
                    />
                </DropdownMenuTrigger>
                <DropdownMenuContent
                    side="right"
                    align="start"
                    sideOffset={6}
                    className="hidden"
                >
                    <DropdownMenuItem>Open</DropdownMenuItem>
                </DropdownMenuContent>
            </DropdownMenu>
            {selected ? (
                <div className="absolute top-0 left-full z-10 ml-1.5">{submenu}</div>
            ) : null}
        </div>
    );
}

function PortSubmenu({
    entry,
    useHttps,
    onToggleHttps,
}: {
    entry: PortEntry;
    useHttps: boolean;
    onToggleHttps: () => void;
}) {
    const openUrl = entry.domain
        ? `${useHttps ? "https" : "http"}://${entry.domain}`
        : `http://127.0.0.1:${entry.port}`;

    const metadata = [
        ["Command", entry.command],
        ["PID", String(entry.pid)],
        ["User", entry.user],
        ["Direction", "Inbound"],
        ["Protocol", "TCP"],
        ["Local", `*:${entry.port}`],
        ["State", "LISTEN"],
        ["FD", entry.fd],
        ["Socket", "IPv6"],
    ] as const;

    return (
        <div className={subSurface}>
            <div className="px-2.5 py-1.5 text-[11px] leading-[15px] text-black/40">
                {metadata.map(([label, value]) => (
                    <div key={label}>
                        {label}: {value}
                    </div>
                ))}
            </div>
            <div className={separatorClass} />
            <MenuButton
                onClick={() => window.open(openUrl, "_blank", "noopener,noreferrer")}
            >
                <MoveUpRight />
                Open
            </MenuButton>
            {entry.kind === "service" ? (
                <>
                    <MenuButton onClick={onToggleHttps}>
                        <Check className={useHttps ? "opacity-100" : "opacity-0"} />
                        Use HTTPS
                    </MenuButton>
                    <MenuButton>
                        <Minus />
                        Unassign Domain
                    </MenuButton>
                </>
            ) : null}
            <div className={separatorClass} />
            <MenuButton>
                <Square className="fill-current" />
                Kill
            </MenuButton>
        </div>
    );
}

export function MacosMenu({ checkoutHref }: { checkoutHref: string }) {
    const [openId, setOpenId] = useState(serviceEntry.id);
    const [useHttps, setUseHttps] = useState(true);
    const [showOutbound, setShowOutbound] = useState(false);

    const submenuFor = (entry: PortEntry) => (
        <PortSubmenu
            entry={entry}
            useHttps={useHttps}
            onToggleHttps={() => setUseHttps((value) => !value)}
        />
    );

    return (
        <div className="relative w-[506px] max-w-full">
            <div className={cn(menuSurface, "overflow-visible")}>
                <div className="flex items-start gap-2 px-2 py-1.5">
                    <span className="mt-[5px] size-[7px] shrink-0 rounded-full bg-black/25" />
                    <div>
                        <div className="text-[13px] leading-[16px] text-black/40">
                            Live
                        </div>
                        <div className="text-[11px] leading-[14px] text-black/35">
                            12 inbound, 30 outbound
                        </div>
                    </div>
                </div>

                <div className={separatorClass} />

                <div className="px-2 pt-1.5 pb-0.5 text-[11px] font-semibold tracking-wide text-black/40">
                    Services
                </div>
                <PortRow
                    entry={serviceEntry}
                    selected={openId === serviceEntry.id}
                    onSelect={() => setOpenId(serviceEntry.id)}
                    submenu={submenuFor(serviceEntry)}
                />

                <div className={separatorClass} />

                <div className="px-2 pt-1.5 pb-0.5 text-[11px] font-semibold tracking-wide text-black/40">
                    Inbound
                </div>
                {inboundEntries.map((entry) => (
                    <PortRow
                        key={entry.id}
                        entry={entry}
                        selected={openId === entry.id}
                        onSelect={() => setOpenId(entry.id)}
                        submenu={submenuFor(entry)}
                    />
                ))}

                <div className={separatorClass} />

                <MenuButton onClick={() => setShowOutbound((value) => !value)}>
                    <Eye />
                    {showOutbound ? "Hide Outbound Ports" : "Show Outbound Ports"}
                </MenuButton>
                <MenuButton className="hover:[&_span]:text-white">
                    <RefreshCw />
                    Refresh
                    <span className="ml-auto text-[13px] text-black/35">⌘R</span>
                </MenuButton>
                <MenuButton>
                    <RotateCw />
                    Check for Updates...
                </MenuButton>
                <a
                    href={checkoutHref}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={itemClass}
                >
                    <ShoppingBag />
                    Buy License Key
                </a>
                <MenuButton>
                    <Key />
                    Activate License Key
                </MenuButton>
                <MenuButton>
                    <Info />
                    About Ports on Mac
                </MenuButton>
                <MenuButton>
                    <Power />
                    Quit
                </MenuButton>
            </div>
        </div>
    );
}
