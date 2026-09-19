const assert = require("node:assert/strict")
const {readFileSync} = require("node:fs")
const {runInNewContext} = require("node:vm")

const source = readFileSync("assets/js/app.js", "utf8")
const definition = source.match(/const LogTail = (\{[\s\S]*?\n\})/)[1]
const hook = runInNewContext(`(${definition})`)
hook.el = {scrollTop: 0, scrollHeight: 1000, clientHeight: 200, dataset: {processId: "one"}}
hook.mounted()
assert.equal(hook.el.scrollTop, 1000)
hook.el.scrollTop = 800
hook.beforeUpdate()
hook.el.scrollHeight = 1200
hook.updated()
assert.equal(hook.el.scrollTop, 1200, "follow appended output when near the bottom")
hook.el.scrollTop = 100
hook.beforeUpdate()
hook.el.scrollHeight = 1400
hook.updated()
assert.equal(hook.el.scrollTop, 100, "keep the reading position when scrolled up")
hook.beforeUpdate()
hook.el.dataset.processId = "two"
hook.updated()
assert.equal(hook.el.scrollTop, 1400, "follow the tail when selecting another log")
console.log("LogTail scroll checks passed")
