import QtQuick
import org.kde.kwin 3.0
import "windows.js" as Windows

Item {
    id: root
    property bool connected: false
    property int failureCount: 0

    DBusCall {
        id: next
        service: "org.reflexwm.ReflexWM"
        path: "/org/reflexwm/ReflexWM"
        dbusInterface: "org.reflexwm.ReflexWM"
        method: "NextCommand"
        onFinished: function(returnValue) {
            root.connected = true
            root.failureCount = 0
            const text = returnValue[0]
            if (!text) {
                next.call()
                return
            }
            let command
            let result
            try {
                command = JSON.parse(text)
                if (command.version !== 1) throw new Error("unsupported reflex-wm bridge version")
                result = Windows.execute(command)
                result.id = command.id
            } catch (error) {
                result = { id: command ? command.id : "", error: String(error) }
            }
            complete.arguments = [JSON.stringify(result)]
            complete.call()
        }
        onFailed: root.retry()
    }
    DBusCall {
        id: complete
        service: next.service
        path: next.path
        dbusInterface: next.dbusInterface
        method: "CompleteCommand"
        onFinished: next.call()
        onFailed: root.retry()
    }
    Timer {
        id: reconnect
        interval: 1000
        repeat: false
        onTriggered: next.call()
    }
    function retry() {
        connected = false
        failureCount += 1
        if (failureCount === 1) console.log("reflex-wm: waiting for background program")
        reconnect.restart()
    }
    Connections {
        target: Workspace
        function onWindowActivated(window) { Windows.recordFocus(window) }
        function onWindowRemoved(window) { Windows.removeWindow(window) }
    }
    Component.onCompleted: {
        Windows.initialize(Workspace, function(x, y, width, height) { return Qt.rect(x, y, width, height) }, Workspace.MaximizeArea)
        next.call()
    }
}
