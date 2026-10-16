import {test} from "node:test"
import assert from "node:assert/strict"
import {Dialog} from "../assets/js/dialog.mjs"

test("dialog opens without resetting forms, restores focus, closes on server completion and removes listeners", () => {
  const callbacks = new Map()
  const events = new Map()
  const windowEvents = new Map()
  let opens = 0, headingFocus = 0, restored = 0
  const trigger = {isConnected: true, focus: () => restored++}
  globalThis.document = {activeElement: trigger}
  globalThis.window = {
    location: {hash: ""},
    addEventListener: (name, fn) => windowEvents.set(name, fn),
    removeEventListener: (name, fn) => { assert.equal(windowEvents.get(name), fn); windowEvents.delete(name) }
  }
  const disclosure = {tagName: "DETAILS", open: false}
  const el = {
    id: "draft-editor", open: false, value: "Retain typed text",
    parentElement: disclosure,
    addEventListener: (name, fn) => callbacks.set(name, fn),
    removeEventListener: (name, fn) => { assert.equal(callbacks.get(name), fn); callbacks.delete(name) },
    showModal() { this.open = true; opens++ },
    close() { this.open = false; callbacks.get("close")() },
    querySelector: () => ({focus: () => headingFocus++})
  }
  const hook = {el, handleEvent: (name, fn) => events.set(name, fn)}
  Dialog.mounted.call(hook)
  callbacks.get("cc:open")()
  callbacks.get("cc:open")()
  assert.equal(opens, 1)
  assert.equal(headingFocus, 1)
  events.get("dialog-close")({id: "other-dialog"})
  assert.equal(el.open, true)
  events.get("dialog-close")({id: el.id})
  assert.equal(el.open, false)
  assert.equal(restored, 1)
  callbacks.get("cc:open")()
  assert.equal(el.value, "Retain typed text")
  callbacks.get("cc:close")()
  assert.equal(restored, 2)
  disclosure.open = false
  window.location.hash = "#draft-editor"
  windowEvents.get("hashchange")()
  assert.equal(el.open, true)
  assert.equal(disclosure.open, true)
  callbacks.get("cc:close")()
  const body = {isConnected: true, focus: () => assert.fail("deep-link close should focus its opener")}
  document.body = body
  document.activeElement = body
  document.querySelector = selector => {
    assert.equal(selector, '[aria-controls="draft-editor"]')
    return trigger
  }
  windowEvents.get("hashchange")()
  const beforeClose = restored
  callbacks.get("cc:close")()
  assert.equal(restored, beforeClose + 1)
  Dialog.destroyed.call(hook)
  assert.equal(callbacks.size, 0)
  assert.equal(windowEvents.size, 0)
  delete globalThis.document
  delete globalThis.window
})
