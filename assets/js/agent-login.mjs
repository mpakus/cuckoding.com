export const AgentLogin = {
  mounted() {
    this.openLogin = () => {
      this.closePending()
      this.request = this.el.querySelector('[name="consent_key"]').value
      this.popup = window.open("about:blank", "_blank")
      if (this.popup) {
        this.popup.opener = null
        this.popup.document.title = "Cuckoding · Connecting"
        this.popup.document.body.textContent = "Preparing sign-in… Keep the Cuckoding tab open."
      }
    }
    this.closePending = () => {
      if (this.popup && !this.popup.closed) this.popup.close()
      this.popup = null
    }
    this.el.addEventListener("submit", this.openLogin)
    this.handleEvent("login-submitted", ({key, accepted}) => {
      if (key === this.request && !accepted) this.closePending()
    })
  },
  updated() {
    const {commandId, loginReady, loginRoute} = this.el.dataset
    if (commandId === this.request && loginReady === "true" &&
        /^[0-9a-f-]{36}$/.test(this.request) && loginRoute === `/codex/login/${this.request}`) {
      if (this.popup && !this.popup.closed) this.popup.location.replace(loginRoute)
      this.popup = null
    } else if (this.popup && !commandId) {
      this.closePending()
    }
  },
  destroyed() {
    this.closePending()
    this.el.removeEventListener("submit", this.openLogin)
  }
}
