import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history (Super+v, or Clipboard in the launcher's actions):
// what cliphist recorded (autostart.conf), newest first. Type to search;
// Enter or a click copies the entry again, Del removes it, Ctrl+Del twice
// clears the history. Images show a thumbnail, decoded once into the
// runtime folder (gone at logout).
Popout {
    id: root
    ipcNames: ["clipboard"]

    property string query: ""
    property int selected: 0
    property bool wipeArmed: false
    property var entries: []         // {line, text, kind: text|link|image, ext}
    property bool loaded: false

    readonly property string thumbDir: Quickshell.env("XDG_RUNTIME_DIR") + "/mango-clipboard"
    readonly property var results: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w !== "")
        return words.length ? entries.filter(e => words.every(w => e.text.toLowerCase().includes(w)))
                            : entries
    }
    onResultsChanged: selected = Math.min(selected, Math.max(results.length - 1, 0))

    centered: true
    cardWidth: 600
    cardHeight: Math.min(520, fitHeight * 0.85)

    onVisibleChanged: {
        if (!visible)
            return
        field.text = ""
        selected = 0
        wipeArmed = false
        reload()
        // after Popout's own focus grab on open
        Qt.callLater(() => field.forceActiveFocus())
    }

    function reload() {
        lister.running = false
        lister.running = true
    }

    // cliphist list: "<id>\t<preview>"; an image previews as
    // "[[ binary data 212 KiB png 1920x1080 ]]"
    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0)
                        continue
                    const preview = line.slice(tab + 1)
                    const img = preview.match(/^\[\[ binary data (.+) (\w+) (\d+)x(\d+) \]\]$/)
                    if (img)
                        out.push({ line: line, kind: "image", ext: img[2],
                                   text: "Image · " + img[2] + " " + img[3] + "×" + img[4] + " · " + img[1] })
                    else
                        out.push({ line: line, kind: /^https?:\/\/\S+$/.test(preview.trim()) ? "link" : "text",
                                   text: preview.trim() })
                }
                root.entries = out
                root.loaded = true
            }
        }
    }

    // removing waits for cliphist before the list is read again
    Process {
        id: remover
        onExited: root.reload()
    }

    function copy(e) {
        if (!e)
            return
        root.visible = false
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "sh", e.line])
    }

    function remove(e) {
        if (!e)
            return
        remover.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", e.line]
        remover.running = true
    }

    function wipe() {
        if (!wipeArmed) {
            wipeArmed = true
            disarm.restart()
            return
        }
        wipeArmed = false
        remover.command = ["sh", "-c", "cliphist wipe; rm -rf \"$1\"", "sh", thumbDir]
        remover.running = true
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.wipeArmed = false
    }

    function move(d) {
        if (!results.length)
            return
        selected = Math.max(0, Math.min(results.length - 1, selected + d))
        list.positionViewAtIndex(selected, ListView.Contain)
    }

    Rectangle {
        id: search
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        radius: 8
        color: Qt.alpha(Theme.fg, 0.06)
        border.width: 1
        border.color: field.activeFocus ? Qt.alpha(Theme.accent, 0.5) : "transparent"

        Txt {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: Theme.accent
            font.pixelSize: 14
        }

        TextInput {
            id: field
            anchors.left: searchIcon.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            selectionColor: Qt.alpha(Theme.accent, 0.4)
            font.family: Theme.fontFamily
            font.pixelSize: 13
            clip: true
            onTextChanged: root.query = text
            Keys.onPressed: event => {
                const k = event.key
                const ctrl = event.modifiers & Qt.ControlModifier
                if (k === Qt.Key_Down || k === Qt.Key_Tab)
                    root.move(1)
                else if (k === Qt.Key_Up || k === Qt.Key_Backtab)
                    root.move(-1)
                else if (k === Qt.Key_PageDown)
                    root.move(8)
                else if (k === Qt.Key_PageUp)
                    root.move(-8)
                else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                    root.copy(root.results[root.selected])
                else if (k === Qt.Key_Delete && ctrl)
                    root.wipe()
                else if (k === Qt.Key_Delete && cursorPosition === text.length)
                    root.remove(root.results[root.selected])
                else if (k === Qt.Key_Escape && text !== "")
                    text = ""
                else {
                    // typing, and a plain Escape on to Popout (closes)
                    event.accepted = false
                    return
                }
                event.accepted = true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text === ""
                text: "Search clipboard"
                color: Qt.alpha(Theme.fg, 0.35)
                font: field.font
            }
        }
    }

    ListView {
        id: list
        anchors.top: search.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: 12
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.results
        currentIndex: root.selected
        highlightFollowsCurrentItem: false

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: root.selected === index
            readonly property bool image: modelData.kind === "image"
            readonly property string thumb: image ? root.thumbDir + "/" + modelData.line.split("\t")[0] + "." + modelData.ext : ""
            width: list.width
            height: image ? 64 : 34
            radius: 8
            color: current ? Qt.alpha(Theme.fg, 0.12) : "transparent"
            border.width: current ? 1 : 0
            border.color: Qt.alpha(Theme.accent, 0.5)

            Txt {
                id: glyph
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                horizontalAlignment: Text.AlignHCenter
                text: row.modelData.kind === "link" ? "󰌹" : row.image ? "󰋩" : "󰅍"
                color: Theme.cyan
                font.pixelSize: 14
            }

            // an image's thumbnail: decoded the first time its row shows
            Process {
                id: decoder
                running: row.image
                command: ["sh", "-c", "mkdir -p \"${2%/*}\" && { [ -s \"$2\" ] || printf '%s\\n' \"$1\" | cliphist decode > \"$2\"; }",
                          "sh", row.modelData.line, row.thumb]
                onExited: thumbImage.source = "file://" + row.thumb
            }
            Image {
                id: thumbImage
                visible: row.image
                anchors.left: glyph.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 84
                height: 48
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 168
            }

            Txt {
                anchors.left: row.image ? thumbImage.right : glyph.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.text
                elide: Text.ElideRight
                maximumLineCount: 1
                color: row.current ? Theme.fg : Qt.alpha(Theme.fg, 0.85)
                font.pixelSize: 12
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selected = row.index
                onClicked: root.copy(row.modelData)
            }
        }

        Txt {
            anchors.centerIn: parent
            visible: root.results.length === 0
            text: !root.loaded ? "loading…"
                : root.entries.length === 0 ? "Nothing copied yet"
                : "Nothing matches \"" + root.query + "\""
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: 12
        }
    }

    // only when the list is taller than the card
    Rectangle {
        visible: list.contentHeight > list.height
        anchors.right: list.right
        anchors.rightMargin: -8
        y: list.y + list.visibleArea.yPosition * list.height
        width: 3
        height: list.visibleArea.heightRatio * list.height
        radius: 2
        color: Qt.alpha(Theme.fg, 0.3)
    }

    Txt {
        id: footer
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.wipeArmed ? "ctrl+del again clears the whole history"
                             : "↵ copy · del remove · ctrl+del clear all · esc close"
        color: root.wipeArmed ? Theme.alert : Qt.alpha(Theme.fg, 0.35)
        font.pixelSize: 10
    }
}
