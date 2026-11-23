import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {installMotion} from "./motion.mjs"
import {AutopilotFlowCanvas} from "./autopilot_flow.mjs"

installMotion(document, window)
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
  updated() {
    const select = this.el.querySelector("#task-revision")
    if (select && select.value !== this.el.dataset.revision) {
      select.value = this.el.dataset.revision
    }
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
const TaskBoardMotion = {
  mounted() {
    this.positions = new Map()
    this.capture()
  },
  beforeUpdate() {
    this.capture()
  },
  updated() {
    if (document.documentElement.dataset.motion === "off" ||
        window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
      this.capture()
      return
    }
    const prev = this.positions || new Map()
    const next = new Map()
    this.el.querySelectorAll("[data-task-card]").forEach(item => {
      const id = item.dataset.taskCard
      const col = item.dataset.taskColumn
      const rect = item.getBoundingClientRect()
      next.set(id, {rect, col, state: item.dataset.taskState})
      const old = prev.get(id)
      if (!old) return
      const dx = old.rect.left - rect.left
      const dy = old.rect.top - rect.top
      if (Math.abs(dx) > 4 || Math.abs(dy) > 4 || old.col !== col) {
        item.animate(
          [
            {transform: `translate(${dx}px, ${dy}px)`, opacity: 0.88},
            {transform: "translate(0, 0)", opacity: 1}
          ],
          {duration: 320, easing: "cubic-bezier(0.22, 1, 0.36, 1)"}
        )
      }
    })
    this.positions = next
  },
  capture() {
    const map = new Map()
    this.el.querySelectorAll("[data-task-card]").forEach(item => {
      map.set(item.dataset.taskCard, {
        rect: item.getBoundingClientRect(),
        col: item.dataset.taskColumn,
        state: item.dataset.taskState
      })
    })
    this.positions = map
  }
}

const DialogModal = {
  mounted() {
    this.opener = document.activeElement
    this.cancel = event => {
      event.preventDefault()
      this.el.querySelector("[data-modal-close]")?.click()
    }
    this.keydown = event => {
      if (event.key === "Escape") {
        event.preventDefault()
        this.el.querySelector("[data-modal-close]")?.click()
      }
    }
    this.backdropClick = event => {
      if (event.target === this.el && event.detail > 0) {
        this.el.querySelector("[data-modal-close]")?.click()
      }
    }
    this.el.addEventListener("cancel", this.cancel)
    this.el.addEventListener("keydown", this.keydown)
    this.el.addEventListener("click", this.backdropClick)
    if (!this.el.open) {
      this.el.showModal()
    }
  },
  updated() {
    if (!this.el.open) {
      this.el.showModal()
    }
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.cancel)
    this.el.removeEventListener("keydown", this.keydown)
    this.el.removeEventListener("click", this.backdropClick)
    if (this.el.open) {
      this.el.close()
    }
    const target = document.getElementById(this.el.dataset.returnFocus) ||
      (this.opener?.isConnected && this.opener !== document.body ? this.opener : null) ||
      document.getElementById("task-board-heading")
    target?.focus()
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {TaskDrawer, DialogModal, AutopilotFlowCanvas, TaskBoardMotion}
})
liveSocket.connect()
