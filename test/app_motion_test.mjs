import assert from "node:assert/strict"
import test from "node:test"
import {installMotion} from "../assets/js/motion.mjs"

class Element extends EventTarget {
  constructor(id) {
    super()
    this.id = id
    this.hidden = true
    this.disabled = true
    this.checked = false
    this.attributes = new Map()
  }
  setAttribute(name, value) { this.attributes.set(name, value) }
  removeAttribute(name) { this.attributes.delete(name) }
}

function fixture({saved = null, reduced = false, storageUnavailable = false} = {}) {
  const toggle = new Element("app-motion-toggle")
  const control = new Element("app-motion-control")
  const note = new Element("app-motion-system")
  const elements = new Map([toggle, control, note].map(element => [element.id, element]))
  const document = new EventTarget()
  document.documentElement = {dataset: {motion: "off", input: "keyboard"}}
  document.getElementById = id => elements.get(id)
  const media = new EventTarget()
  media.matches = reduced
  const writes = []
  const window = new EventTarget()
  window.matchMedia = query => {
    assert.equal(query, "(prefers-reduced-motion: reduce)")
    return media
  }
  Object.defineProperty(window, "localStorage", {get() {
    if (storageUnavailable) throw new Error("Storage is disabled")
    return {
      getItem: key => key === "boss.motion" ? saved : null,
      setItem: (key, value) => { writes.push([key, value]); saved = value },
    }
  }})
  const destroy = installMotion(document, window)
  const dispatch = (target, type, fields = {}) => target.dispatchEvent(Object.assign(new Event(type), fields))
  return {
    toggle, control, note, media, document, window, writes, destroy,
    state: document.documentElement.dataset,
    choosePause(value) { toggle.checked = value; dispatch(toggle, "change") },
    systemReduce(value) { media.matches = value; dispatch(media, "change") },
    dispatch,
  }
}

test("the visible pause control restores and persists the user's choice", () => {
  const ui = fixture({saved: "paused"})
  assert.equal(ui.state.motion, "off")
  assert.equal(ui.toggle.checked, true)
  assert.equal(ui.control.hidden, false)
  assert.equal(ui.toggle.disabled, false)

  ui.choosePause(false)
  assert.equal(ui.state.motion, "on")
  ui.choosePause(true)
  assert.equal(ui.state.motion, "off")
  assert.deepEqual(ui.writes, [["boss.motion", "auto"], ["boss.motion", "paused"]])
  ui.destroy()
})

test("live system changes override motion without rewriting the saved choice", () => {
  const ui = fixture()
  assert.equal(ui.state.motion, "on")
  ui.systemReduce(true)
  assert.equal(ui.state.motion, "off")
  assert.equal(ui.toggle.checked, true)
  assert.equal(ui.toggle.disabled, true)
  assert.equal(ui.note.hidden, false)
  assert.equal(ui.toggle.attributes.get("aria-describedby"), ui.note.id)
  ui.choosePause(false)
  assert.equal(ui.state.motion, "off")
  ui.systemReduce(false)
  assert.equal(ui.state.motion, "on")
  assert.equal(ui.toggle.disabled, false)
  assert.equal(ui.note.hidden, true)
  assert.equal(ui.toggle.attributes.has("aria-describedby"), false)
  assert.deepEqual(ui.writes, [])

  ui.choosePause(true)
  ui.systemReduce(true)
  ui.systemReduce(false)
  assert.equal(ui.state.motion, "off")
  ui.destroy()
})

test("the control still works when browser storage is unavailable", () => {
  const ui = fixture({storageUnavailable: true})
  ui.choosePause(true)
  assert.equal(ui.state.motion, "off")
  ui.choosePause(false)
  assert.equal(ui.state.motion, "on")
  ui.destroy()
})

test("pointer motion is disabled again before keyboard navigation", () => {
  const ui = fixture()
  assert.equal(ui.state.input, "keyboard")
  ui.dispatch(ui.document, "pointerdown")
  assert.equal(ui.state.input, "pointer")
  ui.dispatch(ui.document, "keydown", {key: "Tab"})
  assert.equal(ui.state.input, "keyboard")
  ui.dispatch(ui.document, "pointerdown")
  ui.dispatch(ui.document, "keydown", {key: "Enter"})
  assert.equal(ui.state.input, "keyboard")
  ui.destroy()
})

test("preference changes in another tab apply, and teardown removes listeners", () => {
  const ui = fixture()
  ui.dispatch(ui.window, "storage", {key: "unrelated", newValue: "paused"})
  assert.equal(ui.state.motion, "on")
  ui.dispatch(ui.window, "storage", {key: "boss.motion", newValue: "paused"})
  assert.equal(ui.state.motion, "off")
  ui.dispatch(ui.window, "storage", {key: "boss.motion", newValue: "auto"})
  assert.equal(ui.state.motion, "on")
  assert.deepEqual(ui.writes, [])
  ui.destroy()
  assert.equal(ui.control.hidden, true)
  assert.equal(ui.toggle.disabled, true)
  assert.equal(ui.state.motion, "off")
  ui.dispatch(ui.window, "storage", {key: "boss.motion", newValue: "auto"})
  ui.dispatch(ui.document, "pointerdown")
  assert.equal(ui.state.motion, "off")
  assert.equal(ui.state.input, "keyboard")
})
