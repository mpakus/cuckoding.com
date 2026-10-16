import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {Dialog} from "./dialog.mjs"
import {AgentLogin} from "./agent-login.mjs"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: {Dialog, AgentLogin}})
liveSocket.connect()
