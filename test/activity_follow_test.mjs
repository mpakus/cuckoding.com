import test from "node:test"
import assert from "node:assert/strict"
import {ActivityFollow} from "../assets/js/activity-follow.mjs"

test("following shows the newest entries while reading mode preserves position across updates", () => {
  const hook = {...ActivityFollow, el: {dataset: {follow: "true"}, scrollTop: 0, scrollHeight: 1200}}
  hook.mounted()
  assert.equal(hook.el.scrollTop, 1200)
  hook.el.dataset.follow = "false"
  hook.el.scrollTop = 240
  hook.el.scrollHeight = 1600
  hook.updated()
  assert.equal(hook.el.scrollTop, 240)
  hook.el.dataset.follow = "true"
  hook.updated()
  assert.equal(hook.el.scrollTop, 1600)
})
