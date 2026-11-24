import assert from "node:assert/strict"
import test from "node:test"
import {hitTestPixel, layoutPipeline} from "../assets/js/autopilot_flow.mjs"

test("layoutPipeline maps stages, active routing, and task pixels cleanly", () => {
  const payload = {
    status: "running",
    stages: [
      {id: "plan", label: "Plan", state: "done"},
      {id: "resolve", label: "Diagnose", state: "done"},
      {id: "implement", label: "Write", state: "current"},
      {id: "check", label: "Check", state: "waiting"},
      {id: "review", label: "Review", state: "waiting"},
      {id: "publish", label: "Integrate", state: "waiting"}
    ],
    items: [
      {task_id: 1, position: 0, title: "First", state: "done", stage: "publish", note: ""},
      {task_id: 2, position: 1, title: "Second", state: "current", stage: "implement", note: ""}
    ]
  }

  const layout = layoutPipeline(payload, 720, 200)
  assert.equal(layout.stageNodes.length, 6)
  assert.equal(layout.connectors.length, 5)
  assert.equal(layout.pixels.length, 2)
  assert.equal(layout.focus.taskId, 2)
  assert.ok(layout.route)
  assert.equal(layout.route.state, "current")

  const px = layout.pixels[1].x
  const py = layout.height - layout.pixels[1].y
  const hit = hitTestPixel(layout, px, py)
  assert.equal(hit?.taskId, 2)
  assert.equal(hitTestPixel(layout, 2, 2), null)
})

test("the default readout focuses the task needing attention ahead of an active peer", () => {
  const items = [
    {task_id: 4, state: "waiting", label: "Queued"},
    {task_id: 3, state: "ready", label: "Awaiting integration", stage: "publish"},
    {task_id: 1, state: "current", label: "Implementing", stage: "implement"},
    {task_id: 2, state: "failed", label: "Needs input", stage: "review"}
  ]
  const layout = layoutPipeline({items})
  assert.equal(layout.focus.taskId, 2)
  assert.equal(layout.focus.label, "Needs input")
  assert.equal(layout.pixels[1].label, "Awaiting integration")
  assert.equal(layoutPipeline({items: items.slice(0, 3)}).focus.taskId, 1)
  assert.equal(layoutPipeline({items: items.slice(0, 2)}).focus.taskId, 3)
})
