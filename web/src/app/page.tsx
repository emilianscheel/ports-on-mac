import Image from "next/image";
import { Button } from "@/components/ui/button";

const checkoutHref = `/checkout?products=${process.env.NEXT_PUBLIC_POLAR_PRODUCT_ID}`;

export default function Home() {
    return (
        <main className="grid grid-cols-1 xl:min-h-svh xl:grid-cols-2">
            <section className="relative flex min-h-svh w-full flex-col items-center justify-center bg-white px-6">
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
                            render={<a href={checkoutHref} />}
                            className="h-10 rounded-full bg-transparent px-4 text-[15px] text-black hover:bg-neutral-100"
                        >
                            Buy
                        </Button>
                    </div>
                </div>
                <p className="absolute inset-x-0 bottom-[max(2rem,env(safe-area-inset-bottom,0px))] text-center text-sm text-neutral-400">
                    7 trial days · $10 one time
                </p>
            </section>
            <aside className="min-h-svh w-full bg-neutral-100" aria-hidden="true" />
        </main>
    );
}
