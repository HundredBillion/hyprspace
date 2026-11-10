# HyprSpace

HyprSpace is a tiling window manager for macOS that aims to feel like [Hyprland](https://hyprland.org/).

It is built on an MIT-licensed i3-like tiling window manager by Nikita Bobko, which provides the window management
foundation (the tree model, workspace emulation, CLI, config parsing). See [LICENSE.txt](./LICENSE.txt).

## Status

Early work in progress. Not released, not notarized, debug builds only.

## Hyprland-style features

- **Dwindle layout (default).** Each new window splits the focused window in half along its longer side.
- **Master layout.** `new-window-placement = 'master'`: the first window is the master, the rest are stacked beside it.
- **Hyprland dispatchers.** Bindings and the CLI accept `killactive`, `movefocus`, `movewindow`, `swapwindow`,
  `focusmonitor`, `togglefloating`, `togglesplit`, `movetoworkspace`, `movetoworkspacesilent`,
  `togglespecialworkspace`, `cyclenext`, `focuscurrentorlast` and `exec`.
- **Special workspace.** `togglespecialworkspace [name]` jumps to a scratchpad workspace and back.
- **Pinned windows.** `pin` keeps a floating window visible on every workspace of its monitor.
- **Example config.** [hyprland-like-config-example.toml](docs/config-examples/hyprland-like-config-example.toml)
  mirrors Hyprland's default bindings, with `alt` in place of SUPER.
- Config lives at `~/.hyprspace.toml` (or `${XDG_CONFIG_HOME}/hyprspace/hyprspace.toml`). The CLI is `hyprspace`.

## What macOS does not allow

Hyprland is a Wayland compositor and draws every window itself. On macOS that job belongs to the closed WindowServer,
so HyprSpace can only ask apps to move and resize through the Accessibility API. Blur, custom shaders and
compositor-level animations are out of reach without disabling System Integrity Protection.

## Roadmap

- [ ] Focused-window borders
- [ ] Special workspace shown as an overlay on top of the current workspace (today it is a regular workspace)
- [ ] Window animations
- [ ] `resizeactive`, `layoutmsg` (swap with master, master factor) and the remaining dispatchers
- [ ] Window rules in Hyprland's `windowrule` vocabulary
- [ ] Packaged, signed `HyprSpace.app` release build

## Building

Requires Xcode with Swift 6.4.

```
swift build              # builds .build/out/Products/Debug/HyprSpaceApp and hyprspace
swift test
```

Run the debug server from a terminal and grant that terminal Accessibility permission when prompted:

```
.build/out/Products/Debug/HyprSpaceApp
```

Documentation: [Guide](docs/guide.adoc), [Commands](docs/commands.adoc).
