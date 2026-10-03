const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const engine = vm.createContext({console});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Resources/kwin/windows.js'), 'utf8'), engine);
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
  clientArea: (_, output) => output.geometry, raiseWindow() {}, sendClientToScreen(w, output) { w.output = output; },
  maximizeCalls: 0, slotWindowMaximize() { this.maximizeCalls++; this.activeWindow.nativeMaximized = !this.activeWindow.nativeMaximized; }};
const deferred = [];
const flushDeferred = () => { while (deferred.length) deferred.shift()(); };
engine.initialize(workspace, rect, workspace.MaximizeArea, callback => deferred.push(callback));
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
engine.execute({action: 'toggle-maximize'}); assert.equal(a.nativeMaximized, true);
engine.execute({action: 'toggle-maximize'}); assert.equal(a.nativeMaximized, false);
assert.equal(workspace.maximizeCalls, 2); assert.deepEqual(a.frameGeometry, original);
// Honor a maximized state set outside reflex-wm, without rewriting the frame.
a.nativeMaximized = true;
engine.execute({action: 'toggle-maximize'}); assert.equal(a.nativeMaximized, false);
assert.deepEqual(a.frameGeometry, original);
engine.execute({action: 'toggle-vertical-split'}); assert.equal(a.frameGeometry.width, 500);
engine.execute({action: 'toggle-vertical-split'}); assert.equal(a.frameGeometry.x, 500); assert.equal(a.frameGeometry.width, 501);
engine.execute({action: 'move-to-next-screen'}); assert.equal(a.output, outputs[1]);
assert.ok(a.frameGeometry.x >= 1001); assert.ok(a.frameGeometry.x + a.frameGeometry.width <= 3001);
assert.equal(a.frameGeometry.width, 501 / 1001 * 2000);
assert.equal(a.frameGeometry.height, 1200);
// Simulate the output transition retaining the smaller screen's size.
a.frameGeometry = rect(a.frameGeometry.x, a.frameGeometry.y, 501, 800);
flushDeferred();
assert.equal(a.frameGeometry.width, 501 / 1001 * 2000);
assert.equal(a.frameGeometry.height, 1200);
engine.execute({action: 'move-to-next-screen'}); flushDeferred();
assert.equal(a.output, outputs[0]);
assert.ok(Math.abs(a.frameGeometry.x - 500) < 1e-9);
assert.ok(Math.abs(a.frameGeometry.width - 501) < 1e-9);
assert.equal(a.frameGeometry.y, 0); assert.equal(a.frameGeometry.height, 800);
// A newer split must win over the pending proportional resize.
engine.execute({action: 'move-to-next-screen'});
engine.execute({action: 'toggle-vertical-split'});
const newerFrame = {...a.frameGeometry};
flushDeferred(); assert.deepEqual(a.frameGeometry, newerFrame);
// Native maximization cancels a pending screen resize as well.
engine.execute({action: 'move-to-next-screen'});
engine.execute({action: 'toggle-maximize'});
a.frameGeometry = rect(0, 0, 1001, 800);
flushDeferred(); assert.deepEqual(a.frameGeometry, rect(0, 0, 1001, 800));
assert.equal(a.nativeMaximized, true);
engine.execute({action: 'toggle-maximize'});
// A rapid second move supersedes the first deferred resize.
engine.execute({action: 'move-to-next-screen'});
engine.execute({action: 'move-to-next-screen'});
const latestMove = {...a.frameGeometry};
deferred.shift()(); assert.deepEqual(a.frameGeometry, latestMove);
flushDeferred(); assert.deepEqual(a.frameGeometry, latestMove);
// Do not resize after an external screen move or window removal.
engine.execute({action: 'move-to-next-screen'});
a.output = outputs.find(output => output !== a.output);
a.frameGeometry = rect(1200, 40, 700, 500);
const externalFrame = {...a.frameGeometry};
flushDeferred(); assert.deepEqual(a.frameGeometry, externalFrame);
engine.execute({action: 'move-to-next-screen'});
a.frameGeometry = rect(25, 40, 600, 400);
const removedFrame = {...a.frameGeometry};
engine.removeWindow(a);
flushDeferred(); assert.deepEqual(a.frameGeometry, removedFrame);
b.minimized = true; engine.execute({action: 'focus', window: 'b'}); assert.equal(b.minimized, false);
engine.execute({action: 'close'}); assert.equal(b.closed, true);
engine.removeWindow(b); workspace.stackingOrder = [a,c,panel];
assert.throws(() => engine.execute({action: 'focus', window: 'b'}), /no longer exists/);
workspace.activeWindow = panel; assert.throws(() => engine.execute({action: 'close'}), /no focused/);
workspace.activeWindow = a; a.fullScreen = true;
assert.throws(() => engine.execute({action: 'toggle-vertical-split'}), /fullscreen/);
console.log('KWin action tests passed');
