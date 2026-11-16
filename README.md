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
- **Window borders.** Every window has a border. Width, rounding, and the colors of the focused and of the other
  windows are configurable (`border.*`). Colors can be gradients: `'rgba(33ccffee) rgba(00ff99ee) 45deg'`.
- **Window animations.** Windows glide to their new position when the layout changes, new windows pop in, and
  windows slide in and out when the workspace is switched (`animations.*`).
- **Move and resize with the mouse.** `mouse-drag-modifier = 'alt'`: hold the modifier and drag anywhere on a window
  with the left mouse button to move it, with the right mouse button to resize it.
- **Groups.** `togglegroup`, `changegroupactive`, `moveintogroup` and `moveoutofgroup` stack windows in one tile.
- **Pseudotiling and smart gaps.** `pseudo` keeps the own size of a window inside of its tile. `gaps.smart = true`
  removes the outer gaps when the workspace has a single tiling window.
- **Special workspace.** `togglespecialworkspace [name]` shows a scratchpad on top of the current workspace.
- **Pinned windows.** `pin` keeps a floating window visible on every workspace of its monitor.
- **Window rules.** `windowrule = ['float, class:^(Calculator)$']` in Hyprland's vocabulary. Rules: `float`, `tile`,
  `pin`, `fullscreen`, `maximize`, `pseudo`, `center`, `size`, `move` and `workspace`.
- **Hyprland dispatchers.** Bindings and the CLI accept `killactive`, `movefocus`, `movewindow`, `swapwindow`,
  `swapnext`, `focusmonitor`, `movecurrentworkspacetomonitor`, `togglefloating`, `togglesplit`, `pseudo`,
  `fullscreen (0|1)`, `fullscreenstate`, `workspace (e+1|e-1|previous|special)`, `movetoworkspace`,
  `movetoworkspacesilent`, `togglespecialworkspace`, `resizeactive`, `moveactive`, `centerwindow`, `layoutmsg`,
  `pin`, `cyclenext`, `focuscurrentorlast`, the group dispatchers and `exec`.
- **Ready-to-use config.** [hyprspace.toml](docs/config-examples/hyprspace.toml) is a complete config you can install
  as is: `cp docs/config-examples/hyprspace.toml ~/.hyprspace.toml`. It has Hyprland's default bindings with `alt` in
  place of SUPER, plus vim-style `alt-h/j/k/l` keys and layout toggles.
- **Example config.** [hyprland-like-config-example.toml](docs/config-examples/hyprland-like-config-example.toml)
  mirrors Hyprland's default bindings only.
- Config lives at `~/.hyprspace.toml` (or `${XDG_CONFIG_HOME}/hyprspace/hyprspace.toml`). The CLI is `hyprspace`.

## What macOS does not allow

Hyprland is a Wayland compositor and draws every window itself. On macOS that job belongs to the closed WindowServer,
so HyprSpace can only ask apps to move and resize through the Accessibility API. That is why:

- Animations are emulated by moving and resizing a window several times in a row. Apps that are slow to resize look
  choppy. A window that is closed can't be animated: it is already gone.
- A border is a separate click-through window that is kept right above the window it belongs to.
- Groups are stacked windows (the accordion layout). There is no tab bar.
- The special workspace is emulated with floating windows instead of a real overlay.
- Blur, shadows, custom shaders and window opacity are out of reach without disabling System Integrity Protection.

## Roadmap

- [ ] A tab bar for groups
- [ ] Workspace switch animation with several monitors
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
