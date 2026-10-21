import QtQuick

// Settings panel: a centered card, the tabs down the left and the tab's
// content on the right. Apply at the foot of the strip shows once the
// Keybinds or Rules tab has saved something mango isn't running yet.
// IPC: `settings toggle | close | open <tab>`; a tab's own name (keybinds,
// rules, layouts / tweaks, wallpapers, displays) toggles or opens that
// tab, and `wallpapers random | set <path>` go to the Wallpaper pane.
Popout {
    id: root
    ipcNames: ["settings", "keybinds", "rules", "layouts", "tweaks", "wallpapers", "displays"]
    function ipc(fn, arg, target) {
        if (target === "wallpapers" && fn === "random") { wallpaper.applyRandom(); return }
        if (target === "wallpapers" && fn === "set") { wallpaper.apply(arg); return }
        const own = { keybinds: "keybinds", rules: "rules", layouts: "layout", tweaks: "layout", wallpapers: "wallpaper", displays: "displays" }
        if (target in own && fn === "toggle") {
            const i = tabs.findIndex(t => t.key === own[target])
            if (visible && tab === i) { visible = false; return }
            tab = i
            visible = true
            return
        }
        if (fn === "toggle") {
            visible = !visible
        } else if (fn === "close") {
            visible = false
        } else if (fn === "open") {
            const i = tabs.findIndex(t => t.key === (target in own ? own[target] : arg))
            tab = i < 0 ? 0 : i
            visible = true
        }
    }

    property int tab: 0
    readonly property var tabs: [
        { key: "keybinds", label: "Keybinds", icon: "󰌌" },
        { key: "rules",    label: "Rules",    icon: "󰖲" },
        { key: "layout",   label: "Layout",   icon: "󰕰" },
        { key: "bar",      label: "Bar",      icon: "󰍜" },
        { key: "wallpaper", label: "Wallpaper", icon: "󰸉" },
        { key: "displays", label: "Displays", icon: "󰍹" }
    ]
    readonly property bool dirty: keybinds.dirty || rules.dirty
    readonly property int stripWidth: 150

    centered: true
    cardWidth: Math.min(1560, fitWidth - 64)
    cardHeight: fitHeight * 0.8

    // the panes that hear shown() and hidden(), by tab key
    readonly property var panes: ({ keybinds: keybinds, rules: rules, wallpaper: wallpaper, displays: displays })
    function sync(hide) {
        if (hide)
            for (const k in panes) panes[k].hidden()
        if (visible)
            panes[tabs[tab].key]?.shown()
    }
    onVisibleChanged: sync(!visible)
    // Ctrl+PageDown / Ctrl+PageUp walk the tabs (Ctrl+Tab is the
    // Keybinds tab's chips). Window shortcuts: they fire before the
    // search field or the wallpaper grid can swallow the key.
    Shortcut { sequences: ["Ctrl+PgDown"]; onActivated: root.tab = (root.tab + 1) % root.tabs.length }
    Shortcut { sequences: ["Ctrl+PgUp"]; onActivated: root.tab = (root.tab + root.tabs.length - 1) % root.tabs.length }
    onTabChanged: {
        takeFocus()
        if (visible)
            sync(true)
    }
    // Apply: scripts/keybinds apply reloads mango's config
    function apply() { rules.apply(); keybinds.apply() }

    // --- tab strip ---
    Column {
        id: strip
        width: root.stripWidth
        spacing: 4

        Repeater {
            model: root.tabs

            ListRow {
                required property var modelData
                required property int index
                glyph: modelData.icon
                text: modelData.label
                active: root.tab === index
                height: 36
                leftMargin: 12
                glyphWidth: 18
                glyphSize: 15
                fontSize: 13
                activeColor: Theme.selbg
                glyphInk: active ? Theme.selfg : Theme.cyan
                ink: active ? Theme.selfg : Qt.alpha(Theme.fg, 0.9)
                onClicked: root.tab = index
            }
        }
    }

    // saved changes mango isn't running yet: one click reloads it
    Btn {
        visible: root.dirty
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.stripWidth
        height: 36
        text: "󰑓  Apply"
        active: true
        fontSize: 12
        activeHoverColor: Qt.lighter(Theme.accent, 1.1)
        fadeMs: 0
        onClicked: root.apply()
    }
    Txt {
        visible: !root.dirty
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.bottomMargin: 10
        text: "esc closes"
        color: Qt.alpha(Theme.fg, 0.35)
    }

    // divider
    Rectangle {
        x: root.stripWidth + 10
        width: 1
        height: parent.height
        color: Qt.alpha(Theme.fg, 0.1)
    }

    // --- the tabs' content ---
    Item {
        id: content
        x: root.stripWidth + 24
        width: parent.width - x
        height: parent.height

        KeybindsPane {
            id: keybinds
            popup: root
            anchors.fill: parent
            visible: root.tab === 0
        }

        RulesPane {
            id: rules
            popup: root
            anchors.fill: parent
            visible: root.tab === 1
        }

        Flickable {
            visible: root.tab === 2
            anchors.fill: parent
            contentHeight: layoutTweaks.implicitHeight
            clip: true
            LayoutTweaks { id: layoutTweaks; popup: root; width: Math.min(420, parent.width) }
        }

        Flickable {
            visible: root.tab === 3
            anchors.fill: parent
            contentHeight: barTweaks.implicitHeight
            clip: true
            BarTweaks { id: barTweaks; width: Math.min(420, parent.width) }
        }

        WallpaperPane {
            id: wallpaper
            popup: root
            anchors.fill: parent
            visible: root.tab === 4
        }

        DisplaysPane {
            id: displays
            popup: root
            anchors.fill: parent
            visible: root.tab === 5
        }
    }
}
