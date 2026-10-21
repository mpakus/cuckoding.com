export const ActivityFollow = {
  mounted() { this.updated() },
  updated() {
    if (this.el.dataset.follow === "true") this.el.scrollTop = this.el.scrollHeight
  }
}
