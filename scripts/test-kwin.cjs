const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const engine = vm.createContext({console});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Resources/kwin/reflex-wm/contents/code/windows.js'), 'utf8'), engine);
const rect = (x,y,width,height) => ({x,y,width,height});
const outputs = [{geometry: rect(0,0,1001,800)}, {geometry: rect(1001,0,2000,1200)}];
const desktop = {};
function win(id, pid = 1) {
  return {internalId: id, pid, normalWindow: true, resourceClass: 'terminal', desktopFileName: 'org.example.Terminal',
    caption: 'Shell', frameGeometry: rect(20,30,600,400), output: outputs[0], closeable: true,
    resizeable: true, moveable: true, moveableAcrossScreens: true, desktops: [desktop], activities: [],
    setMaximize() {}, closeWindow() {this.closed = true;}};
}
const a = win('a'), b = win('b'), c = win('c', 2), panel = {...win('panel'), specialWindow: true};
const workspace = {stackingOrder: [a,b,c,panel], activeWindow: a, screens: outputs,
  currentDesktop: desktop, currentActivity: 'default', MaximizeArea: 2,
  clientArea: (_, output) => output.geometry, raiseWindow() {}, sendClientToScreen(w, output) { w.output = output; }};
engine.initialize(workspace, rect, workspace.MaximizeArea);
engine.recordFocus(c); engine.recordFocus(a);
let snapshot = engine.execute({action: 'snapshot'});
assert.equal(snapshot.windows.length, 3);
assert.equal(snapshot.windows[0].id, 'a');
assert.equal(snapshot.windows[0].desktopEntryID, 'org.example.Terminal');
engine.execute({action: 'toggle', window: 'a'}); assert.equal(workspace.activeWindow, c);
engine.execute({action: 'toggle', window: 'a'}); assert.equal(workspace.activeWindow, a);
engine.execute({action: 'focus-next-app-window'}); assert.equal(workspace.activeWindow, b);
engine.execute({action: 'focus-next-app-window'}); assert.equal(workspace.activeWindow, a);
const original = {...a.frameGeometry};
engine.execute({action: 'toggle-maximize'}); assert.equal(a.frameGeometry.width, 1001);
engine.execute({action: 'toggle-maximize'}); assert.deepEqual(a.frameGeometry, original);
engine.execute({action: 'toggle-vertical-split'}); assert.equal(a.frameGeometry.width, 500);
engine.execute({action: 'toggle-vertical-split'}); assert.equal(a.frameGeometry.x, 500); assert.equal(a.frameGeometry.width, 501);
engine.execute({action: 'move-to-next-screen'}); assert.equal(a.output, outputs[1]);
assert.ok(a.frameGeometry.x >= 1001); assert.ok(a.frameGeometry.x + a.frameGeometry.width <= 3001);
b.minimized = true; engine.execute({action: 'focus', window: 'b'}); assert.equal(b.minimized, false);
engine.execute({action: 'close'}); assert.equal(b.closed, true);
engine.removeWindow(b); workspace.stackingOrder = [a,c,panel];
assert.throws(() => engine.execute({action: 'focus', window: 'b'}), /no longer exists/);
workspace.activeWindow = panel; assert.throws(() => engine.execute({action: 'close'}), /no focused/);
workspace.activeWindow = a; a.fullScreen = true;
assert.throws(() => engine.execute({action: 'toggle-vertical-split'}), /fullscreen/);
console.log('KWin action tests passed');
