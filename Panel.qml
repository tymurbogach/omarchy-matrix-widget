import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The pack's switchboard, on the bar.
//
// It used to be a block spliced into ~/.config/omarchy/extensions/omarchy-menu.jsonc
// -- three clicks deep under Style, and the single most invasive thing the pack
// did to a file that is not its own. A bar widget is the extension point
// Omarchy's own built-ins use, so the splice is gone.
//
// It owns no state. Every question goes to `omarchy-matrix status --json` and
// every answer comes back from it, so the ✓ here and the ✓ in the terminal are
// the same ✓ -- and "on" keeps meaning "happening now" rather than
// "configured" (see is_active in the CLI).
//
// A plugin of its own, deliberately. For kind `bar-widget`, "enabled" means
// "present in bar.layout": PluginRegistry.setEnabled inserts the entry there
// and removes it again (PluginRegistry.qml:498-520). Folding this into the rain
// plugin would mean turning both rain layers off took the icon off the bar with
// them, leaving nothing to turn them back on with.
Panel {
  id: root

  moduleName: "io.github.tymurbogach.enter-the-matrix.widget" // Bar.qml overwrites this with the real entry id at load
  // No IpcHandler: the shell routes `summon` to a live bar widget through the
  // bar itself (shell.qml:isBarWidgetPanelPlugin), and registering a target
  // here would only compete with the rain service's own.
  manageIpc: false

  // The one program this panel ever runs, as an absolute path: no PATH lookup,
  // no shell word-splitting, nothing built from input. The provider owns this
  // file the way it owns manifest.json -- the machinery is the CLI, and this
  // is the one name in it.
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-matrix"
  // Omarchy's own floating terminal, by absolute path for the same reason.
  readonly property string launcher: Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-launch-floating-terminal-with-presentation"
  // Both paths come from the environment. An absolute path made of these
  // characters only cannot close a single quote, so it is safe inside the
  // shell command the launcher runs. Any other path disables the actions.
  readonly property bool cliSafe: /^\/[A-Za-z0-9._\/-]+$/.test(cli)
  readonly property bool launcherSafe: /^\/[A-Za-z0-9._\/-]+$/.test(launcher)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // --- what the CLI last told us ---------------------------------------------
  // Sanitized before anything reads it: the answer is parsed, not trusted.
  // An object with schema 1, booleans that are exactly true, strings printable
  // ASCII capped at 64 -- anything else falls back to switched-off defaults,
  // which is also what a CLI that is not there says.

  property var state: ({ name: "Enter the Matrix", version: "", slug: "", theme: "", active: false, settings: ({}), pieces: ({}) })
  property bool asked: false

  function cleanString(value) {
    return String(value || "").replace(/[^\x20-\x7e]/g, "").slice(0, 64)
  }

  // A version is a short run of these characters, or nothing. It lands in the
  // panel title next to the name, and in the label of the Update button.
  function cleanVersion(value) {
    var version = cleanString(value)
    return /^[0-9A-Za-z.+-]{1,32}$/.test(version) ? version : ""
  }

  function sanitize(raw) {
    var clean = { name: "Enter the Matrix", version: "", slug: "", theme: "", active: false, settings: ({}), pieces: ({}) }
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return clean
    if (raw.schema !== 1) return clean
    clean.name = cleanString(raw.name) || "Enter the Matrix"
    clean.version = cleanVersion(raw.version)
    clean.slug = cleanString(raw.slug)
    clean.theme = cleanString(raw.theme)
    clean.active = raw.active === true
    var settings = (raw.settings && typeof raw.settings === "object") ? raw.settings : ({})
    var pieces = (raw.pieces && typeof raw.pieces === "object") ? raw.pieces : ({})
    var keys = ["wallpaper", "screensaver", "lock", "boot", "widget"]
    for (var i = 0; i < keys.length; i++) {
      clean.settings[keys[i]] = settings[keys[i]] === true
      clean.pieces[keys[i]] = pieces[keys[i]] === true
    }
    return clean
  }

  readonly property string packName: state.name || "Enter the Matrix"
  readonly property string currentTheme: String(state.theme || "")
  readonly property bool inEffect: state.active === true

  // Happening now. This decides the switch.
  function on(key) {
    return !!(state.pieces && state.pieces[key] === true)
  }

  // Switched on in the settings, whether or not it is happening now.
  function wanted(key) {
    return !!(state.settings && state.settings[key] === true)
  }

  // The line under a row's label. A piece that is on in the settings but not
  // in effect gets the reason, in the words that `status` uses. Without it,
  // that piece reads exactly like a piece that is off.
  function note(row) {
    if (on(row.key) || !wanted(row.key)) return row.description
    // Repair leaves the boot splash alone: it needs sudo.
    if (row.key === "boot") return "On, but not applied. Run: omarchy-matrix boot on"
    if (!inEffect) return "On, but stood down with the theme"
    return "On, but not in effect. Repair brings it back."
  }

  readonly property var rows: [
    { key: "wallpaper", label: "Background", description: "Rain on the desktop" },
    { key: "screensaver", label: "Screensaver", description: "Rain when idle, instead of Omarchy's" },
    { key: "lock", label: "Lock", description: "Rain behind the password field" },
    { key: "boot", label: "Boot splash", description: "The screen before login. Asks for your password." }
  ]

  readonly property int activeCount: {
    var n = 0
    for (var i = 0; i < rows.length; i++) if (on(rows[i].key)) n++
    return n
  }

  readonly property string summary: {
    if (!asked) return "…"
    if (!inEffect) return currentTheme === "" ? "stood down" : "stood down — theme is " + currentTheme
    if (activeCount === 0) return "nothing on"
    return activeCount + " of " + rows.length + " on"
  }

  // --- the cursor -------------------------------------------------------------
  // Four switches then two actions, and Update last when a newer version is
  // out, in one list: Up/Down walks it, Enter activates. Mouse hover moves the
  // cursor to whatever it is over, so the keyboard never lands somewhere the
  // eye is not.

  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property int itemCount: rows.length + (update.available ? 3 : 2)

  function moveCursor(dx, dy) {
    var step = dy !== 0 ? dy : dx
    cursorIndex = (cursorIndex + step + itemCount) % itemCount
  }

  function activateCursor() {
    if (cursorIndex < rows.length) togglePiece(rows[cursorIndex].key)
    else if (cursorIndex === rows.length) repair()
    else if (cursorIndex === rows.length + 1) uninstall()
    else runUpdate()
  }

  // --- doing things -----------------------------------------------------------
  // argv vectors, never a shell string: the args land in positional parameters
  // without re-tokenizing, so nothing here can become a second command.

  function runHidden(args) {
    if (!root.cliSafe) return
    Quickshell.execDetached([root.cli].concat(args))
  }

  // In a terminal, not detached: these want a password, print as they go, or
  // ask a question. The launcher runs its one argument with `bash -c`, so that
  // argument is a shell command. Only the CLI path goes in single quotes
  // (cliSafe proves it cannot close them). The words after it are constants
  // from this file. Quoting the whole command made bash look for a program
  // named "omarchy-matrix doctor", and Repair, Uninstall and boot did nothing.
  function runVisibly(args) {
    if (!root.cliSafe || !root.launcherSafe) return
    Quickshell.execDetached([root.launcher, "'" + root.cli + "' " + args.join(" ")])
  }

  function togglePiece(key) {
    if (key === "boot") {
      // sudo, and it rebuilds the initramfs.
      runVisibly(["boot", "toggle"])
      root.close()
      return
    }
    runHidden([key, "toggle"])
    // The lock swap restarts the shell, which takes this widget with it; the
    // others land in a second or so. Ask again shortly either way rather than
    // drawing an optimistic tick that may not come true.
    settle.restart()
  }

  function repair() {
    runVisibly(["doctor"])
    root.close()
  }

  function uninstall() {
    runVisibly(["uninstall"])
    root.close()
  }

  // In a terminal: the pull and doctor print as they go, and a pull that stops
  // on local changes has to say so where somebody reads it.
  function runUpdate() {
    if (!root.update.available) return
    runVisibly(["update"])
    root.close()
  }

  function refresh() {
    if (!status.running) {
      root.statusRaw = ""
      root.statusOverflow = false
      status.running = true
    }
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      refresh()
      checkUpdate()
    }
  }

  // The bar icon has to be right before anyone opens the panel: the pack can be
  // stood down by a theme change nobody told us about.
  Component.onCompleted: refresh()

  // The status answer, collected raw and parsed once the process is gone: a
  // clipped stream must never be parsed as if it were whole.
  property string statusRaw: ""
  // Set once the answer passes the cap. Chunks that were already in flight
  // when the process was stopped must not refill the buffer.
  property bool statusOverflow: false

  Process {
    id: status
    // Never hangs the panel: the CLI answers in milliseconds, and anything
    // past three seconds is wedged -- killed a second later.
    command: ["/usr/bin/timeout", "-k", "1", "3", root.cli, "status", "--json"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        if (root.statusOverflow) return
        root.statusRaw += data
        // 16 KiB is far past any answer this CLI gives; past it the stream is
        // garbage, so the process stops instead of parsing a fragment.
        if (root.statusRaw.length > 16384) {
          root.statusOverflow = true
          root.statusRaw = ""
          status.running = false
        }
      }
    }
    // Not installed, or half installed: say nothing and dim the icon rather
    // than drawing four switches that would answer nothing.
    onExited: function(exitCode) {
      if (exitCode === 0 && !root.statusOverflow && root.statusRaw !== "") {
        try {
          root.state = root.sanitize(JSON.parse(root.statusRaw))
        } catch (e) {
          root.state = root.sanitize(null)
        }
      } else {
        root.state = root.sanitize(null)
      }
      root.statusRaw = ""
      root.asked = true
    }
  }

  // --- updates -----------------------------------------------------------------
  // Asked each time the panel opens, apart from the status poll: the check can
  // reach GitHub, and `status` has to stay instant. The CLI keeps the answer
  // for six hours, so opening the panel again costs nothing. The answer is
  // handled like the status one: collected whole, capped, then sanitized.

  property var update: ({ available: false, latest: "" })
  property string updateRaw: ""
  property bool updateOverflow: false

  function sanitizeUpdate(raw) {
    var clean = { available: false, latest: "" }
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return clean
    if (raw.schema !== 1 || raw.available !== true) return clean
    var latest = cleanVersion(raw.latest)
    if (latest === "") return clean
    clean.available = true
    clean.latest = latest
    return clean
  }

  function checkUpdate() {
    if (!root.cliSafe || updateCheck.running) return
    root.updateRaw = ""
    root.updateOverflow = false
    updateCheck.running = true
  }

  Process {
    id: updateCheck
    // A fetch over a slow link takes a while. Past twenty seconds it is
    // wedged, and the panel simply offers no update.
    command: ["/usr/bin/timeout", "-k", "1", "20", root.cli, "update", "--check", "--json"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        if (root.updateOverflow) return
        root.updateRaw += data
        // The answer is one short line. Past 4 KiB it is not that answer.
        if (root.updateRaw.length > 4096) {
          root.updateOverflow = true
          root.updateRaw = ""
          updateCheck.running = false
        }
      }
    }
    onExited: function(exitCode) {
      var answer = null
      if (exitCode === 0 && !root.updateOverflow && root.updateRaw !== "") {
        try {
          answer = JSON.parse(root.updateRaw)
        } catch (e) {
          answer = null
        }
      }
      root.update = root.sanitizeUpdate(answer)
      root.updateRaw = ""
    }
  }

  Component.onDestruction: {
    status.running = false
    updateCheck.running = false
  }

  // One late re-read after a toggle. A piece can take a moment: `lock` waits for
  // the handler to answer steadily, `wallpaper` waits for the background to be
  // selected.
  Timer {
    id: settle
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  // While the panel is open, keep it honest: `omarchy theme set` from anywhere
  // else stands the pack down, and a stale ✓ is the bug this pack has already
  // paid for once.
  Timer {
    running: root.opened
    interval: 3000
    repeat: true
    onTriggered: root.refresh()
  }

  // The bar sizes each slot from the widget item's implicit size
  // (Bar.qml:1565), and a plain Item has none: without these two lines the
  // widget loads, answers, opens its panel -- and paints nothing on the bar.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘨"
    tooltipText: root.packName + " — " + root.summary
    foreground: root.activeCount > 0 && root.inEffect
      ? (root.bar ? root.bar.barForeground : Color.foreground)
      : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.55)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.repair()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // Omarchy's PanelHero, drawn here: it takes the title as one string,
        // and the version has to sit beside the name, not in it. The icon, the
        // sizes and the caption underneath are PanelHero's own. The version is
        // smaller and dim, on the title's baseline, the way OmaSettings shows
        // its version: in the same size and weight it would read as part of
        // the name.
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.inEffect ? 1.0 : 0.5
            textFormat: Text.PlainText
            text: "󰘨"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              spacing: Style.space(6)

              Text {
                id: heroTitle
                textFormat: Text.PlainText
                text: root.packName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                visible: root.state.version !== ""
                anchors.baseline: heroTitle.baseline
                textFormat: Text.PlainText
                text: root.state.version
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.summary.toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        // Said once, at the top, instead of four times over four dead switches:
        // with another theme current the pack has stood down on purpose, and
        // the switches below are what will come back when it returns.
        Text {
          visible: root.asked && !root.inEffect
          width: parent.width
          // Plain text: the slug inside is CLI output, not markup.
          textFormat: Text.PlainText
          text: "Picking another theme stands the pack down. Your settings are kept — "
            + "come back with: omarchy theme set " + (root.state.slug || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.rows

          Toggle {
            required property var modelData
            required property int index

            width: column.width
            label: modelData.label
            // The switch follows what is happening, not what is configured.
            // A piece that is on in the settings but not happening shows an
            // off switch, and this line says why (see note()).
            description: root.note(modelData)
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            checked: root.on(modelData.key)
            hasCursor: root.cursorActive && root.cursorIndex === index
            onHovered: function(isHovered) {
              if (isHovered) { root.cursorActive = true; root.cursorIndex = index }
            }
            onClicked: {
              root.cursorActive = true
              root.cursorIndex = index
              root.togglePiece(modelData.key)
            }
          }
        }

        PanelSeparator { width: parent.width }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Repair"
            iconText: "󰗠"
            tooltipText: "Re-apply everything. Run this after `omarchy refresh shell`."
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursorIndex === root.rows.length
            onHovered: function(isHovered) {
              if (isHovered) { root.cursorActive = true; root.cursorIndex = root.rows.length }
            }
            onClicked: root.repair()
          }

          Button {
            text: "Uninstall"
            iconText: "󰩹"
            // Omarchy's own Remove -> Theme only deletes the theme folder: it
            // would leave the plugin, the lock clone, the CLI and the hooks
            // behind, pointing at a theme that is gone.
            tooltipText: "Remove the pack and the theme, and hand Omarchy's lock, screensaver and boot splash back"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursorIndex === root.rows.length + 1
            onHovered: function(isHovered) {
              if (isHovered) { root.cursorActive = true; root.cursorIndex = root.rows.length + 1 }
            }
            onClicked: root.uninstall()
          }
        }

        // Only when a newer version is out, and last in the cursor's list.
        Button {
          visible: root.update.available
          text: "Update to " + root.update.latest
          iconText: "󰚰"
          tooltipText: "Pull the latest version of this theme, then re-apply everything"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.cursorIndex === root.rows.length + 2
          onHovered: function(isHovered) {
            if (isHovered) { root.cursorActive = true; root.cursorIndex = root.rows.length + 2 }
          }
          onClicked: root.runUpdate()
        }
      }
    }
  }
}
