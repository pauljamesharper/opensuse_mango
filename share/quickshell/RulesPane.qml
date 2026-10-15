import QtQuick
import Quickshell
import Quickshell.Io

// Rules tab of the settings panel: ~/.config/mango/rules.conf as a list
// — what a rule matches and what it does — with an editor built around
// the decisions rather than mango's windowrule keys. A new rule starts
// from a window: pick one of the open windows (mmsg lists them, with
// the command that opened each, from /proc) or type the app id; the match shows as one chip, the raw app id / title stay
// behind "edit match". Then floating (with a size, a fraction of the
// screen), the tag it opens on, the monitor when there is more than one,
// a note. "Scratchpad" is a switch: on, it asks for the command that
// opens the window and the key that toggles it — saving writes the rule
// and the toggle_named_scratchpad bind both, and deleting removes both.
// The app id doubles as the scratchpad's name, so the command has to
// start the app with that id (kitty --class NAME, most GUI apps have a
// fixed one). Every write goes through mango's own config check first,
// so a bad rule is refused with its reason. scripts/rules and
// scripts/keybinds are the back ends.
Item {
    id: root
    required property var popup

    property var rows: []        // {section, match, detail, line}
    property var editing: null   // {line, section, isNew, title}
    property bool floating: false
    property int tag: 0          // 0: none
    property string monitor: ""
    property bool scratch: false
    property bool showMatch: false
    property var windows: null   // open windows to pick from: [{appid, title, cmd}]
    property string pickedCmd: "" // what opened the picked window: the scratchpad's command
    property int bindLine: 0     // the scratchpad's keybind, when editing one
    property bool dirty: false
    property string status: ""
    property bool statusBad: false
    readonly property string tool: Theme.shareDir + "/scripts/rules"
    readonly property string ktool: Theme.shareDir + "/scripts/keybinds"

    function shown() { status = ""; loader.running = true }
    function hidden() { chordField.stop(); editing = null; windows = null }
    function apply() { dirty = false }

    Process {
        id: loader
        command: [root.tool]
        stdout: StdioCollector { onStreamFinished: root.rows = root.parse(text) }
    }
    function parse(t) {
        const out = []
        for (const l of t.split("\n")) {
            const f = l.split("\t")
            if (f.length < 4) continue
            out.push({ section: f[0], match: f[1], detail: f[2], line: parseInt(f[3]) })
        }
        return out
    }
    readonly property var sectionTitles: ({ floating: "Floating windows", tags: "Opens on a tag", scratchpads: "Scratchpads" })
    readonly property var sections: {
        const s = []
        for (const r of rows) {
            let sec = s.find(x => x.key === r.section)
            if (!sec) { sec = { key: r.section, title: sectionTitles[r.section] ?? r.section, rows: [] }; s.push(sec) }
            sec.rows.push(r)
        }
        return s
    }

    // one verb at a time, for either script; the exit code rides on the first line
    Process {
        id: proc
        property var done: null
        stdout: StdioCollector {
            onStreamFinished: {
                const f = proc.done; proc.done = null
                const i = text.indexOf("\n")
                if (f) f(parseInt(text.slice(0, i)), text.slice(i + 1))
            }
        }
    }
    function run(script, args, cb) {
        proc.done = cb
        proc.command = ["sh", "-c", 'o=$("$0" "$@" 2>&1); r=$?; printf "%s\\n%s" "$r" "$o"', script].concat(args)
        proc.running = true
    }
    function setStatus(s, bad) { status = s; statusBad = bad }

    function fill(f) {
        idField.text = f[0] ?? ""; titleField.text = f[1] ?? ""
        tag = parseInt(f[2] ?? "") || 0
        floating = f[3] === "yes"; monitor = f[4] ?? ""
        wField.text = f[5] ?? ""; hField.text = f[6] ?? ""
        scratch = f[7] === "yes"; descField.text = f[8] ?? ""
        runField.text = ""; chordField.text = ""; bindLine = 0; pickedCmd = ""
        showMatch = false; windows = null
    }
    readonly property string matchText: {
        const parts = []
        if (idField.text.trim() !== "") parts.push("app " + idField.text.trim())
        if (titleField.text.trim() !== "") parts.push("title " + titleField.text.trim())
        return parts.join("  ·  ")
    }
    function openEditor(line, section, match) {
        run(root.tool, ["get", String(line)], (rc, out) => {
            const f = out.replace(/\n$/, "").split("\t")
            if (rc !== 0 || f.length < 9) return
            editing = { line: line, section: section, isNew: false, title: match }
            fill(f)
            if (scratch) findBind(idField.text.trim())
            focusEditor()
        })
    }
    // the toggle_named_scratchpad bind for NAME, from the keybinds rows:
    // its line, chord and the command it runs
    function findBind(name) {
        run(root.ktool, [], (rc, out) => {
            bindLine = 0
            for (const l of out.split("\n")) {
                const f = l.split("\t")
                if (f.length < 6 || f[4] !== "do" || f[3].indexOf("local:") === 0) continue
                const a = f[5].split(",")
                if (a[0] !== "toggle_named_scratchpad" || a[1] !== name) continue
                bindLine = parseInt(f[3])
                runField.text = a.slice(3).join(",")
                run(root.ktool, ["get", String(bindLine)], (rc2, out2) => {
                    const g = out2.replace(/\n$/, "").split("\t")
                    if (rc2 === 0 && g.length >= 2)
                        chordField.text = (g[0] === "none" || g[0] === "" ? "" : g[0] + "+") + g[1]
                })
                return
            }
        })
    }
    function addRule() {
        editing = { line: 0, section: "", isNew: true, title: "" }
        fill([])
        pick()
    }
    function focusEditor() { status = ""; Qt.callLater(() => idField.input.forceActiveFocus()) }
    function cancelEdit() { chordField.stop(); editing = null; windows = null }
    // where a rule files by what it does
    function sectionFor() { return scratch ? "scratchpads" : tag ? "tags" : "floating" }
    function save() {
        if (!editing) return
        chordField.stop()
        const e = editing
        const id = idField.text.trim()
        if (id === "" && titleField.text.trim() === "") { setStatus("pick a window first, or type its app id", true); return }
        if (scratch && id === "") { setStatus("a scratchpad is matched by app id (it is the scratchpad's name)", true); return }
        if (scratch && runField.text.trim() === "") { setStatus("a scratchpad needs the command that opens it", true); return }
        const args = (e.isNew ? ["add", sectionFor()] : ["set", String(e.line)]).concat([
            id, titleField.text.trim(), tag ? String(tag) : "", floating || scratch ? "yes" : "no", monitor,
            floating || scratch ? wField.text.trim() : "", floating || scratch ? hField.text.trim() : "",
            scratch ? "yes" : "no", descField.text.trim()])
        run(root.tool, args, (rc, out) => {
            if (rc !== 0) { setStatus(out.trim(), true); return }
            // the rule is in the file now: a second Save edits it
            const line = parseInt(out.trim())
            if (e.isNew && !isNaN(line)) editing = { line: line, section: sectionFor(), isNew: false, title: "app " + id }
            if (scratch && chordField.text.trim() !== "")
                saveBind(id)
            else
                saved()
        })
    }
    // the scratchpad's toggle key: a new bind, or the one it already has
    function saveBind(name) {
        const ck = chordField.split(chordField.text)
        const desc = descField.text.trim() !== "" ? descField.text.trim() : "Scratchpad " + name
        const value = "toggle_named_scratchpad," + name + ",none," + runField.text.trim()
        const args = (bindLine ? ["set", String(bindLine)] : ["add", "apps"]).concat([ck[0], ck[1], desc, "do", value])
        run(root.ktool, args, (rc, out) => {
            if (rc !== 0) { setStatus("rule saved, but the key: " + out.trim(), true); dirty = true; loader.running = true; return }
            saved()
        })
    }
    function saved() {
        dirty = true; editing = null; windows = null
        setStatus("saved · Apply reloads mango with it", false)
        loader.running = true
    }
    function remove() {
        const e = editing
        if (!e || e.isNew) { cancelEdit(); return }
        const dropRule = () => run(root.tool, ["delete", String(e.line)], (rc, out) => {
            if (rc !== 0) { setStatus(out.trim(), true); return }
            dirty = true; editing = null
            setStatus("removed · Apply reloads mango without it", false)
            loader.running = true
        })
        // a scratchpad's bind goes with it
        if (scratch && bindLine)
            run(root.ktool, ["delete", String(bindLine)], (rc, out) => { if (rc !== 0) setStatus(out.trim(), true); else dropRule() })
        else
            dropRule()
    }
    // the open windows, to choose the match from
    function pick() {
        run(root.tool, ["pick"], (rc, out) => {
            const w = []
            for (const l of out.split("\n")) {
                const f = l.split("\t")
                if (f.length < 2) continue
                const inner = f[3] ?? ""
                // a terminal showing a program: offered as that program (a
                // rule on the bare terminal would catch every terminal)
                const key = inner !== "" ? f[0] + " " + inner : f[0]
                if (!w.find(x => x.key === key)) w.push({ key: key, appid: f[0], title: f[1], cmd: f[2] ?? "", inner: inner })
            }
            windows = w
            if (w.length === 0) { showMatch = true; focusEditor() }
        })
    }
    // how each terminal is told its app id (the scratchpad's name)
    readonly property var classFlag: ({ kitty: "--class", foot: "--app-id", alacritty: "--class", wezterm: "--class", ghostty: "--class" })
    function choose(w) {
        if (!editing) editing = { line: 0, section: "", isNew: true, title: "" }
        titleField.text = ""
        if (w.inner !== "") {
            // kitty running pulsemixer → app id pulsemixer, opened by
            // kitty --class pulsemixer -e pulsemixer
            const prog = w.inner.split(" ")[0].split("/").pop()
            const term = (w.cmd.split(" ")[0] || w.appid).split("/").pop()
            idField.text = prog
            pickedCmd = term + " " + (classFlag[term] ?? "--class") + " " + prog + " -e " + w.inner
            setStatus(term + " showing " + prog + ": matched as " + prog + ", opened by " + pickedCmd, false)
        } else {
            idField.text = w.appid
            pickedCmd = w.cmd
        }
        if (scratch && runField.text.trim() === "") runField.text = w.cmd
        windows = null; showMatch = false
    }
    function edit(line) {
        popup.visible = false
        Quickshell.execDetached([root.tool, "open", String(line)])
    }

    component Pill: Rectangle {
        property string label
        property bool active: false
        signal clicked()
        width: pillText.implicitWidth + 18
        height: 24
        radius: 8
        color: active ? Theme.accent : pillMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }
        Txt { id: pillText; anchors.centerIn: parent; text: parent.label; color: parent.active ? Theme.bg : Qt.alpha(Theme.fg, 0.85); font.bold: parent.active }
        MouseArea { id: pillMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
    component Lbl: Txt {
        width: 110
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.alpha(Theme.fg, 0.7)
    }
    component Switch: Item {
        id: sw
        property string label
        property bool on: false
        property bool enabled: true
        signal toggled()
        anchors.verticalCenter: parent.verticalCenter
        width: swText.x + swText.implicitWidth
        height: 24
        opacity: enabled ? 1 : 0.4
        Toggle { id: swToggle; anchors.verticalCenter: parent.verticalCenter; on: sw.on; enabled: sw.enabled; onToggled: sw.toggled() }
        Txt { id: swText; x: swToggle.width + 8; anchors.verticalCenter: parent.verticalCenter; text: sw.label; color: Qt.alpha(Theme.fg, 0.9) }
        MouseArea { anchors.fill: parent; enabled: sw.enabled; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    // --- header ---
    Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34
        radius: 8
        color: Qt.alpha(Theme.fg, 0.06)
        Txt {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "󰖲  Window rules and scratchpads"
            color: Qt.alpha(Theme.fg, 0.8)
            font.pixelSize: 12
        }
        EditButton {
            anchors.right: hint.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            label: "+ New rule"
            primary: true
            onClicked: root.addRule()
        }
        Txt {
            id: hint
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.4)
            elide: Text.ElideRight
            text: root.status !== "" ? root.status : "click a rule to edit it · right-click opens the file"
            color: root.status === "" ? Qt.alpha(Theme.fg, 0.35) : root.statusBad ? Theme.red : Qt.alpha(Theme.fg, 0.7)
        }
    }

    // --- list ---
    Flickable {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: root.editing ? editorPanel.top : parent.bottom
        anchors.bottomMargin: root.editing ? 14 : 0
        contentWidth: width
        contentHeight: list.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: list
            width: parent.width
            spacing: 14

            Txt {
                visible: root.rows.length === 0
                text: "No rules yet. New rule → pick a window → say what it should do."
                color: Qt.alpha(Theme.fg, 0.5)
            }

            Repeater {
                model: root.sections

                Column {
                    id: section
                    required property var modelData
                    width: parent.width
                    spacing: 1

                    Txt {
                        leftPadding: 6
                        bottomPadding: 4
                        text: section.modelData.title
                        color: Theme.accent
                        font.bold: true
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: section.modelData.rows

                        Rectangle {
                            id: ruleRow
                            required property var modelData
                            width: parent.width
                            height: Math.max(matchCap.height, detail.implicitHeight) + 8
                            radius: 6
                            color: rowMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Rectangle {
                                id: matchCap
                                x: 6; y: 4
                                height: 20
                                width: Math.min(matchText.implicitWidth + 12, 300)
                                radius: 4
                                color: Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)
                                clip: true
                                Txt { id: matchText; anchors.centerIn: parent; text: ruleRow.modelData.match; color: Theme.fg }
                            }
                            Txt {
                                id: detail
                                x: 320; y: 6
                                width: parent.width - x - 50
                                text: ruleRow.modelData.detail
                                wrapMode: Text.Wrap
                                color: Qt.alpha(Theme.fg, 0.9)
                                font.pixelSize: 12
                            }
                            Txt {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                y: 7
                                text: "L" + ruleRow.modelData.line
                                opacity: rowMa.containsMouse ? 1 : 0
                                color: Qt.alpha(Theme.fg, 0.4)
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: m => {
                                    if (m.button === Qt.RightButton) root.edit(ruleRow.modelData.line)
                                    else root.openEditor(ruleRow.modelData.line, ruleRow.modelData.section, ruleRow.modelData.match)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- editor ---
    Rectangle {
        id: editorPanel
        visible: root.editing !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: edCol.implicitHeight + 24
        radius: 10
        color: Qt.alpha(Theme.fg, 0.05)
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.3)

        Column {
            id: edCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            Txt {
                width: parent.width
                text: !root.editing ? "" : root.editing.isNew ? "New rule"
                    : "Editing: " + root.editing.title + "  ·  line " + root.editing.line
                color: Theme.accent
                font.bold: true
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            // 1. the window
            Row {
                spacing: 8
                Lbl { text: "Window" }
                EditButton { anchors.verticalCenter: parent.verticalCenter; label: "󰖯 Pick a window"; primary: root.matchText === ""; onClicked: root.pick() }
                Rectangle {
                    visible: root.matchText !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    width: matchChip.implicitWidth + 18
                    radius: 8
                    color: Qt.alpha(Theme.accent, 0.18)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accent, 0.4)
                    Txt { id: matchChip; anchors.centerIn: parent; text: root.matchText; color: Theme.fg }
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.showMatch ? "hide match fields" : (root.matchText === "" ? "or type its app id" : "edit match")
                    color: Theme.accent
                    font.pixelSize: 11
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showMatch = !root.showMatch }
                }
            }
            // the open windows, one chip each
            Flow {
                visible: root.windows !== null
                width: parent.width
                spacing: 6
                leftPadding: 118
                Txt { visible: root.windows !== null && root.windows.length === 0; text: "nothing open to pick from: open the app, or type its app id"; color: Qt.alpha(Theme.fg, 0.5) }
                Repeater {
                    model: root.windows ?? []
                    Pill {
                        required property var modelData
                        label: modelData.inner !== "" ? modelData.appid + "  ·  " + modelData.inner.split(" ")[0].split("/").pop()
                             : modelData.appid + (modelData.title !== "" ? "  ·  " + modelData.title.slice(0, 40) : "")
                        onClicked: root.choose(modelData)
                    }
                }
            }
            Row {
                visible: root.showMatch
                spacing: 8
                Lbl { text: "" }
                EditField { id: idField; width: 260; placeholder: "app id"; onAccepted: root.save(); onEscaped: root.cancelEdit() }
                EditField { id: titleField; width: 300; placeholder: "title"; onAccepted: root.save(); onEscaped: root.cancelEdit() }
                Txt { anchors.verticalCenter: parent.verticalCenter; text: "both are regexes; mmsg get focusing-client shows a window's"; color: Qt.alpha(Theme.fg, 0.4); font.pixelSize: 10 }
            }

            // 2. what it does
            Row {
                spacing: 8
                Lbl { text: "Window is" }
                Switch { label: "floating"; on: root.floating || root.scratch; enabled: !root.scratch; onToggled: root.floating = !root.floating }
                Item { width: 16; height: 1 }
                Txt { visible: root.floating || root.scratch; anchors.verticalCenter: parent.verticalCenter; text: "size"; color: Qt.alpha(Theme.fg, 0.7) }
                EditField { id: wField; visible: root.floating || root.scratch; width: 70; placeholder: "width"; onAccepted: root.save(); onEscaped: root.cancelEdit() }
                Txt { visible: root.floating || root.scratch; anchors.verticalCenter: parent.verticalCenter; text: "×"; color: Qt.alpha(Theme.fg, 0.5) }
                EditField { id: hField; visible: root.floating || root.scratch; width: 70; placeholder: "height"; onAccepted: root.save(); onEscaped: root.cancelEdit() }
                Txt { visible: root.floating || root.scratch; anchors.verticalCenter: parent.verticalCenter; text: "of the screen (0.6 = 60%), empty: the app's own size"; color: Qt.alpha(Theme.fg, 0.4); font.pixelSize: 10 }
            }
            Row {
                spacing: 8
                Lbl { text: "Opens on tag" }
                Repeater {
                    model: 12
                    Pill {
                        required property int index
                        label: String(index + 1)
                        active: root.tag === index + 1
                        onClicked: root.tag = root.tag === index + 1 ? 0 : index + 1
                    }
                }
                Txt { anchors.verticalCenter: parent.verticalCenter; leftPadding: 6; text: root.tag ? "" : "none: the current tag"; color: Qt.alpha(Theme.fg, 0.4) }
            }
            Row {
                visible: Quickshell.screens.length > 1
                spacing: 8
                Lbl { text: "On monitor" }
                Pill { label: "current"; active: root.monitor === ""; onClicked: root.monitor = "" }
                Repeater {
                    model: Quickshell.screens
                    Pill { required property var modelData; label: modelData.name; active: root.monitor === modelData.name; onClicked: root.monitor = modelData.name }
                }
            }

            // 3. scratchpad
            Row {
                spacing: 8
                Lbl { text: "Scratchpad" }
                Switch {
                    label: root.scratch ? "a scratchpad: a key shows and hides it" : "make it a scratchpad"
                    on: root.scratch
                    onToggled: {
                        root.scratch = !root.scratch
                        if (root.scratch) {
                            root.floating = true
                            if (wField.text.trim() === "" && hField.text.trim() === "") { wField.text = "0.6"; hField.text = "0.6" }
                            if (runField.text.trim() === "") runField.text = root.pickedCmd
                        }
                    }
                }
            }
            Row {
                visible: root.scratch
                spacing: 8
                Lbl { text: "Opened by" }
                EditField { id: runField; width: 420; placeholder: "command that opens it, e.g. kitty --class notes"; onAccepted: root.save(); onEscaped: root.cancelEdit() }
                Txt { anchors.verticalCenter: parent.verticalCenter; text: "it must open with the app id above"; color: Qt.alpha(Theme.fg, 0.4); font.pixelSize: 10 }
            }
            Row {
                visible: root.scratch
                spacing: 8
                Lbl { text: "Toggle key" }
                ChordField { id: chordField; onAccepted: root.save(); onEscaped: root.cancelEdit() }
                Txt { anchors.verticalCenter: parent.verticalCenter; text: root.bindLine ? "" : "written to keybinds.conf on save"; color: Qt.alpha(Theme.fg, 0.4) }
            }

            Row {
                spacing: 8
                Lbl { text: "Note" }
                EditField { id: descField; width: 420; placeholder: "optional"; onAccepted: root.save(); onEscaped: root.cancelEdit() }
            }

            Row {
                spacing: 8
                EditButton { label: "Save"; primary: true; onClicked: root.save() }
                EditButton { label: "Cancel"; onClicked: root.cancelEdit() }
                EditButton { visible: root.editing && !root.editing.isNew; label: "Delete"; ink: Theme.red; onClicked: root.remove() }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 8
                    width: edCol.width - 300
                    elide: Text.ElideRight
                    visible: root.status !== ""
                    text: root.status
                    color: root.statusBad ? Theme.red : Qt.alpha(Theme.fg, 0.7)
                    font.bold: root.statusBad
                }
            }
        }
    }
}
