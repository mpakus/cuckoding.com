import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const TaskBoard = {
  mounted() {
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

  allowed(card, state) {
    return card.dataset.allowedTargets.split(",").includes(state)
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {TaskBoard},
})

liveSocket.connect()
window.liveSocket = liveSocket
