import { useEffect, useRef, useState, type ReactNode } from "react"
import TechText from "@/components/TechText"

const REPO = "lixelv/glasschat"
const RELEASES = `https://github.com/${REPO}/releases/latest`
const BASE = import.meta.env.BASE_URL

type Release = { tag: string; url: string }

// The DMG name carries the version, so look it up from the latest release at runtime.
function useLatestDmg() {
  const [release, setRelease] = useState<Release | null>(null)
  useEffect(() => {
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`)
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((data) => {
        const dmg = data.assets?.find((a: { name: string }) => a.name.endsWith(".dmg"))
        if (dmg) setRelease({ tag: data.tag_name, url: dmg.browser_download_url })
      })
      .catch(() => {})
  }, [])
  return release
}

// Fades a block up once as it scrolls into view; CSS turns this off for reduced motion.
function Reveal({ children, className = "" }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [shown, setShown] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const io = new IntersectionObserver(([e]) => e.isIntersecting && (setShown(true), io.disconnect()), {
      rootMargin: "0px 0px -10% 0px",
    })
    io.observe(el)
    return () => io.disconnect()
  }, [])
  return (
    <div ref={ref} className={`reveal ${shown ? "is-shown" : ""} ${className}`}>
      {children}
    </div>
  )
}

function DownloadButton({ release, small = false }: { release: Release | null; small?: boolean }) {
  return (
    <a
      href={release?.url ?? RELEASES}
      className={`press inline-flex items-center gap-2 rounded-full bg-white font-medium text-black hover:bg-white/90 ${
        small ? "px-3 py-1 text-xs" : "px-7 py-3.5 text-[17px]"
      }`}
    >
      <svg viewBox="0 0 17 20" className={small ? "size-3" : "size-4"} fill="currentColor" aria-hidden>
        <path d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9C3.6 4.8 2 5.8 1.1 7.4c-1.8 3.2-.5 7.9 1.3 10.5.9 1.3 1.9 2.7 3.3 2.6 1.3-.1 1.8-.9 3.4-.9s2 .9 3.4.8c1.4 0 2.3-1.3 3.2-2.6 1-1.5 1.4-2.9 1.4-3-.1 0-2.8-1.1-2.9-4.2ZM11.6 3c.7-.9 1.2-2.1 1.1-3.3-1 .1-2.3.7-3 1.6-.7.8-1.3 2-1.1 3.2 1.1.1 2.3-.6 3-1.5Z" />
      </svg>
      Download for macOS
    </a>
  )
}

const features = [
  ["Native to macOS", "SwiftUI and Liquid Glass, in light and dark, with matching app icons."],
  ["Bring your own key", "OpenAI, OpenRouter, Ollama, LM Studio — any OpenAI‑compatible API."],
  ["Files, your way", "Images, audio, PDFs and code. Paste, drop, or attach."],
  ["Edit and branch", "Edit, retry, or branch from any message in the conversation."],
  ["Private by design", "Chats stay on your Mac. API keys live in the Keychain."],
  ["Open source", "Free to use, and every line is on GitHub."],
]

const showcases = [
  { img: "site-code.jpg", title: "Code, beautifully clear.", text: "Answers stream in with Markdown and syntax‑highlighted code blocks you can copy in one click." },
  { img: "site-math.jpg", title: "Math that reads like a textbook.", text: "LaTeX renders inline and on its own line, sharp at any size." },
  { img: "site-tools.jpg", title: "Your tools, in the conversation.", text: "Connect local processes and remote services with MCP, and watch each call as it happens." },
  { img: "site-models.jpg", title: "Any model. Your key.", text: "Set your base URL and key once, then switch models right from the chat window." },
]

export default function App() {
  const release = useLatestDmg()
  return (
    <div className="min-h-screen bg-black text-[#f5f5f7] antialiased">
      <nav className="sticky top-0 z-50 border-b border-white/[0.08] bg-[rgba(22,22,23,0.72)] backdrop-blur-xl backdrop-saturate-[1.8]">
        <div className="mx-auto flex h-12 max-w-[980px] items-center justify-between px-4 text-xs">
          <a href={BASE} className="flex items-center gap-2 text-[13px] font-semibold tracking-tight">
            <img src={`${BASE}icon.png`} alt="" className="size-5" />
            GlassChat
          </a>
          <div className="flex items-center gap-6">
            <a href={`https://github.com/${REPO}`} className="text-white/80 transition-colors hover:text-white">
              GitHub
            </a>
            <DownloadButton release={release} small />
          </div>
        </div>
      </nav>

      <main>
        <section className="mx-auto max-w-[980px] px-4 pt-20 text-center sm:pt-28">
          <div className="intro">
            <img src={`${BASE}icon.png`} alt="GlassChat icon" className="mx-auto mb-2 size-24" />
            <div className="mx-auto h-[120px] max-w-[760px] sm:h-[200px]">
              <TechText text="GlassChat" fontSize={170} fontWeight={600} letterSpacing={-0.03} color="#f5f5f7" accentColor="#2997ff" labels={false} intro="assemble" />
            </div>
            <h1 className="display mx-auto max-w-[720px] text-[40px] sm:text-[56px]">Your favorite AI models. Right at home on Mac.</h1>
            <p className="mx-auto mt-5 max-w-[560px] text-[19px] leading-relaxed text-[#86868b] sm:text-[21px]">
              A native chat app built with SwiftUI and Liquid Glass. Bring your own key, pick a model, and start talking.
            </p>
            <div className="mt-9 flex flex-col items-center gap-3">
              <DownloadButton release={release} />
              <p className="text-xs text-[#86868b]">{release ? `${release.tag} · ` : ""}Free · macOS 26 or later · Apple silicon</p>
            </div>
          </div>
        </section>

        <Reveal className="mx-auto mt-20 max-w-[1200px] px-4">
          <img src={`${BASE}shots/site-pair.jpg`} alt="GlassChat in light and dark appearance" className="w-full" />
        </Reveal>

        {showcases.map((s) => (
          <section key={s.img} className="mx-auto mt-32 max-w-[1200px] px-4 text-center sm:mt-44">
            <Reveal>
              <h2 className="display mx-auto max-w-[760px] text-[36px] sm:text-[56px]">{s.title}</h2>
              <p className="mx-auto mt-4 max-w-[560px] text-[19px] leading-relaxed text-[#86868b] sm:text-[21px]">{s.text}</p>
            </Reveal>
            <Reveal className="mt-12">
              <img src={`${BASE}shots/${s.img}`} alt={s.title} loading="lazy" className="w-full" />
            </Reveal>
          </section>
        ))}

        <section className="mx-auto mt-32 max-w-[980px] px-4 sm:mt-44">
          <Reveal>
            <h2 className="display text-center text-[36px] sm:text-[56px]">Everything in its place.</h2>
          </Reveal>
          <Reveal className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {features.map(([title, text]) => (
              <div key={title} className="rounded-[28px] bg-[#161617] p-8">
                <h3 className="text-[21px] font-semibold tracking-[-0.01em]">{title}</h3>
                <p className="mt-2 text-[17px] leading-relaxed text-[#86868b]">{text}</p>
              </div>
            ))}
          </Reveal>
        </section>

        <section className="mx-auto max-w-[980px] px-4 py-36 text-center sm:py-48">
          <Reveal>
            <h2 className="display text-[40px] sm:text-[64px]">Make yourself at home.</h2>
            <div className="mt-10 flex flex-col items-center gap-3">
              <DownloadButton release={release} />
              <a href={`https://github.com/${REPO}`} className="text-[17px] text-[#2997ff] hover:underline">
                View on GitHub ›
              </a>
            </div>
          </Reveal>
        </section>
      </main>

      <footer className="border-t border-[#424245] py-6">
        <p className="mx-auto max-w-[980px] px-4 text-xs text-[#86868b]">GlassChat is free and open source. Requires macOS 26 or later.</p>
      </footer>
    </div>
  )
}
