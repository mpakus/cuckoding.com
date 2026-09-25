import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Modal = {
  mounted() {
    this.cancel = event => {
      event.preventDefault()
      this.pushEvent(this.el.dataset.cancel, {})
    }
    this.el.addEventListener("cancel", this.cancel)
    this.el.showModal()
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.cancel)
    this.el.close()
    document.getElementById(this.el.dataset.returnFocus)?.focus()
  },
}

const TaskBoard = {
  mounted() {
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.animations = new Map()
    this.cancelMotion = () => {
      this.animations.forEach(animation => animation.cancel())
      this.animations.clear()
    }
    this.motion.addEventListener("change", this.cancelMotion)
    this.el.addEventListener("dragstart", event => {
      const card = event.target.closest("[data-task-id]")
      if (!card || card.dataset.allowedTargets === "") return event.preventDefault()

      this.draggedTaskId = card.dataset.taskId
      event.dataTransfer.setData("text/plain", card.dataset.taskId)
      event.dataTransfer.effectAllowed = "move"
    })

    this.el.addEventListener("dragend", () => { this.draggedTaskId = null })

    this.el.addEventListener("dragover", event => {
      const column = event.target.closest("[data-drop-state]")
      const card = document.getElementById(`task-${this.draggedTaskId}`)

      if (column && card && this.allowed(card, column.dataset.dropState)) {
        event.preventDefault()
        event.dataTransfer.dropEffect = "move"
      }
    })

    this.el.addEventListener("drop", event => {
      const column = event.target.closest("[data-drop-state]")
      const taskId = event.dataTransfer.getData("text/plain") || this.draggedTaskId
      const card = document.getElementById(`task-${taskId}`)

      if (!column || !card || !this.allowed(card, column.dataset.dropState)) return

      event.preventDefault()
      card.setAttribute("aria-busy", "true")
      column.querySelector("[data-task-list]").prepend(card)
      this.pushEvent("transition-task", {id: taskId, to: column.dataset.dropState})
      this.draggedTaskId = null
    })
  },

  beforeUpdate() {
    this.positions = new Map()
    // Keep keyboard interactions and changes while reading a focused card instant.
    if (!this.motion.matches && !this.el.contains(document.activeElement)) {
      this.el.querySelectorAll("[data-task-id]").forEach(card => {
        this.positions.set(card.id, {rect: card.getBoundingClientRect(), state: card.dataset.taskState})
      })
    }
    this.cancelMotion()
  },

  updated() {
    if (this.motion.matches || document.visibilityState !== "visible") return
    this.el.querySelectorAll("[data-task-id]").forEach(card => {
      const before = this.positions?.get(card.id)
      if (!before || before.state === card.dataset.taskState || typeof card.animate !== "function") return
      const after = card.getBoundingClientRect()
      const x = before.rect.left - after.left
      const y = before.rect.top - after.top
      if (Math.abs(x) < 1 && Math.abs(y) < 1) return
      const animation = card.animate([
        {transform: `translate(${x}px, ${y}px)`},
        {transform: "translate(0, 0)"},
      ], {duration: 200, easing: "cubic-bezier(0.77, 0, 0.175, 1)"})
      this.animations.set(card.id, animation)
      animation.onfinish = () => {
        if (this.animations.get(card.id) === animation) this.animations.delete(card.id)
      }
    })
  },

  destroyed() {
    this.cancelMotion()
    this.motion.removeEventListener("change", this.cancelMotion)
  },

  allowed(card, state) {
    return card.dataset.allowedTargets.split(",").includes(state)
  },
}

const CopyCommand = {
  mounted() {
    this.input = this.el.querySelector("[data-copy-source]")
    this.button = this.el.querySelector("[data-copy-button]")
    this.status = this.el.querySelector("[data-copy-status]")
    this.copy = async () => {
      try {
        await navigator.clipboard.writeText(this.input.value)
        this.button.textContent = "Copied"
        this.status.textContent = "Command copied to clipboard."
        clearTimeout(this.resetTimer)
        this.resetTimer = setTimeout(() => { this.button.textContent = "Copy" }, 2000)
      } catch (_error) {
        this.input.focus()
        this.input.select()
        this.status.textContent = "Copy failed. The command is selected; copy it manually."
      }
    }
    this.button.addEventListener("click", this.copy)
  },

  destroyed() {
    clearTimeout(this.resetTimer)
    this.button.removeEventListener("click", this.copy)
  },
}

const LogTail = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight
  },
  beforeUpdate() {
    this.follow = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 24
    this.processId = this.el.dataset.processId
  },
  updated() {
    if (this.follow || this.processId !== this.el.dataset.processId) {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
}

const ActivityHistory = {
  mounted() {
    this.handleEvent("activity:latest", () => { this.el.scrollTop = 0 })
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {CopyCommand, TaskBoard, LogTail, Modal, ActivityHistory},
})

liveSocket.connect()
window.liveSocket = liveSocket
