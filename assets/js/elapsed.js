function formatDuration(secs) {
  if (secs < 60) return `${secs}s`
  const minutes = Math.floor(secs / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  return `${hours}h ${minutes % 60}m`
}

function chordOf(event) {
  const parts = []
  if (event.metaKey || event.ctrlKey) parts.push("Meta")
  if (event.altKey) parts.push("Alt")
  if (event.shiftKey) parts.push("Shift")
  const key = event.key === " " ? "Space" : event.key.length === 1 ? event.key.toUpperCase() : event.key
  parts.push(key === "ArrowRight" ? "]" : key === "ArrowLeft" ? "[" : key)
  return parts.join("+")
}

function normalizeCombo(combo) {
  return String(combo || "")
    .replaceAll("Cmd", "Meta")
    .replaceAll("Ctrl", "Meta")
    .replaceAll("Control", "Meta")
    .split("+")
    .map((part) => part.trim())
    .filter(Boolean)
    .join("+")
}

export const Elapsed = {
  mounted() {
    this.start()
  },
  updated() {
    this.start()
  },
  destroyed() {
    clearInterval(this.timer)
  },
  start() {
    this.render()
    clearInterval(this.timer)
    this.timer = setInterval(() => this.render(), 1000)
  },
  render() {
    const until = this.el.dataset.until
    const started = this.el.dataset.startedAt
    const target = until ? Date.parse(until) : Date.parse(started || "")

    if (Number.isNaN(target)) {
      this.el.textContent = ""
      return
    }

    if (until) {
      const secs = Math.max(0, Math.floor((target - Date.now()) / 1000))
      this.el.textContent = secs === 0 ? "expired" : formatDuration(secs)
      return
    }

    const secs = Math.max(0, Math.floor((Date.now() - target) / 1000))
    this.el.textContent = formatDuration(secs)
  },
}

export const LoadOlder = {
  mounted() {
    this.busy = false
    this.stream = document.getElementById("activity-stream")
    this.onScroll = () => this.maybeLoad()
    this.stream?.addEventListener("scroll", this.onScroll, {passive: true})
  },
  updated() {
    this.busy = false
  },
  destroyed() {
    this.stream?.removeEventListener("scroll", this.onScroll)
  },
  maybeLoad() {
    if (this.busy || this.el.dataset.older !== "true" || !this.stream) return
    if (this.stream.scrollTop > 16) return
    this.busy = true
    this.pushEvent("load_older_activity", {})
  },
}

export const Composer = {
  mounted() {
    this.el.addEventListener("keydown", (event) => {
      const combo = normalizeCombo(this.el.dataset.sendShortcut || "Meta+Enter")
      if (chordOf(event) === combo) {
        event.preventDefault()
        this.el.requestSubmit()
      }
    })

    this.onPaste = (event) => {
      const files = Array.from(event.clipboardData?.files || [])
      if (files.length === 0) return
      event.preventDefault()
      this.upload("attachments", files)
    }

    this.onDragOver = (event) => {
      event.preventDefault()
      this.el.classList.add("is-dropping")
    }

    this.onDragLeave = () => this.el.classList.remove("is-dropping")

    this.onDrop = (event) => {
      event.preventDefault()
      this.el.classList.remove("is-dropping")
      const files = Array.from(event.dataTransfer?.files || [])
      if (files.length) this.upload("attachments", files)
    }

    this.el.addEventListener("paste", this.onPaste)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("dragleave", this.onDragLeave)
    this.el.addEventListener("drop", this.onDrop)
  },
  destroyed() {
    this.el.removeEventListener("paste", this.onPaste)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("dragleave", this.onDragLeave)
    this.el.removeEventListener("drop", this.onDrop)
  },
}

export const Shortcuts = {
  mounted() {
    this.handler = (event) => this.onKey(event)
    window.addEventListener("keydown", this.handler)
  },
  destroyed() {
    window.removeEventListener("keydown", this.handler)
  },
  onKey(event) {
    const map = JSON.parse(this.el.dataset.shortcuts || "{}")
    const chord = chordOf(event)
    const typing = event.target && /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName)

    for (const [action, combo] of Object.entries(map)) {
      if (normalizeCombo(combo) !== chord) continue
      if (action === "send") continue
      if (typing && !["interrupt", "focus_composer", "search"].includes(action) && !event.metaKey && !event.ctrlKey) {
        continue
      }
      event.preventDefault()
      if (action === "focus_composer") {
        document.querySelector("#prompt-composer textarea")?.focus()
        return
      }
      if (action === "search") {
        document.querySelector("#project-search input, #sidebar-search input")?.focus()
        return
      }
      this.pushEvent("shortcut", {action})
      return
    }
  },
}
