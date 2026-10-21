pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Now-playing state shared by every output's Media pill and popup: which
// player shows (the playing one wins; the popup can pin one, dropped when
// it exits), players middle-click dismissed until they play again or
// change track, and the position, ticked while playing (MPRIS doesn't
// push it).
Singleton {
    id: root

    property var manual: null
    property var dismissed: ({})      // bus name -> true
    property int dismissals: 0
    function dismiss(p) {
        dismissed[p.dbusName] = true
        dismissals++
    }
    function undismiss(p) {
        if (!dismissed[p.dbusName])
            return
        delete dismissed[p.dbusName]
        dismissals++
    }
    readonly property var player: {
        void dismissals
        const ps = Mpris.players.values
        if (manual && ps.indexOf(manual) >= 0)
            return manual
        for (let i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing)
                return ps[i]
        for (let i = 0; i < ps.length; i++)
            if (!dismissed[ps[i].dbusName])
                return ps[i]
        return null
    }
    readonly property bool playing: player !== null
        && player.playbackState === MprisPlaybackState.Playing
    // a dismissed player that starts playing elsewhere takes the pill back
    onPlayerChanged: if (player && playing) undismiss(player)
    // shown on the bars unless dismissed or stopped
    readonly property bool shown: {
        void dismissals
        return player !== null && !dismissed[player.dbusName]
            && player.playbackState !== MprisPlaybackState.Stopped
    }

    // MPRIS reports artists as an array, but some players hand over a
    // plain string
    readonly property string artistText: {
        const a = player?.trackArtists
        if (!a) return ""
        return Array.isArray(a) ? a.join(", ") : String(a)
    }

    property real pos: 0
    readonly property real len: player?.length ?? 0
    readonly property bool timed: len > 0 && isFinite(len)

    Timer {
        running: root.shown && root.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pos = root.player?.position ?? 0
    }
    // re-read at once on a track change or a seek while paused
    Connections {
        target: root.player
        function onTrackTitleChanged() {
            root.pos = root.player?.position ?? 0
            root.undismiss(root.player)
        }
        function onPlaybackStateChanged() {
            if (root.player.playbackState === MprisPlaybackState.Playing)
                root.undismiss(root.player)
        }
        function onPositionChanged() { root.pos = root.player?.position ?? 0 }
    }

    function fmt(s) {
        s = Math.max(0, Math.round(s))
        const m = Math.floor(s / 60), r = s % 60
        return (m >= 60 ? Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0")
                        : m) + ":" + String(r).padStart(2, "0")
    }
}
