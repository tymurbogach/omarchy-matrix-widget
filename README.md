# Matrix Widget

The bar widget for the [Matrix pack for Omarchy](https://github.com/tymurbogach/omarchy-enter-the-matrix-theme):
one icon on your bar, and a panel with four switches — desktop rain,
screensaver, lock, and boot splash — plus Repair and Uninstall.

![Matrix panel](preview.png)

This widget owns no state of its own. Every question it asks goes to the
`omarchy-matrix` CLI (`omarchy-matrix status --json`), which the main pack
installs. **If you install the widget without the rest of the pack, the icon
is dimmed and the panel has nothing to report.** That is expected.

A switch shows what is happening now. If a piece is on in your settings but
not happening, the switch is off and the line under it says why. For example,
another theme stands the pack down, and each piece that is on then says
"On, but stood down with the theme".

## Install

The normal way is automatic: installing the
[Matrix pack](https://github.com/tymurbogach/omarchy-enter-the-matrix-theme) via its
own `install.sh` fetches this repo and stages it for you. You do not need to
add it separately.

To add just this widget on its own, for development only:

```bash
omarchy plugin add https://github.com/tymurbogach/omarchy-matrix-widget --enable
```

The pack pins the widget to one commit. The pack's `install.sh` leaves a
checkout added by hand alone, so that checkout does not follow the pin.

## Remove

```bash
omarchy plugin remove io.github.tymurbogach.enter-the-matrix.widget
```

If you installed the full pack, use its own uninstaller instead
(`omarchy-matrix uninstall`), which also hands back the lock, screensaver and
boot splash it took over.

## Requirements

Part of the Matrix pack, on Omarchy 4.0.3. The widget runs the pack's CLI by
absolute path, `~/.local/bin/omarchy-matrix`, and never looks it up on PATH.
The pack's `install.sh` creates that file. Without it, every action is off.

## License

MIT.