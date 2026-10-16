// Native dialog owns focus trapping and Escape; closing preserves LiveView form state.
export const Dialog = {
  mounted() {
    this.open = () => {
      if (this.el.open) return
      this.returnFocus = document.activeElement
      if (this.returnFocus === document.body) {
        this.returnFocus = document.querySelector(`[aria-controls="${this.el.id}"]`) || this.returnFocus
      }
      // A deep link can open a dialog inside the initially collapsed Advanced section.
      for (let parent = this.el.parentElement; parent; parent = parent.parentElement) {
        if (parent.tagName === "DETAILS") parent.open = true
      }
      this.el.showModal()
      this.el.querySelector("[data-dialog-title]").focus()
    }
    this.close = () => this.el.close()
    this.restoreFocus = () => {
      if (this.returnFocus?.isConnected) this.returnFocus.focus()
    }
    this.el.addEventListener("cc:open", this.open)
    this.el.addEventListener("cc:close", this.close)
    this.el.addEventListener("close", this.restoreFocus)
    this.handleEvent("dialog-close", ({id}) => { if (id === this.el.id) this.close() })
    this.openFromHash = () => { if (window.location.hash === `#${this.el.id}`) this.open() }
    window.addEventListener("hashchange", this.openFromHash)
    this.openFromHash()
  },
  destroyed() {
    this.el.removeEventListener("cc:open", this.open)
    this.el.removeEventListener("cc:close", this.close)
    this.el.removeEventListener("close", this.restoreFocus)
    window.removeEventListener("hashchange", this.openFromHash)
  }
}
