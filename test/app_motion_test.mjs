import assert from "node:assert/strict"
import test from "node:test"
import {installMotion} from "../assets/js/motion.mjs"

function fixture({reduced = false} = {}) {
  const document = new EventTarget()
  document.documentElement = {dataset: {motion: "off", input: "keyboard"}}
  const media = new EventTarget()
  media.matches = reduced
  const window = new EventTarget()
  window.matchMedia = query => {
    assert.equal(query, "(prefers-reduced-motion: reduce)")
    return media
  }
  const destroy = installMotion(document, window)
  const dispatch = (target, type, fields = {}) =>
    target.dispatchEvent(Object.assign(new Event(type), fields))
  return {
    media,
    document,
    window,
    destroy,
    state: document.documentElement.dataset,
    systemReduce(value) {
      media.matches = value
      dispatch(media, "change")
    },
    dispatch,
  }
}

test("motion follows the live OS reduced-motion preference without a footer toggle", () => {
  const ui = fixture()
  assert.equal(ui.state.motion, "on")
  ui.systemReduce(true)
  assert.equal(ui.state.motion, "off")
  ui.systemReduce(false)
  assert.equal(ui.state.motion, "on")
  ui.destroy()
})

test("initial OS reduced motion keeps motion disabled", () => {
  const ui = fixture({reduced: true})
  assert.equal(ui.state.motion, "off")
  ui.systemReduce(false)
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

test("teardown resets motion and removes listeners", () => {
  const ui = fixture()
  assert.equal(ui.state.motion, "on")
  ui.destroy()
  assert.equal(ui.state.motion, "off")
  ui.systemReduce(false)
  ui.dispatch(ui.document, "pointerdown")
  assert.equal(ui.state.motion, "off")
  assert.equal(ui.state.input, "keyboard")
})
