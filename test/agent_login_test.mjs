import {test} from "node:test"
import assert from "node:assert/strict"
import {AgentLogin} from "../assets/js/agent-login.mjs"

const key = "73e53017-5d58-4c6f-ab14-733f9f22cedc"

function fixture(blocked = false) {
  const listeners = new Map(), events = new Map(), navigations = []
  let opened = 0, closed = 0
  const popup = {
    closed: false, opener: {}, document: {body: {}},
    location: {replace: path => navigations.push(path)},
    close() { this.closed = true; closed++ }
  }
  globalThis.window = {open: (url, target) => {
    assert.equal(url, "about:blank")
    assert.equal(target, "_blank")
    opened++
    return blocked ? null : popup
  }}
  const el = {
    dataset: {}, querySelector: () => ({value: key}),
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name)
  }
  const hook = {el, handleEvent: (name, fn) => events.set(name, fn)}
  AgentLogin.mounted.call(hook)
  const ready = () => Object.assign(el.dataset, {
    commandId: key, loginReady: "true", loginRoute: `/codex/login/${key}`
  })
  return {hook, el, listeners, events, popup, ready, navigations, counts: () => [opened, closed]}
}

test("one user submit opens a tab, then hands it to only the exact protected redirect once", () => {
  const f = fixture()
  f.listeners.get("submit")()
  assert.equal(f.popup.opener, null)
  assert.match(f.popup.document.body.textContent, /Preparing sign-in/)
  f.el.dataset.commandId = key
  AgentLogin.updated.call(f.hook)
  assert.deepEqual(f.navigations, [])
  f.ready()
  AgentLogin.updated.call(f.hook)
  AgentLogin.updated.call(f.hook)
  AgentLogin.destroyed.call(f.hook)
  assert.deepEqual(f.navigations, [`/codex/login/${key}`])
  assert.deepEqual(f.counts(), [1, 0])
  assert.equal(f.listeners.size, 0)
})

test("foreign commands and routes cannot navigate; rejection and cancellation close only the pending tab", () => {
  const f = fixture()
  f.listeners.get("submit")()
  f.ready()
  f.el.dataset.loginRoute = "https://foreign.invalid/"
  AgentLogin.updated.call(f.hook)
  f.ready()
  f.el.dataset.commandId = "foreign-command"
  AgentLogin.updated.call(f.hook)
  assert.deepEqual(f.navigations, [])
  f.events.get("login-submitted")({key: "other", accepted: false})
  assert.equal(f.popup.closed, false)
  f.events.get("login-submitted")({key, accepted: false})
  assert.equal(f.popup.closed, true)
  AgentLogin.destroyed.call(f.hook)
  assert.deepEqual(f.counts(), [1, 1])

  const cancelled = fixture()
  cancelled.listeners.get("submit")()
  AgentLogin.updated.call(cancelled.hook)
  assert.equal(cancelled.popup.closed, true)
  AgentLogin.destroyed.call(cancelled.hook)
})

test("blocked tabs, reconnect and browser-closed tabs never reopen or replay login", () => {
  const f = fixture(true)
  f.ready()
  AgentLogin.updated.call(f.hook)
  assert.deepEqual(f.counts(), [0, 0])
  f.listeners.get("submit")()
  AgentLogin.updated.call(f.hook)
  assert.deepEqual(f.navigations, [])
  AgentLogin.destroyed.call(f.hook)

  const closed = fixture()
  closed.listeners.get("submit")()
  closed.popup.closed = true
  closed.ready()
  AgentLogin.updated.call(closed.hook)
  assert.deepEqual(closed.navigations, [])
  assert.deepEqual(closed.counts(), [1, 0])
  AgentLogin.destroyed.call(closed.hook)
  delete globalThis.window
})
