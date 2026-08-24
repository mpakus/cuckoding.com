export function isTauri() {
  return typeof window !== "undefined" && (window.__TAURI__ != null || window.__TAURI_INTERNALS__ != null)
}

function tauriInvoke() {
  const api = window.__TAURI__
  const internals = window.__TAURI_INTERNALS__
  return api?.core?.invoke || api?.invoke || internals?.invoke || null
}

export async function openNativeDialog(options = {}) {
  const api = window.__TAURI__

  if (api?.dialog && typeof api.dialog.open === "function") {
    return api.dialog.open(options)
  }

  const invoke = tauriInvoke()
  if (typeof invoke === "function") {
    return invoke("plugin:dialog|open", { options })
  }

  throw new Error("Native folder picker is unavailable")
}

export const RepoPicker = {
  mounted() {
    this._onClick = (event) => this.pick(event)
    this.el.addEventListener("click", this._onClick, true)
  },

  destroyed() {
    if (this._onClick) this.el.removeEventListener("click", this._onClick, true)
  },

  async pick(event) {
    if (typeof tauriInvoke() !== "function" && !(window.__TAURI__?.dialog && typeof window.__TAURI__.dialog.open === "function")) {
      return
    }

    event.preventDefault()
    event.stopImmediatePropagation()

    try {
      const selected = await openNativeDialog({
        title: "Choose a Git repository",
        directory: true,
        multiple: false,
      })

      if (selected == null || selected === false) return

      const path = Array.isArray(selected) ? selected[0] : selected
      if (typeof path === "string" && path !== "") {
        this.pushEvent("open_project", { path })
      }
    } catch (error) {
      this.pushEvent("picker_failed", { error: error.message || String(error) })
    }
  },
}
