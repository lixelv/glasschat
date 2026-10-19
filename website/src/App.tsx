import { useEffect, useState } from "react"
import { Apple, Code2, FileText, KeyRound, Plug, Sigma, Sparkles } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"

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

function DownloadButton({ release }: { release: Release | null }) {
  return (
    <div className="flex flex-col items-center gap-3">
      <Button
        render={<a href={release?.url ?? RELEASES} />}
        nativeButton={false}
        size="lg"
        className="h-14 rounded-full bg-white px-8 text-base font-semibold text-black shadow-[0_0_40px_rgba(255,255,255,0.25)] hover:bg-white/90"
      >
        <Apple className="size-5" />
        Download for macOS
      </Button>
      <p className="text-sm text-white/50">
        {release ? `${release.tag} · ` : ""}Free · macOS 26 or later · Apple silicon
      </p>
    </div>
  )
}

const features = [
  { icon: Sparkles, title: "Native to macOS", text: "SwiftUI and Liquid Glass. Light and dark, with matching app icons." },
  { icon: KeyRound, title: "Bring your own key", text: "OpenAI, OpenRouter, Ollama, LM Studio — any OpenAI-compatible API." },
  { icon: Code2, title: "Code and Markdown", text: "Streaming answers with syntax-highlighted code blocks." },
  { icon: Sigma, title: "LaTeX math", text: "Inline and display equations rendered like a textbook." },
  { icon: FileText, title: "Files", text: "Images, audio, PDFs and code: paste, drag and drop, or attach." },
  { icon: Plug, title: "MCP tools", text: "Connect conversations to local processes and remote services." },
]

const shots = [
  { src: "02-code.jpg", alt: "Syntax-highlighted Swift code in a GlassChat conversation" },
  { src: "03-math.jpg", alt: "LaTeX equations rendered in GlassChat" },
  { src: "04-tools.jpg", alt: "An MCP tool call in GlassChat" },
  { src: "05-models.jpg", alt: "A new chat in GlassChat" },
]

export default function App() {
  const release = useLatestDmg()
  return (
    <div className="min-h-screen bg-[#07080c] text-white">
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[720px] bg-[radial-gradient(ellipse_at_top,rgba(110,130,255,0.22),transparent_65%)]" />

      <header className="relative mx-auto flex max-w-6xl items-center justify-between px-4 py-5 sm:px-6">
        <a href={BASE} className="flex items-center gap-2.5 font-semibold">
          <img src={`${BASE}icon.png`} alt="" className="size-8" />
          GlassChat
        </a>
        <a href={`https://github.com/${REPO}`} className="text-sm text-white/60 transition hover:text-white">
          GitHub
        </a>
      </header>

      <main className="relative">
        <section className="mx-auto flex max-w-4xl flex-col items-center px-4 pt-16 text-center sm:px-6 sm:pt-24">
          <img src={`${BASE}icon.png`} alt="GlassChat icon" className="mb-8 size-28 drop-shadow-[0_20px_50px_rgba(110,130,255,0.35)]" />
          <Badge variant="outline" className="mb-6 border-white/15 bg-white/5 text-white/70">
            Open source · Native macOS app
          </Badge>
          <h1 className="text-5xl font-semibold tracking-tight sm:text-7xl">
            Your favorite AI models.
            <br />
            <span className="bg-gradient-to-b from-white to-white/50 bg-clip-text text-transparent">Right at home on Mac.</span>
          </h1>
          <p className="mt-6 max-w-2xl text-lg text-white/60">
            GlassChat is a native AI chat app built with SwiftUI and Liquid Glass. Bring your own API key, pick a model, and start talking.
          </p>
          <div className="mt-10">
            <DownloadButton release={release} />
          </div>
        </section>

        <section className="mx-auto mt-20 max-w-6xl px-4 sm:px-6">
          <img
            src={`${BASE}shots/01-light.jpg`}
            alt="GlassChat in light and dark appearance"
            className="w-full rounded-2xl border border-white/10 shadow-2xl"
          />
        </section>

        <section className="mx-auto mt-28 max-w-6xl px-4 sm:px-6">
          <h2 className="text-center text-3xl font-semibold tracking-tight sm:text-4xl">Everything you need. Nothing you don't.</h2>
          <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {features.map(({ icon: Icon, title, text }) => (
              <Card key={title} className="border-white/10 bg-white/[0.03] text-white backdrop-blur">
                <CardContent className="space-y-2">
                  <Icon className="size-5 text-indigo-300" />
                  <h3 className="font-medium">{title}</h3>
                  <p className="text-sm text-white/55">{text}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>

        <section className="mx-auto mt-28 grid max-w-6xl gap-6 px-4 sm:px-6 md:grid-cols-2">
          {shots.map((s) => (
            <img key={s.src} src={`${BASE}shots/${s.src}`} alt={s.alt} loading="lazy" className="w-full rounded-xl border border-white/10" />
          ))}
        </section>

        <section className="mx-auto mt-28 flex max-w-3xl flex-col items-center px-4 pb-28 text-center sm:px-6">
          <h2 className="mb-4 text-3xl font-semibold tracking-tight sm:text-4xl">Make yourself at home.</h2>
          <p className="mb-10 text-white/60">Your chats stay on your Mac. API keys live in the macOS Keychain.</p>
          <DownloadButton release={release} />
        </section>
      </main>

      <footer className="border-t border-white/10 py-8 text-center text-sm text-white/40">
        GlassChat · <a href={`https://github.com/${REPO}`} className="hover:text-white">Source on GitHub</a>
      </footer>
    </div>
  )
}
