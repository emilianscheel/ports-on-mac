"use client";

import {
    useLayoutEffect,
    useMemo,
    useState,
    type ComponentProps,
    type ReactNode,
} from "react";
import {
    Check,
    ChevronRight,
    CircleX,
    Eye,
    Info,
    Key,
    Minus,
    MoveUpRight,
    Plus,
    Power,
    RefreshCw,
    RotateCw,
    Search,
    ShoppingBag,
    Square,
} from "lucide-react";

import { cn } from "@/lib/utils";

const desktopMenuQuery = "(min-width: 768px)";

function isDesktopMenu() {
    return window.matchMedia(desktopMenuQuery).matches;
}

const menuFont =
    "font-[-apple-system,BlinkMacSystemFont,'SF_Pro_Text','Helvetica_Neue',sans-serif]";

const menuSurface = cn(
    menuFont,
    "w-[280px] rounded-[10px] bg-[#f6f6f6]/80 p-[5px] text-[13px] text-black/85 shadow-[0_0_0_0.5px_rgba(0,0,0,0.18),0_12px_40px_rgba(0,0,0,0.18)] backdrop-blur-xl backdrop-saturate-150",
);

const subSurface = cn(
    menuFont,
    "w-full rounded-[10px] bg-[#f6f6f6]/80 p-[5px] text-[13px] text-black/85 shadow-[0_0_0_0.5px_rgba(0,0,0,0.18),0_12px_40px_rgba(0,0,0,0.18)] backdrop-blur-xl backdrop-saturate-150 md:w-[220px]",
);

const itemClass = cn(
    "group/item flex h-auto w-full items-center justify-start gap-2 rounded-[5px] border-0 bg-transparent px-2 py-[4px] text-left text-[13px] leading-[16px] font-normal text-black/90 shadow-none outline-none",
    "[&_svg]:size-[14px] [&_svg]:shrink-0 [&_svg]:text-black/65",
    "hover:bg-[#007AFF] hover:text-white hover:[&_svg]:text-white hover:[&_span]:text-white",
    "focus-visible:bg-[#007AFF] focus-visible:text-white focus-visible:[&_svg]:text-white focus-visible:[&_span]:text-white",
);

const selectedItemClass =
    "bg-[#007AFF] text-white [&_svg]:text-white [&_span]:text-white hover:bg-[#007AFF] hover:text-white hover:[&_span]:text-white";

const separatorClass = "mx-1 my-1 h-px bg-black/10";

type PortEntry = {
    id: string;
    kind: "service" | "inbound";
    domain?: string;
    port: number;
    process: string;
    icon: string;
    command: string;
    protocol: string;
    folder?: string;
    cwd?: string;
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
    protocol: "TCP",
    folder: "ports-on-mac",
    cwd: "/Users/coderdojo/Developer/ports-on-mac",
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
        protocol: "TCP",
        folder: "api",
        cwd: "/Users/coderdojo/Developer/api",
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
        protocol: "TCP",
        folder: "Ports",
        cwd: "/Applications/Ports.app",
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
        protocol: "UDP",
        folder: "paper",
        cwd: "/Users/coderdojo/Developer/paper",
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
        protocol: "TCP",
        folder: "cursor",
        cwd: "/Applications/Cursor.app",
        pid: 61002,
        user: "coderdojo",
        fd: "24u",
    },
];

function matchesSearch(entry: PortEntry, query: string) {
    const needle = query.trim().toLowerCase();
    if (!needle) return true;
    return [
        entry.process,
        entry.command,
        String(entry.port),
        `:${entry.port}`,
        entry.protocol,
        entry.folder,
        entry.cwd,
        entry.domain,
    ].some((value) => value?.toLowerCase().includes(needle));
}

function domainFromQuery(query: string) {
    const value = query.trim().toLowerCase();
    if (!value) return null;
    if (value.includes(".")) return value;
    const slug = value.replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    return slug ? `${slug}.com` : null;
}

function MenuSearchField({
    value,
    onChange,
}: {
    value: string;
    onChange: (value: string) => void;
}) {
    return (
        <div className="flex h-7 items-center gap-2 px-2">
            <Search className="size-[14px] shrink-0 text-black/35" />
            <input
                value={value}
                onChange={(event) => onChange(event.target.value)}
                placeholder="Search"
                spellCheck={false}
                className="min-w-0 flex-1 translate-y-px bg-transparent text-[13px] leading-[16px] text-black/90 caret-[#8e8e93] outline-none placeholder:text-black/35 selection:bg-black/12 selection:text-inherit"
            />
            {value ? (
                <button
                    type="button"
                    onClick={() => onChange("")}
                    className="shrink-0 text-black/35 hover:text-black/55"
                    aria-label="Clear"
                >
                    <CircleX className="size-[14px]" />
                </button>
            ) : null}
        </div>
    );
}

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

function SubmenuFlyout({ children }: { children: ReactNode }) {
    return (
        <div className="mt-1 md:absolute md:top-0 md:left-full md:z-10 md:mt-0 md:ml-1.5">
            {children}
        </div>
    );
}

function PortRow({
    entry,
    selected,
    onSelect,
    onHover,
    submenu,
}: {
    entry: PortEntry;
    selected: boolean;
    onSelect: () => void;
    onHover: () => void;
    submenu: ReactNode;
}) {
    return (
        <div className="relative">
            <MenuButton
                selected={selected}
                onPointerEnter={onHover}
                onClick={onSelect}
            >
                <AppIcon src={entry.icon} />
                {entry.kind === "service" ? (
                    <span className="flex min-w-0 flex-1 flex-col items-start leading-tight">
                        <span className="font-medium">{entry.domain}</span>
                        <span
                            className={cn(
                                "text-[11px] text-black/45 group-hover/item:text-white/85 group-focus-visible/item:text-white/85",
                                selected && "text-white/85",
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
                        selected ? "text-white max-md:rotate-90" : "text-black/30",
                    )}
                />
            </MenuButton>
            {selected ? <SubmenuFlyout>{submenu}</SubmenuFlyout> : null}
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
        ["Protocol", entry.protocol],
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

function AssignDomainRow({
    selected,
    onSelect,
    onHover,
    processes,
    onAssign,
}: {
    selected: boolean;
    onSelect: () => void;
    onHover: () => void;
    processes: PortEntry[];
    onAssign: (entry: PortEntry) => void;
}) {
    return (
        <div className="relative">
            <MenuButton
                selected={selected}
                onPointerEnter={onHover}
                onClick={onSelect}
            >
                <Plus />
                Assign Domain
                <ChevronRight
                    className={cn(
                        "ml-auto size-3.5",
                        selected ? "text-white max-md:rotate-90" : "text-black/30",
                    )}
                />
            </MenuButton>
            {selected ? (
                <SubmenuFlyout>
                    <div className={subSurface}>
                        {processes.map((entry) => (
                            <MenuButton key={entry.id} onClick={() => onAssign(entry)}>
                                <AppIcon src={entry.icon} />
                                :{entry.port}  {entry.process}
                            </MenuButton>
                        ))}
                    </div>
                </SubmenuFlyout>
            ) : null}
        </div>
    );
}

export function MacosMenu({ checkoutHref }: { checkoutHref: string }) {
    const [openId, setOpenId] = useState<string | null>(serviceEntry.id);
    const [useHttps, setUseHttps] = useState(true);
    const [showOutbound, setShowOutbound] = useState(false);
    const [query, setQuery] = useState("");
    const [assignments, setAssignments] = useState<Record<string, string>>({});

    useLayoutEffect(() => {
        if (!isDesktopMenu()) setOpenId(null);
    }, []);

    const hoverItem = (id: string) => {
        if (isDesktopMenu()) setOpenId(id);
    };

    const selectItem = (id: string) => {
        if (isDesktopMenu()) {
            setOpenId(id);
            return;
        }
        setOpenId((current) => (current === id ? null : id));
    };

    const services = useMemo(() => {
        const assigned = inboundEntries.flatMap((entry) => {
            const domain = assignments[entry.id];
            return domain ? [{ ...entry, kind: "service" as const, domain }] : [];
        });
        return [serviceEntry, ...assigned];
    }, [assignments]);

    const inbound = useMemo(
        () => inboundEntries.filter((entry) => !assignments[entry.id]),
        [assignments],
    );

    const isSearching = query.trim().length > 0;
    const visibleServices = services.filter((entry) => matchesSearch(entry, query));
    const visibleInbound = inbound.filter((entry) => matchesSearch(entry, query));
    const hasMatches = visibleServices.length > 0 || visibleInbound.length > 0;
    const showAssign = isSearching && !hasMatches && inbound.length > 0;

    const submenuFor = (entry: PortEntry) => (
        <PortSubmenu
            entry={entry}
            useHttps={useHttps}
            onToggleHttps={() => setUseHttps((value) => !value)}
        />
    );

    const assignFromSearch = (entry: PortEntry) => {
        const domain = domainFromQuery(query);
        if (!domain) return;
        setAssignments((current) => ({ ...current, [entry.id]: domain }));
        setQuery("");
        setOpenId(entry.id);
    };

    return (
        <div className="relative w-[280px] max-w-full md:w-[506px]">
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
                <MenuSearchField value={query} onChange={setQuery} />
                <div className={separatorClass} />

                {showAssign ? (
                    <AssignDomainRow
                        selected={openId === "assign-domain"}
                        onSelect={() => selectItem("assign-domain")}
                        onHover={() => hoverItem("assign-domain")}
                        processes={inbound}
                        onAssign={assignFromSearch}
                    />
                ) : null}

                {!isSearching || visibleServices.length > 0 ? (
                    <>
                        <div className="px-2 pt-1.5 pb-0.5 text-[11px] font-semibold tracking-wide text-black/40">
                            Services
                        </div>
                        {visibleServices.map((entry) => (
                            <PortRow
                                key={entry.id}
                                entry={entry}
                                selected={openId === entry.id}
                                onSelect={() => selectItem(entry.id)}
                                onHover={() => hoverItem(entry.id)}
                                submenu={submenuFor(entry)}
                            />
                        ))}
                    </>
                ) : null}

                {!isSearching || visibleInbound.length > 0 ? (
                    <>
                        <div className={separatorClass} />
                        <div className="px-2 pt-1.5 pb-0.5 text-[11px] font-semibold tracking-wide text-black/40">
                            Inbound
                        </div>
                        {visibleInbound.map((entry) => (
                            <PortRow
                                key={entry.id}
                                entry={entry}
                                selected={openId === entry.id}
                                onSelect={() => selectItem(entry.id)}
                                onHover={() => hoverItem(entry.id)}
                                submenu={submenuFor(entry)}
                            />
                        ))}
                    </>
                ) : null}

                {isSearching && !hasMatches && !showAssign ? (
                    <div className="px-2 py-[4px] text-[13px] text-black/35">
                        No Results
                    </div>
                ) : null}

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
