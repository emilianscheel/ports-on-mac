import Image from "next/image";
import { Button } from "@/components/ui/button";

export default function Home() {
    return (
        <main className="grid min-h-svh grid-cols-1 md:grid-cols-2">
            <section className="relative flex flex-col items-center justify-center bg-white px-6">
                <div className="flex flex-col items-center">
                    <Image
                        src="/icon.png"
                        alt="ports-on-mac"
                        width={128}
                        height={128}
                        priority
                        className="size-28"
                    />
                    <h1 className="mt-8 text-[28px] font-semibold tracking-tight text-black">
                        Ports on Mac
                    </h1>
                    <p className="mt-4 max-w-[22rem] text-center text-[15px] leading-relaxed text-neutral-500">
                        minimal macos menu bar app for inspecting used ports and freeing them
                        quickly
                    </p>
                    <div className="mt-10 flex items-center gap-2.5">
                        <Button
                            nativeButton={false}
                            variant="secondary"
                            render={<a href="#download" />}
                            className="h-10 rounded-full bg-neutral-100 px-4 text-[15px] text-black hover:bg-neutral-200"
                        >
                            Download
                        </Button>
                        <Button
                            nativeButton={false}
                            variant="ghost"
                            render={<a href="#buy" />}
                            className="h-10 rounded-full bg-transparent px-4 text-[15px] text-black hover:bg-neutral-100"
                        >
                            Buy
                        </Button>
                    </div>
                </div>
                <p className="absolute inset-x-0 bottom-8 text-center text-sm text-neutral-400">
                    7 trial days · $10 one time
                </p>
            </section>
            <aside className="hidden min-h-svh bg-neutral-100 md:block" aria-hidden="true" />
        </main>
    );
}
