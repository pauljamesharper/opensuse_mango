import QtQuick
import Quickshell

// The bar window, effectiveBarHeight px tall. Under mango this is a
// wlr-layer-shell panel: the compositor reserves its exclusive zone and
// re-tiles live when the height changes — no struts, no placement fixups.
PanelWindow {
    id: root

    property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.effectiveBarHeight
    color: "transparent"
    // map once, at final size — see Theme.barStateReady
    visible: Theme.barStateReady

    Rectangle {
        id: panel
        anchors.fill: parent
        // inset from the screen edges; the gap below comes from mango's
        // outer gaps (same value), so the bar and windows share one margin
        anchors.topMargin: Theme.edgeInset
        anchors.leftMargin: Theme.edgeInset
        anchors.rightMargin: Theme.edgeInset
        anchors.bottomMargin: 0

        radius: Theme.barRadius
        color: Qt.alpha(Theme.bg, 0.94)
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.35)

        Behavior on color { ColorAnimation { duration: 400 } }
        Behavior on border.color { ColorAnimation { duration: 400 } }

        // A portrait monitor or a small laptop panel cannot hold every
        // pill. When the two clusters would run into each other, the pills
        // that only repeat what another window shows step aside: media
        // first, then the CPU/RAM readout. Measured, not guessed: what the
        // rest needs is summed without those two, so hiding one cannot
        // change the answer and flip it back.
        // (the cluster's children are the module loaders, each carrying
        // its gap in its width; media and metrics are found by key)
        readonly property real restWidth: {
            let w = leftCluster.width + 56
            const kids = rightCluster.children
            for (let i = 0; i < kids.length; i++) {
                const k = kids[i]
                if (k.key !== undefined && k.key !== "media" && k.key !== "metrics" && k.shown)
                    w += k.width
            }
            return w
        }
        function need(key) {
            const kids = rightCluster.children
            for (let i = 0; i < kids.length; i++)
                if (kids[i].key === key && kids[i].item) return kids[i].item.implicitWidth + rightCluster.gap
            return 0
        }
        readonly property real metricsNeed: need("metrics")
        readonly property real mediaNeed: need("media")
        readonly property bool fitsMetrics: restWidth + metricsNeed <= width
        readonly property bool fitsMedia: restWidth + metricsNeed + mediaNeed <= width

        // right-click empty bar = the layout/tweaks picker (same popup
        // as clicking the layout button); declared before the clusters
        // so module mouse areas stack above it
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: BarIpc.call("settings", "open", "layout")
        }

        Row {
            id: leftCluster
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Launcher {}
            Tags {}
            LayoutButton { id: layoutBtn }
        }

        // Title lives in the gap between the clusters: screen-centered when
        // it fits, nudged inward when it doesn't, elided to the gap width.
        // (A symmetric clamp goes negative on narrow screens — the right
        // cluster is wide — and a negative-width Text ignores elide.)
        Title {
            anchors.verticalCenter: parent.verticalCenter
            readonly property real gapL: leftCluster.x + leftCluster.width + 24
            readonly property real gapR: rightCluster.x - 24
            width: Math.max(0, Math.min(implicitWidth, gapR - gapL))
            x: Math.max(gapL, Math.min((parent.width - width) / 2, gapR - width))
            visible: width > 40
        }

        // the right cluster: Theme.modules (the Bar tab's Modules list)
        // says which show and in what order; a module that hides itself
        // when idle (media, updates, caps lock) still does
        Row {
            id: rightCluster
            anchors.right: parent.right
            // each loader carries the gap after it, so a hidden module
            // leaves no double spacing; the command menu comes last, fixed
            readonly property int gap: 4
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            // looked up when a Loader asks (a map built at construction
            // would see the Component ids before they exist)
            function componentFor(key) {
                switch (key) {
                case "media": return cMedia;        case "weather": return cWeather
                case "metrics": return cMetrics;    case "volume": return cVolume
                case "network": return cNetwork;    case "updates": return cUpdates
                case "tray": return cTray;          case "bell": return cBell
                case "clock": return cClock;        case "micmute": return cMicMute
                case "capslock": return cCapsLock;  case "screenshot": return cScreenshot
                }
                return null
            }
            Component { id: cMedia; Media { allowed: panel.fitsMedia } }
            Component { id: cWeather; Weather {} }
            Component { id: cMetrics; Metrics { visible: panel.fitsMetrics } }
            Component { id: cVolume; Volume {} }
            Component { id: cNetwork; Network {} }
            Component { id: cUpdates; Updates {} }
            Component { id: cTray; Tray {} }
            Component { id: cBell; Bell {} }
            Component { id: cClock; Clock {} }
            Component { id: cMicMute; MicMute {} }
            Component { id: cCapsLock; CapsLock {} }
            Component { id: cScreenshot; Screenshot {} }

            Repeater {
                model: Theme.modules.filter(m => m.on)
                // always visible itself (binding to the item's visibility
                // is circular: a hidden parent hides the child); a module
                // that hides itself collapses the loader to no width
                Loader {
                    required property var modelData
                    readonly property string key: modelData.key
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: rightCluster.componentFor(modelData.key)
                    readonly property bool shown: item !== null && item.visible
                    width: shown ? item.implicitWidth + rightCluster.gap : 0
                    height: item ? item.implicitHeight : 0
                }
            }
            // always here: it hosts the settings panel, the power menu and
            // the notification popups (Super+/, Super+x reach them by ipc)
            Commands {}
        }
    }
}
