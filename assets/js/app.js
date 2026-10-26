import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const TaskDrawer = {
  mounted() {
    this.opener = document.activeElement
    this.cancel = event => {
      event.preventDefault()
      this.el.querySelector("[data-drawer-close]").click()
    }
    this.el.addEventListener("cancel", this.cancel)
    this.el.showModal()
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.cancel)
    this.el.close()
    const target = document.getElementById(this.el.dataset.returnFocus) ||
      (this.opener?.isConnected && this.opener !== document.body ? this.opener : null) ||
      document.getElementById("task-board-heading")
    target?.focus()
  }
}
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {TaskDrawer}
})
liveSocket.connect()
