// Run: rtk node test/task_board_motion_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/js/app.js', 'utf8');
const motionListeners = new Set();
const media = {
  matches: false,
  addEventListener: (_, listener) => motionListeners.add(listener),
  removeEventListener: (_, listener) => motionListeners.delete(listener),
};
const document = {activeElement: null, visibilityState: 'visible'};
const context = {window: {matchMedia: () => media}, document};
vm.runInNewContext(source.slice(source.indexOf('const TaskBoard ='), source.indexOf('const CopyCommand =')) + '\nglobalThis.hook = TaskBoard;', context);
const animations = [];
let rect = {left: 0, top: 0};
const card = {
  id: 'task-one', dataset: {taskState: 'running'},
  getBoundingClientRect: () => rect,
  animate: (frames, options) => {
    const animation = {frames, options, cancelled: false, cancel() {this.cancelled = true;}};
    animations.push(animation);
    return animation;
  },
};
const board = Object.assign({}, context.hook, {el: {
  addEventListener() {},
  contains: element => element === card,
  querySelectorAll: () => [card],
}});
board.mounted();
board.beforeUpdate();
card.dataset.taskState = 'paused';
rect = {left: 200, top: 50};
board.updated();
assert.equal(animations.length, 1, 'A durable state move animates');
assert.equal(animations[0].frames[0].transform, 'translate(-200px, -50px)');
assert.equal(animations[0].options.duration, 200);
assert.equal(animations[0].options.easing, 'cubic-bezier(0.77, 0, 0.175, 1)');
media.matches = true;
motionListeners.forEach(listener => listener());
assert.equal(animations[0].cancelled, true, 'Preference changes cancel motion immediately');
board.beforeUpdate();
card.dataset.taskState = 'running';
rect = {left: 0, top: 0};
board.updated();
assert.equal(animations.length, 1, 'Reduced motion changes position instantly');
media.matches = false;
document.activeElement = card;
board.beforeUpdate();
card.dataset.taskState = 'waiting';
rect = {left: 400, top: 100};
board.updated();
assert.equal(animations.length, 1, 'Focused keyboard interaction stays instant');
document.activeElement = null;
board.beforeUpdate();
rect = {left: 410, top: 100};
board.updated();
assert.equal(animations.length, 1, 'Timer and ordinary layout updates do not animate');
board.destroyed();
assert.equal(motionListeners.size, 0);
console.log('Board motion: state move, reduced motion, focus, ordinary updates and cleanup passed');
