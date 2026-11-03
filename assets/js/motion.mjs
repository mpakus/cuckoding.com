const preferenceKey = "boss.motion"

// This preference belongs to the document, not a LiveView or a task run.
export function installMotion(document, window) {
  const toggle = document.getElementById("app-motion-toggle")
  const control = document.getElementById("app-motion-control")
  const systemNote = document.getElementById("app-motion-system")
  if (!toggle || !control || !systemNote) return () => {}

  const root = document.documentElement
  const media = window.matchMedia("(prefers-reduced-motion: reduce)")
  let storage
  let paused = false
  try {
    storage = window.localStorage
    paused = storage.getItem(preferenceKey) === "paused"
  } catch {
    // Restricted storage must not disable the in-memory preference or LiveView.
  }

  const apply = () => {
    const reduced = paused || media.matches
    root.dataset.motion = reduced ? "off" : "on"
    toggle.checked = reduced
    toggle.disabled = media.matches
    systemNote.hidden = !media.matches
    if (media.matches) toggle.setAttribute("aria-describedby", systemNote.id)
    else toggle.removeAttribute("aria-describedby")
  }
  const change = () => {
    if (media.matches) return apply()
    paused = toggle.checked
    try { storage?.setItem(preferenceKey, paused ? "paused" : "auto") } catch {}
    apply()
  }
  const storageChanged = event => {
    if (event.key !== preferenceKey) return
    paused = event.newValue === "paused"
    apply()
  }
  const pointer = () => { root.dataset.input = "pointer" }
  const keyboard = event => {
    if (!event.metaKey && !event.ctrlKey && !event.altKey) root.dataset.input = "keyboard"
  }

  root.dataset.input = "keyboard"
  toggle.addEventListener("change", change)
  media.addEventListener("change", apply)
  window.addEventListener("storage", storageChanged)
  document.addEventListener("pointerdown", pointer, {capture: true})
  document.addEventListener("keydown", keyboard, {capture: true})
  apply()
  control.hidden = false

  return () => {
    toggle.removeEventListener("change", change)
    media.removeEventListener("change", apply)
    window.removeEventListener("storage", storageChanged)
    document.removeEventListener("pointerdown", pointer, {capture: true})
    document.removeEventListener("keydown", keyboard, {capture: true})
    root.dataset.motion = "off"
    toggle.disabled = true
    control.hidden = true
    systemNote.hidden = true
  }
}
