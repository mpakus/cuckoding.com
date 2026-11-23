// Synchronizes desktop app motion with the OS reduced-motion preference and pointer/keyboard input.
export function installMotion(document, window) {
  const root = document?.documentElement
  if (!root || typeof window?.matchMedia !== "function") return () => {}

  const media = window.matchMedia("(prefers-reduced-motion: reduce)")
  const apply = () => {
    root.dataset.motion = media.matches ? "off" : "on"
  }
  const pointer = () => { root.dataset.input = "pointer" }
  const keyboard = event => {
    if (!event.metaKey && !event.ctrlKey && !event.altKey) root.dataset.input = "keyboard"
  }

  root.dataset.input = "keyboard"
  media.addEventListener("change", apply)
  document.addEventListener("pointerdown", pointer, {capture: true})
  document.addEventListener("keydown", keyboard, {capture: true})
  apply()

  return () => {
    media.removeEventListener("change", apply)
    document.removeEventListener("pointerdown", pointer, {capture: true})
    document.removeEventListener("keydown", keyboard, {capture: true})
    root.dataset.motion = "off"
  }
}
