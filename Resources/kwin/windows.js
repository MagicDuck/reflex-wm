// Runs inside KWin; the background program never owns native window references.
var workspace
var makeRect
var maximizeArea
var callLater
var pendingScreenMoves = {}
var history = []
var appOrder = {}
var splitLeft = true

function initialize(ws, rect, areaKind, defer) {
    workspace = ws
    makeRect = rect
    maximizeArea = areaKind
    callLater = defer
    pendingScreenMoves = {}
    history = []
    appOrder = {}
    splitLeft = true
    var windows = eligible()
    for (var i = 0; i < windows.length; i++) recordFocus(windows[i])
    recordFocus(workspace.activeWindow)
}
function id(window) { return String(window.internalId) }
function valid(window) {
    return window && !window.deleted && !window.specialWindow && !window.popupWindow &&
        (window.normalWindow || window.dialog)
}
function eligible() {
    // stackingOrder is available in the declarative scripting API on Plasma 6.0.
    return Array.prototype.slice.call(workspace.stackingOrder).filter(valid)
}
function recordFocus(window) {
    if (!valid(window)) return
    var key = id(window)
    history = history.filter(function(value) { return value !== key })
    history.unshift(key)
}
function removeWindow(window) {
    var key = id(window)
    history = history.filter(function(value) { return value !== key })
    delete pendingScreenMoves[key]
    Object.keys(appOrder).forEach(function(app) {
        appOrder[app] = appOrder[app].filter(function(value) { return value !== key })
        if (!appOrder[app].length) delete appOrder[app]
    })
}
function requireFocused() {
    var window = workspace.activeWindow
    if (!valid(window)) throw new Error("there is no focused application window")
    return window
}
function find(key) {
    var matches = eligible().filter(function(window) { return id(window) === key })
    if (!matches.length) throw new Error("the selected window no longer exists")
    return matches[0]
}
function focus(window) {
    if (window.minimized) window.minimized = false
    if (window.desktops && window.desktops.length &&
        window.desktops.indexOf(workspace.currentDesktop) < 0) {
        workspace.currentDesktop = window.desktops[0]
    }
    if (window.activities && window.activities.length &&
        window.activities.indexOf(workspace.currentActivity) < 0) {
        workspace.currentActivity = window.activities[0]
    }
    workspace.activeWindow = window
    workspace.raiseWindow(window)
    recordFocus(window)
}
function rectCopy(rect) { return { x: rect.x, y: rect.y, width: rect.width, height: rect.height } }
function area(window, output) {
    return workspace.clientArea(maximizeArea, output || window.output, workspace.currentDesktop)
}
function setFrame(window, frame) {
    if (!window.resizeable || !window.moveable) throw new Error("the focused window cannot be moved/resized")
    if (window.fullScreen) throw new Error("leave fullscreen before resizing the window")
    delete pendingScreenMoves[id(window)]
    window.setMaximize(false, false)
    window.frameGeometry = makeRect(frame.x, frame.y, frame.width, frame.height)
}
function appKey(window) {
    if (window.pid > 0) return "pid:" + window.pid
    return "app:" + (window.resourceClass || window.desktopFileName || id(window))
}
function execute(command) {
    if (command.action === "snapshot") {
        var windows = eligible()
        windows.sort(function(a, b) {
            var ai = history.indexOf(id(a)), bi = history.indexOf(id(b))
            return (ai < 0 ? 100000 : ai) - (bi < 0 ? 100000 : bi)
        })
        return {
            focused: valid(workspace.activeWindow) ? id(workspace.activeWindow) : null,
            windows: windows.map(function(window) {
                return { id: id(window), appID: String(window.resourceClass || ""),
                    desktopEntryID: String(window.desktopFileName || ""),
                    title: String(window.caption || ""), pid: window.pid }
            })
        }
    }
    if (command.action === "focus" || command.action === "toggle") {
        var target = find(command.window)
        if (command.action === "toggle" && valid(workspace.activeWindow) && id(workspace.activeWindow) === id(target)) {
            var available = eligible()
            var previous = history.filter(function(key) {
                return key !== id(target) && available.some(function(window) { return id(window) === key })
            })
            if (!previous.length) throw new Error("there is no previous window to activate")
            target = find(previous[0])
        }
        focus(target)
        return {}
    }
    var window = requireFocused()
    var key = id(window)
    switch (command.action) {
    case "close":
        if (!window.closeable) throw new Error("the focused window cannot be closed")
        delete pendingScreenMoves[key]
        window.closeWindow()
        break
    case "toggle-maximize":
        delete pendingScreenMoves[key]
        workspace.slotWindowMaximize()
        break
    case "toggle-vertical-split":
        var bounds = area(window)
        var leftWidth = Math.floor(bounds.width / 2)
        setFrame(window, { x: bounds.x + (splitLeft ? 0 : leftWidth), y: bounds.y,
            width: splitLeft ? leftWidth : bounds.width - leftWidth, height: bounds.height })
        splitLeft = !splitLeft
        break
    case "move-to-next-screen":
        var screens = Array.prototype.slice.call(workspace.screens)
        screens.sort(function(a, b) { return a.geometry.x - b.geometry.x || a.geometry.y - b.geometry.y })
        var index = screens.indexOf(window.output)
        if (screens.length < 2 || index < 0) throw new Error("there is no next screen")
        if (!window.moveableAcrossScreens) throw new Error("the window cannot move between screens")
        var source = area(window)
        var destination = screens[(index + 1) % screens.length]
        var dest = area(window, destination)
        if (source.width <= 0 || source.height <= 0 || dest.width <= 0 || dest.height <= 0)
            throw new Error("could not determine usable screen geometry")
        var frame = rectCopy(window.frameGeometry)
        var width = Math.min(frame.width / source.width * dest.width, dest.width)
        var height = Math.min(frame.height / source.height * dest.height, dest.height)
        var x = dest.x + (frame.x - source.x) / source.width * dest.width
        var y = dest.y + (frame.y - source.y) / source.height * dest.height
        var mapped = { x: Math.min(Math.max(x, dest.x), dest.x + dest.width - width),
            y: Math.min(Math.max(y, dest.y), dest.y + dest.height - height), width: width, height: height }
        workspace.sendClientToScreen(window, destination)
        setFrame(window, mapped)
        // Wayland clients can retain the source size during the output transition.
        // Reapply the captured target on the next event-loop turn, without overriding
        // a newer action, a removed window, or a move to a different output.
        var pending = { frame: mapped, output: destination }
        pendingScreenMoves[key] = pending
        callLater(function() {
            if (pendingScreenMoves[key] !== pending) return
            delete pendingScreenMoves[key]
            if (!valid(window) || window.output !== pending.output) return
            try { setFrame(window, pending.frame) }
            catch (error) { console.log("reflex-wm: could not finish screen resize: " + error) }
        })
        break
    case "focus-next-app-window":
        var app = appKey(window)
        var siblings = eligible().filter(function(candidate) { return appKey(candidate) === app })
        var keys = siblings.map(id)
        var order = (appOrder[app] || []).filter(function(value) { return keys.indexOf(value) >= 0 })
        keys.forEach(function(value) { if (order.indexOf(value) < 0) order.push(value) })
        appOrder[app] = order
        focus(find(order[(order.indexOf(key) + 1) % order.length]))
        break
    default: throw new Error("unsupported window action: " + command.action)
    }
    return {}
}
