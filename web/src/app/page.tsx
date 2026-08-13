import Image from "next/image"
import { Button } from "@/components/ui/button"

export default function Home() {
  return (
    <main className="relative flex min-h-svh flex-col items-center bg-white px-6">
      <div className="flex flex-1 flex-col items-center justify-center">
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
            ports-on-mac
          </h1>
          <p className="mt-4 max-w-[22rem] text-center text-[15px] leading-relaxed text-neutral-500">
            minimal macos menu bar app for inspecting used ports and freeing
            them quickly
          </p>
          <div className="mt-10 flex items-center gap-2.5">
            <Button
              nativeButton={false}
              render={<a href="#download" />}
              className="h-10 rounded-full px-6 text-[15px]"
            >
              Download
            </Button>
            <Button
              nativeButton={false}
              variant="outline"
              render={<a href="#buy" />}
              className="h-10 rounded-full border-black px-6 text-[15px] text-black hover:bg-neutral-50"
            >
              Buy
            </Button>
          </div>
        </div>
      </div>
      <p className="absolute inset-x-0 bottom-8 text-center text-sm text-neutral-400">
        7 trial days · $10 one time
      </p>
    </main>
  )
}
