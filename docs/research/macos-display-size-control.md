# macOS display-size control for Tinycast

## Question

How should Tinycast let a user switch the macOS display's apparent size among:

- `1280 × 800`
- `Default`
- `1680 × 1050`

On a Retina display these labels normally describe the **logical/“Looks like” size**, not the panel's physical pixel count. A display mode can also vary by backing-pixel dimensions, scale, refresh rate, color depth, and mode ID. Core Graphics exposes each of those properties on `CGDisplayMode`; a production implementation should not select a mode on width and height alone. [Apple: `CGDisplayMode`](https://developer.apple.com/documentation/coregraphics/cgdisplaymode)

## Recommendation

Use two stages:

1. **Prove the user story now with three Tinycast custom commands backed by `displayplacer`.** At setup time, put the display into each desired state manually, run `displayplacer list`, and save the emitted profile command. Capture the current preferred state as `Display Size: Default` rather than trying to infer what Apple means by “Default.” This is the quickest route and already gets launcher search plus optional global hotkeys from Tinycast.
2. **If this becomes a shipped Tinycast feature, implement a native `Set Display Size` command using public Core Graphics first.** Enumerate the target display's actual modes and expose only presets that exist. Save a per-display baseline mode for “Default.” Only consider private display APIs if hardware testing shows the public mode list does not expose the required Retina modes.

A Raycast-style extension is worthwhile only if the UX needs one rich picker, current-state display, multiple monitor selection, or sharing as a package. It does not provide a different macOS display-control primitive: it still calls Core Graphics through a bundled helper or invokes a utility such as `displayplacer`.

## Option 1: Tinycast custom commands plus `displayplacer`

This is the lowest-effort working path.

Tinycast custom commands are named shell commands that appear in launcher search and can have global shortcuts. Tinycast runs them using `/bin/zsh -lc` (or `-ilc` when “Load shell environment” is enabled). [Tinycast custom-command contract](https://github.com/abue-ammar/tinycast/blob/main/docs/features/custom-commands.md#execution-contract)

`displayplacer` is a command-line utility for display resolutions and layouts. Its documented workflow is:

```sh
brew install displayplacer
displayplacer list
```

It accepts either a requested resolution/scaling combination:

```sh
displayplacer "id:<display-id> res:1280x800 scaling:on"
displayplacer "id:<display-id> res:1680x1050 scaling:on"
```

or an exact mode number:

```sh
displayplacer "id:<display-id> mode:<mode-number>"
```

The stronger setup is to choose each state in System Settings, run `displayplacer list`, and copy the complete generated profile command. That preserves the exact display ID, mode, scaling, refresh rate, rotation, origin, and any multi-display arrangement instead of guessing among modes with the same logical dimensions. The project's README explicitly recommends using `displayplacer list` to create reusable profiles. [displayplacer usage and profile workflow](https://github.com/jakehilborn/displayplacer/blob/master/README.md#usage)

Suggested Tinycast entries:

| Name | Command | Shortcut example |
| --- | --- | --- |
| Display Size: 1280 × 800 | Profile emitted while this mode is active | `⌃⌥1` |
| Display Size: Default | Profile captured while the user's preferred default is active | `⌃⌥2` |
| Display Size: 1680 × 1050 | Profile emitted while this mode is active | `⌃⌥3` |

### Tradeoffs

**Advantages**

- No Tinycast code change.
- Search, aliases, favorites, and hotkeys already exist.
- Exact captured profiles handle refresh/scaling duplicates better than a bare resolution string.
- Easy to replace later without changing the user's mental model.

**Costs and risks**

- Every user must install and configure an external binary.
- Display IDs can change under some GPU/port/wake races; `displayplacer` documents persistent, contextual, and serial IDs and the associated caveats. [displayplacer display-ID notes](https://github.com/jakehilborn/displayplacer/blob/master/README.md#screenids-switching)
- `displayplacer` warns that some modes it lists do not work and may fall back to another mode. [displayplacer mode notes](https://github.com/jakehilborn/displayplacer/blob/master/README.md#notes)
- The tool is not purely public-API internally. Its header explicitly declares private `CGS*` display-mode functions, and its resolution path calls `CGSConfigureDisplayMode` before completing the configuration permanently. [displayplacer private declarations](https://github.com/jakehilborn/displayplacer/blob/c23026eb3d73000eb1a14b45d82fd6dd08c921f5/src/Header.h#L1-L32) · [displayplacer resolution implementation](https://github.com/jakehilborn/displayplacer/blob/c23026eb3d73000eb1a14b45d82fd6dd08c921f5/src/DisplayPlacer.c#L665-L741)

## Option 2: a Raycast-style Tinycast extension

An extension can present one `Set Display Size` command with three rows and show the active choice. It can invoke `displayplacer` with an argument array through a child process, or ship a small native helper.

This is technically feasible in Tinycast: its extension runtime supports Raycast `List`, actions, view and no-view commands, packaged third-party modules, Node's `child_process`, and bundled Swift helpers. [Tinycast extension architecture](https://github.com/abue-ammar/tinycast/blob/main/docs/features/extensions.md#how-it-works) · [Tinycast compatibility list](https://github.com/abue-ammar/tinycast/blob/main/website/content/docs/extensions/compatibility.md#supported)

Raycast's official `useExec` helper likewise supports running a command with a separate argument array, which is safer than interpolating a shell command string. [Raycast `useExec`](https://developers.raycast.com/utilities/react-hooks/useexec)

### When an extension earns its keep

- There should be one interactive picker rather than three launcher commands.
- The UI should show the current size and unavailable choices.
- The user needs to select among multiple displays.
- The package should be shareable across Tinycast and Raycast.
- Validation, errors, and dependency checks should be visible in the palette.

### Why it is not the best first step

The extension is presentation and orchestration, not the privileged mechanism. A `displayplacer`-backed extension still has the same install, private-API, mode, and display-ID caveats. A bundled native helper adds build, signing, and architecture work. For three fixed personal presets, three custom commands are much smaller.

## Option 3: a native Tinycast feature using public Core Graphics

This is the best long-term product implementation if the needed modes appear in the public API on supported Macs.

The public flow is:

1. Identify the intended `CGDirectDisplayID`.
2. Get its current mode with `CGDisplayCopyDisplayMode` and supported modes with `CGDisplayCopyAllDisplayModes`. Apple says the latter returns the modes the display currently supports. [Apple: current display mode](https://developer.apple.com/documentation/coregraphics/cgdisplaycopydisplaymode%28_%3A%29) · [Apple: all display modes](https://developer.apple.com/documentation/coregraphics/cgdisplaycopyalldisplaymodes%28_%3A_%3A%29)
3. Filter for the requested logical width/height, then choose deterministically among duplicates. Prefer matching the current refresh rate and Retina scale/backing-pixel ratio unless the product defines a different policy.
4. Start a transaction with `CGBeginDisplayConfiguration`, configure the chosen mode with `CGConfigureDisplayWithDisplayMode`, and finish with `CGCompleteDisplayConfiguration`. [Apple: configure with a display mode](https://developer.apple.com/documentation/coregraphics/cgconfiguredisplaywithdisplaymode%28_%3A_%3A_%3A_%3A%29) · [Apple: complete a display configuration](https://developer.apple.com/documentation/coregraphics/cgcompletedisplayconfiguration%28_%3A_%3A%29)
5. Apply with `kCGConfigurePermanently` if the user's choice should survive Tinycast quitting and future login sessions. Apple documents that permanent changes persist for future login sessions for the same user; unsupported settings can fall back to session scope. [Apple: `kCGConfigurePermanently`](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/permanently)

Avoid using `CGDisplaySetDisplayMode` for a permanent user preference. Although it is public and synchronous, Apple says that mode lasts only for the life of the calling process and reverts when the process terminates. That behavior is useful for games or previews, but surprising for a launcher setting. [Apple: `CGDisplaySetDisplayMode`](https://developer.apple.com/documentation/coregraphics/cgdisplaysetdisplaymode%28_%3A_%3A_%3A%29)

### Product decisions the API cannot make for us

**What does “Default” mean?** The public API returns the current and supported modes, but does not expose an Apple-labelled “Default for display” mode in the cited surface. Define `Default` as a baseline captured per physical display when the feature is configured. Make that wording visible, for example “Default (saved: 1440 × 900).” If the baseline is missing because the monitor is new, offer “Save current as Default.”

**Which display changes?** Reasonable policies are the built-in display, the main display, or the display containing the pointer/palette. A single-display MVP can use the main display, but the command should show the target display's name before adding multi-display support.

**What if the exact mode is absent?** Do not silently choose the nearest size. Disable the row and say that the connected display does not advertise that mode. The requested `1280 × 800` and `1680 × 1050` modes are hardware- and topology-dependent, especially while mirroring.

**How should duplicate modes be chosen?** Width and height alone are insufficient. Compare backing-pixel dimensions/scale and refresh rate, reject non-desktop modes, and keep the result deterministic. Store enough of the baseline signature to find the same mode after relaunch; the public API exposes the associated I/O display-mode ID, but the implementation should still fall back to matching the mode's full observable signature after hardware or OS changes. [Apple: I/O display-mode ID](https://developer.apple.com/documentation/coregraphics/cgdisplaymode/iodisplaymodeid)

### Suggested Tinycast UX

```text
Set Display Size

✓ Default (saved: 1440 × 900)     Built-in Retina Display
  Larger Text · 1280 × 800
  More Space · 1680 × 1050
```

Activation should close the palette, apply synchronously off the main actor, then show a success HUD. On failure, report the actual `CGError`. If the display topology changes between enumeration and commit, discard the stale selection and ask the user to retry.

## Option 4: private display APIs inside Tinycast

Private `CGS*`, CoreDisplay, DisplayServices, or private framework calls provide access closer to what System Settings and tools such as `displayplacer` use. Hammerspoon's source, for example, labels its `CGSGetCurrentDisplayMode`, `CGSConfigureDisplayMode`, and related declarations as private Core Graphics APIs with support for scaled Retina modes. [Hammerspoon private display-mode implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/screen/libscreen.m#L2336-L2483)

This can remove the external CLI dependency while preserving broad mode coverage, but it turns an undocumented OS implementation detail into Tinycast maintenance surface. Symbols, structures, and semantics can change on any macOS update. Tinycast's own feature documentation says public AppKit/CoreAudio/workspace APIs are preferred and unstable actions are routed through fixed tools, Apple Events, Accessibility, or dynamically resolved APIs only where needed. [Tinycast system-action policy](https://github.com/abue-ammar/tinycast/blob/main/docs/features/launcher.md#system-actions)

Use this only after testing shows a required preset is not available through public `CGDisplayMode` enumeration and after explicitly accepting the compatibility burden. If adopted, isolate it behind a narrow service and keep a public-API fallback.

## Option 5: BetterDisplay CLI

BetterDisplay is the most capable off-the-shelf route for unusual, virtual, or custom HiDPI modes. Its official CLI supports commands such as:

```sh
betterdisplaycli set -name=<display-name> -resolution=1280x800
betterdisplaycli displayModeList -name=<display-name>
```

The CLI requires BetterDisplay 2.2 or later to be installed and running/configured, and BetterDisplay documents CLI/per-display command integration as a Pro integration feature. [BetterDisplay CLI integration](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI) · [betterdisplaycli repository](https://github.com/waydabber/betterdisplaycli)

This is a good opt-in integration for power users who already run BetterDisplay. It is a poor default dependency for a small Tinycast feature because it adds another resident app and a possible licence requirement.

## Option 6: Shortcuts, AppleScript, or System Settings UI automation

These are wrappers or fallbacks, not preferred display-control APIs.

Tinycast already discovers and runs Apple Shortcuts through `/usr/bin/shortcuts`; Apple documents running shortcuts from the `shortcuts` command and via URL schemes. A shortcut could invoke a helper or UI script, but Shortcuts itself does not change the underlying display-control tradeoffs. [Apple: run shortcuts from the command line](https://support.apple.com/en-au/guide/shortcuts-mac/apd455c82f02/mac) · [Apple: Shortcuts URL scheme](https://support.apple.com/en-ie/guide/shortcuts-mac/apd624386f42/mac) · [Tinycast Apple Shortcuts integration](https://github.com/abue-ammar/tinycast/blob/main/docs/features/launcher.md#apple-shortcuts)

AppleScript can automate System Settings by driving its accessibility hierarchy through System Events. Apple documents that GUI scripting simulates clicks and keystrokes, requires the user to grant Accessibility access manually, and depends on inspecting a target app's UI-element hierarchy. [Apple: automating the user interface](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html)

That makes UI scripting the weakest option here: it is sensitive to macOS UI redesigns, localization, display count, navigation state, and timing, and it visibly opens System Settings. Keep it only as a proof of concept when neither a native API nor an installed display tool is available.

## Decision table

| Route | Time to prove | User dependencies | Mode coverage | Stability | UX ceiling | Recommendation |
| --- | ---: | --- | --- | --- | --- | --- |
| Tinycast custom commands + `displayplacer` | Minutes | Homebrew binary | High | Medium-low; private API underneath | Three searchable commands/hotkeys | **Best MVP** |
| Raycast-style extension + `displayplacer` | Hours | Extension + binary | High | Medium-low | Rich picker/current state | Use when the richer UI matters |
| Native public Core Graphics | Days | None | Must verify on target Macs | High | Fully native | **Best shipped feature** |
| Native private `CGS*`/framework calls | Days | None | High | Low across OS updates | Fully native | Last resort, isolate carefully |
| BetterDisplay CLI | Minutes | BetterDisplay + CLI/possibly Pro | Very high | Good as an integration | Good | Power-user opt-in |
| Shortcuts wrapper | Minutes | User-created shortcut plus a mechanism | Same as wrapped mechanism | Same as wrapped mechanism | Familiar automation surface | Useful wrapper, not core mechanism |
| System Settings UI scripting | Hours to keep working | Accessibility permission | What the UI exposes | Low | Visible and brittle | Avoid |

## Validation plan

Before product work, test the public Core Graphics route on the exact supported hardware/topologies:

1. Built-in Retina display alone.
2. External Retina/HiDPI display.
3. Non-Retina external display.
4. Mirrored and extended arrangements.
5. Dynamic refresh-rate displays.
6. Sleep/wake and unplug/replug between mode enumeration and activation.
7. Tinycast quit/relaunch and logout/login, verifying the chosen persistence scope.

The first go/no-go question is simple: do public `CGDisplayCopyAllDisplayModes` results include modes whose logical dimensions are exactly `1280 × 800` and `1680 × 1050` on the target Macs? If yes, ship the public native path. If no, decide whether the user story permits only available modes or justifies a private/helper integration.
