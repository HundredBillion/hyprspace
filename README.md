# HyprSpace

HyprSpace is a tiling window manager for macOS that aims to feel like [Hyprland](https://hyprland.org/).

It is built on an MIT-licensed i3-like tiling window manager by Nikita Bobko, which provides the window management
foundation (the tree model, workspace emulation, CLI, config parsing). See [LICENSE.txt](./LICENSE.txt).

## Status

Early work in progress. Not released, not notarized, debug builds only.

## Hyprland-style features

- **Dwindle layout (default).** Each new window splits the focused window in half along its longer side.
- **Master layout.** `new-window-placement = 'master'`: the first window is the master, the rest are stacked beside it.
  `layoutmsg swapwithmaster`, `layoutmsg focusmaster` and `layoutmsg mfact` work like in Hyprland.
- **Focused-window border.** Configurable width, color and rounding (`border.*`).
- **Window animations.** Windows glide to their new position when the layout changes (`animations.*`).
- **Special workspace.** `togglespecialworkspace [name]` shows a scratchpad on top of the current workspace.
- **Pinned windows.** `pin` keeps a floating window visible on every workspace of its monitor.
- **Window rules.** `windowrule = ['float, class:^(Calculator)$']` in Hyprland's vocabulary.
- **Hyprland dispatchers.** Bindings and the CLI accept `killactive`, `movefocus`, `movewindow`, `swapwindow`,
  `focusmonitor`, `togglefloating`, `togglesplit`, `movetoworkspace`, `movetoworkspacesilent`,
  `togglespecialworkspace`, `resizeactive`, `layoutmsg`, `pin`, `cyclenext`, `focuscurrentorlast` and `exec`.
- **Example config.** [hyprland-like-config-example.toml](docs/config-examples/hyprland-like-config-example.toml)
  mirrors Hyprland's default bindings, with `alt` in place of SUPER.
- Config lives at `~/.hyprspace.toml` (or `${XDG_CONFIG_HOME}/hyprspace/hyprspace.toml`). The CLI is `hyprspace`.

## What macOS does not allow

Hyprland is a Wayland compositor and draws every window itself. On macOS that job belongs to the closed WindowServer,
so HyprSpace can only ask apps to move and resize through the Accessibility API. That is why:

- Animations are emulated by resizing a window several times in a row. Apps that are slow to resize look choppy.
- The border is a separate click-through window around the focused window. Only the focused window has one.
- The special workspace is emulated with floating windows instead of a real overlay.
- Blur, shadows, custom shaders and window opacity are out of reach without disabling System Integrity Protection.

## Roadmap

- [ ] Borders for inactive windows
- [ ] Animations for opening and closing windows and for workspace switches
- [ ] `resizeactive` for floating windows
- [ ] More window rule matchers and effects (`size`, `move`, `opacity`, ...)
- [ ] Packaged, signed `HyprSpace.app` release build

## Building

Requires Xcode. Nothing else has to be installed.

```
./build-debug.sh        # builds .debug/HyprSpaceApp and .debug/hyprspace
./swift-test.sh
```

Run the debug build from a terminal and grant that terminal Accessibility permission when prompted:

```
./run-debug.sh
```

Documentation: [Guide](docs/guide.adoc), [Commands](docs/commands.adoc).
