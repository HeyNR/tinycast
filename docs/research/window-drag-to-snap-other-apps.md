# Other open-source references for drag-to-snap

Companion to [Drag-to-snap in Loop, Rectangle, and Tinycast](window-drag-to-snap-loop-rectangle.md). This source review covers window identity, gesture tracking, snap geometry, and previews. It records repository activity as observed on November 5, 2026. I did not run the apps or test mouse delivery, AX timing, or native tiling on macOS 26 or 27.

## Ranked shortlist

1. **Rectangle remains the best full-gesture reference.** It captures the handling-window ID at mouse down, distinguishes moves from resizes, and checks the release position before committing. Its MIT edge classifier is separable. Use public AX hit testing from the examples below to explore how much of Rectangle's target lookup can be omitted. [Rectangle gesture handling][rectangle-drag] · [Rectangle classifier][rectangle-edges]
2. **Tiler is the closest architectural reference.** It targets macOS 26 in Swift 6 with no external packages. It separates drag intent and geometry into a Core Graphics library, hit-tests the original press position via public AX when the first drag arrives, rejects resize-border presses and anchored-edge resizes, and bounds attempts to confirm movement. Its writer, diagnostics, smart zones, and optional drag-away restore are coupled to the app. It only recomputes the release target when confirming a fast drag for the first time. An already-confirmed drag uses the cached candidate. The global monitor also excludes the app's own windows. MIT, with October 2026 repository activity. [Build and dependencies][tiler-package] · [Drag intent][tiler-intent] · [Controller][tiler-drag] · [AX hit testing][tiler-ax] · [License][tiler-license] · [History][tiler-history]
3. **Loadstone has the smallest tested drag state machine.** The generic Swift tracker takes injected window lookup and geometry, delays AX resolution until eight points of travel, and polls for movement at most every 50 ms and only near a snap zone. Its click-through AppKit preview is a short standalone file. The tracker resolves at the live cursor after the threshold, treats origin changes as moves even when a resize could change the origin, and commits the last previewed target. Hit testing itself uses public AX. Its writer/history layer also has an optional private `_AXUIElementGetWindow` lookup. Its tile model imports KeyboardShortcuts, so adapt the state machine against Tinycast's own command type. The app writes undocumented WindowManager defaults at launch and restores them on quit. MIT, with October 2026 repository activity. [Tracker][load-tracker] · [Tests][load-tests] · [Monitor][load-monitor] · [Preview][load-preview] · [AX hit testing and window ID][load-ax] · [Tile type][load-tile] · [Startup and native tiling][load-startup] · [License][load-license] · [History][load-history]
4. **EpycZones has the clearest example of sharing a gesture between plain edge snap and modifier-triggered zones.** Its independently tested edge classifier checks for a neighboring display one point beyond the relevant edge. This makes a shared stretch of edge a passage when that option is enabled. The compact preview is an AppKit panel with click-through and nonactivation. Drag capture happens after threshold crossing, can fall back to the focused window, and confirms motion from origin alone. The custom-zone path rechecks on release and the fixed-edge path uses the preview's cached target. Its post-drop coordinator has its own AX observer, polling, and staging sequence. The Swift package has no external dependencies. Private CGS Space discovery supports layout assignment and sits outside the fixed-edge classifier. MIT, with October 2026 repository activity and preview releases. [Package][epyc-package] · [Edge classifier][epyc-edges] · [Classifier tests][epyc-tests] · [Drag detector][epyc-drag] · [AX targeting][epyc-ax] · [Preview][epyc-preview] · [Post-drop writes][epyc-post] · [Private Spaces APIs][epyc-spaces] · [License][epyc-license] · [Release history][epyc-releases]

For Tinycast, use Rectangle's window identity and release checks, Tiler's public-AX and resize-classification example, and Loadstone's approach to bounding AX reads. EpycZones is the reference if a distinct modifier or shared-edge passthrough becomes part of the interaction. Feed the preview and drop into Tinycast's existing placement calculation and writer. Tiler reports the native-tiling conflict through a settings notice but reads undocumented preference keys and can reapply its placement after release. Loadstone changes system settings. Apple's documented controls in Desktop & Dock are the stable reference for coexistence. [Tinycast placement and AX rules](../features/window-management.md#invariants) · [Tiler notice][tiler-notice] · [Tiler preference read][tiler-native] · [Tiler delayed write][tiler-reapply] · [Loadstone preference changes][load-native] · [Apple tiling settings][apple-settings]

## Other candidates

| Project | What the source offers and why it ranks lower |
| --- | --- |
| **HopTab** | MIT, Swift, August 2026 repository activity. Its drag service and click-through AppKit preview are compact and use Apple frameworks. The service samples AX at about 15 Hz, but repeatedly queries the frontmost app's focused window during detection, uses origin changes as evidence, and commits the cached zone. It delegates geometry and writes to the larger workspace layout service. [Drag and preview][hop-drag] · [Layout service][hop-layout] · [License][hop-license] · [History][hop-history] |
| **MacsyZones** | GPLv3, Swift with AppKit and AX, September 2026 repository activity. Useful for custom layouts and observing AX window movement. The app combines global mouse monitors with a per-app AX observer registry, private `_AXUIElementGetWindow`, and shared window and zone state. Its normal drag path spans that registry, layout windows, and resize fallback logic. The more self-contained Quick Snapper is a separate feature. [Observer and monitors][macsy-observer] · [AX ID and drag code][macsy-drag] · [Quick Snapper][macsy-quick] · [License][macsy-license] · [History][macsy-history] |
| **Zones** | MIT, Swift 6 package with Sparkle for updates, June 2026 repository activity. A concise example of a passive mouse-only session event tap and click-through zone overlay. It captures the focused window on the first drag event, lacks a window-motion check, and commits the last highlighted zone. This makes it a useful monitor reference, with weaker target validation. [Event tap][zones-tap] · [Snap controller][zones-drag] · [Overlay][zones-overlay] · [Package][zones-package] · [License][zones-license] · [History][zones-history] |
| **RectZones** | MIT, Objective-C with zero external dependencies, October 2026 repository activity. It has modifier-driven zones and a click-through preview, a listen-only HID tap for mouse and keyboard, public AX hit testing, and private CGS calls for macOS Zoom coordinate correction. The app-level drag, overlay and writes share one large implementation file. The narrower pure core is more separable, but its custom zones and Objective-C offer less reuse than the Swift edge classifiers. [README and build][rectzones-readme] · [Zoom SPI][rectzones-zoom] · [Hit testing and gesture][rectzones-drag] · [Pure core][rectzones-core] · [License][rectzones-license] · [History][rectzones-history] |
| **Swift Shift** | MIT, active Swift project with ShortcutRecorder, LaunchAtLogin and Sparkle. Relevant to modifier-driven move/resize via public AX. Its mouse tracker moves or resizes the window directly, which is a different interaction from observing a native title-bar drag and showing a drop target. [Mouse tracker][shift-mouse] · [Build dependencies][shift-build] · [License][shift-license] · [History][shift-history] |
| **Amethyst** | MIT, active Swift automatic tiler with Silica and other packages. Its mouse state machine and AX observer correlation are useful for move-versus-resize investigation. On mouse-up, a move swaps with a layout drop zone and a resize changes the layout ratio. That behavior depends on the tiling model and provides little reusable fixed-edge snap logic. The reviewed mouse-state file uses public AppKit event observation, with AX handling delegated to the rest of the app. [Mouse state][amethyst-mouse] · [Dependencies][amethyst-packages] · [License][amethyst-license] · [History][amethyst-history] |
| **AeroSpace** | MIT, active Swift 6 automatic tiler with external packages. It uses AX notifications and native window IDs via private `_AXUIElementGetWindow`, then swaps or rebinds windows in its tiling tree or updates their workspace. The mouse behavior is tightly coupled to its tree and is a poor fixed-edge preview reference. [Mouse placement][aero-mouse] · [Private API policy][aero-readme] · [Dependencies][aero-packages] · [License][aero-license] · [History][aero-history] |
| **yabai** | MIT, C, June 2026 repository activity. Its active HID tap can consume and repost events for modifier-driven window manipulation. Drops act on a binary space partitioning tree. Its broader feature set includes a scripting addition requiring partial SIP changes. Those mechanisms add substantial coupling for an opt-in passive snap observer. [Mouse tap][yabai-mouse] · [Mouse actions][yabai-actions] · [Features and requirements][yabai-readme] · [License][yabai-license] · [History][yabai-history] |
| **Tiles by Sempliva** | Relevant interaction reference for dragging to a side or top to tile. The vendor provides free binaries. I found no upstream source repository or source license for this app, so language, dependencies, API choices, and source reuse are unverified. [Vendor site][tiles] |
| **Spectacle and ShiftIt** | Historical Objective-C keyboard-placement references. Spectacle is MIT and archived, with Carthage-managed dependencies. Original ShiftIt is GPLv3 and seeking a maintainer, with an X11 build option and bundled Sparkle. The newer ShiftIt fork declares GPLv3 and advertises Swift 6 modernization, but remains keyboard-oriented. None is a strong source for a global drag observer, snap zones or preview. [Spectacle status and build][spectacle-readme] · [Spectacle license][spectacle-license] · [ShiftIt project status, build and license][oldshift-readme] · [Newer ShiftIt fork][newshift-readme] |

MIT code can be incorporated with its copyright and permission notices retained. GPLv3 and AGPLv3 permit combining and conveying code under their respective §13 provisions. The GPL portion keeps its license, the combination is subject to AGPL's network-interaction terms, and applicable notices and source-distribution requirements still apply. Tinycast's license is AGPLv3-or-later. [Tinycast license](../../LICENSE) · [MacsyZones GPLv3 text][macsy-license]

[rectangle-drag]: https://github.com/rxhanson/Rectangle/blob/0698b04de4349f806beeb2e27b1ef9ab71b537b2/Rectangle/Snapping/SnappingManager.swift#L359-L523
[rectangle-edges]: https://github.com/rxhanson/Rectangle/blob/0698b04de4349f806beeb2e27b1ef9ab71b537b2/Rectangle/Snapping/SnapEdgeDetection.swift#L1-L56
[tiler-package]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/Package.swift
[tiler-intent]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/TilerKit/SnapEngine/DragIntent.swift
[tiler-drag]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/Tiler/SnapEngine/DragSnapController.swift#L80-L242
[tiler-ax]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/Tiler/Accessibility/AccessibilityWindowProvider.swift#L35-L49
[tiler-license]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/LICENSE
[tiler-history]: https://github.com/ambicuity/Tiler/commits/main/
[tiler-notice]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/Tiler/App/AppEnvironment%2BNativeTiling.swift#L8-L23
[tiler-native]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/Tiler/Services/NativeTiling.swift#L6-L17
[tiler-reapply]: https://github.com/ambicuity/Tiler/blob/3cee48c160ea143cac3d759470e875141de895a2/Tiler/SnapEngine/DragSnapController.swift#L244-L261
[load-tracker]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/Input/DragSnapTracker.swift
[load-tests]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/LoadstoneTests/DragSnapTrackerTests.swift
[load-monitor]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/Input/EdgeDragMonitor.swift
[load-preview]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/Input/SnapPreview.swift
[load-ax]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/Core/AXWindow.swift#L63-L188
[load-tile]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/Core/Tile.swift#L1-L10
[load-startup]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/App/AppDelegate.swift#L11-L25
[load-native]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/Loadstone/Support/NativeTiling.swift
[load-license]: https://github.com/mortenbrudvik/loadstone/blob/8c01ccfb3df5538aa38a0401996fe597f1a0b2aa/LICENSE
[load-history]: https://github.com/mortenbrudvik/loadstone/commits/main/
[epyc-package]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Package.swift
[epyc-edges]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Sources/EpycZones/EdgeSnapResolver.swift
[epyc-tests]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Tests/EpycZonesTests/EdgeSnapResolverTests.swift
[epyc-drag]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Sources/EpycZones/DragDetector.swift
[epyc-ax]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Sources/EpycZones/WindowTargeting.swift#L8-L77
[epyc-preview]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Sources/EpycZones/SnapPreviewController.swift#L1-L57
[epyc-post]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Sources/EpycZones/PostDragSnapCoordinator.swift
[epyc-spaces]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/Sources/EpycZones/SpaceDetector.swift
[epyc-license]: https://github.com/ulissescomonian/EpycZones/blob/b3eb9fd19b4e59e0b9a2e1f68d620027757a4a0e/LICENSE
[epyc-releases]: https://github.com/ulissescomonian/EpycZones/releases
[apple-settings]: https://support.apple.com/guide/mac-help/mchlp1119/27/mac/27
[hop-drag]: https://github.com/royalbhati/HopTab/blob/e370062c6b94d7e70c4b6f0e519b07885a4aaf7d/HopTab/Services/DragSnapService.swift
[hop-layout]: https://github.com/royalbhati/HopTab/blob/e370062c6b94d7e70c4b6f0e519b07885a4aaf7d/HopTab/Services/LayoutService.swift
[hop-license]: https://github.com/royalbhati/HopTab/blob/e370062c6b94d7e70c4b6f0e519b07885a4aaf7d/LICENSE
[hop-history]: https://github.com/royalbhati/HopTab/commits/main/
[macsy-observer]: https://github.com/rohanrhu/MacsyZones/blob/2d5ce44a9425413036a55dec333cbec8c4cf047e/MacsyZones/App.swift
[macsy-drag]: https://github.com/rohanrhu/MacsyZones/blob/2d5ce44a9425413036a55dec333cbec8c4cf047e/MacsyZones/Macsy.swift
[macsy-quick]: https://github.com/rohanrhu/MacsyZones/blob/2d5ce44a9425413036a55dec333cbec8c4cf047e/MacsyZones/QuickSnapper.swift
[macsy-license]: https://github.com/rohanrhu/MacsyZones/blob/2d5ce44a9425413036a55dec333cbec8c4cf047e/LICENSE
[macsy-history]: https://github.com/rohanrhu/MacsyZones/commits/main/
[zones-tap]: https://github.com/gavdraper/zones/blob/f89868976ff13f0e284c2333bb91b8234eb5e1d1/Sources/ZonesApp/DragMonitor.swift
[zones-drag]: https://github.com/gavdraper/zones/blob/f89868976ff13f0e284c2333bb91b8234eb5e1d1/Sources/ZonesApp/SnapController.swift
[zones-overlay]: https://github.com/gavdraper/zones/blob/f89868976ff13f0e284c2333bb91b8234eb5e1d1/Sources/ZonesApp/OverlayWindowController.swift
[zones-package]: https://github.com/gavdraper/zones/blob/f89868976ff13f0e284c2333bb91b8234eb5e1d1/Package.swift
[zones-license]: https://github.com/gavdraper/zones/blob/f89868976ff13f0e284c2333bb91b8234eb5e1d1/LICENSE
[zones-history]: https://github.com/gavdraper/zones/commits/main/
[rectzones-readme]: https://github.com/RectZones/RectZones/blob/58ba1b21eb542ac31f7c9b86fbdbb8b6fd33282d/README.md
[rectzones-zoom]: https://github.com/RectZones/RectZones/blob/58ba1b21eb542ac31f7c9b86fbdbb8b6fd33282d/src/main.m#L187-L220
[rectzones-drag]: https://github.com/RectZones/RectZones/blob/58ba1b21eb542ac31f7c9b86fbdbb8b6fd33282d/src/main.m#L420-L700
[rectzones-core]: https://github.com/RectZones/RectZones/blob/58ba1b21eb542ac31f7c9b86fbdbb8b6fd33282d/src/rzcore.m
[rectzones-license]: https://github.com/RectZones/RectZones/blob/58ba1b21eb542ac31f7c9b86fbdbb8b6fd33282d/LICENSE
[rectzones-history]: https://github.com/RectZones/RectZones/commits/main/
[shift-mouse]: https://github.com/pablopunk/SwiftShift/blob/7108f43d75ecd69d72537c007cee2618c04cd3d4/Swift%20Shift/src/Manager/MouseTracker.swift
[shift-build]: https://github.com/pablopunk/SwiftShift/blob/7108f43d75ecd69d72537c007cee2618c04cd3d4/Swift%20Shift.xcodeproj/project.pbxproj
[shift-license]: https://github.com/pablopunk/SwiftShift/blob/7108f43d75ecd69d72537c007cee2618c04cd3d4/LICENSE
[shift-history]: https://github.com/pablopunk/SwiftShift/commits/main/
[amethyst-mouse]: https://github.com/ianyh/Amethyst/blob/04463970f7e93af2d20a26c9063760fa5cb227f0/Amethyst/Model/MouseState.swift
[amethyst-packages]: https://github.com/ianyh/Amethyst/blob/04463970f7e93af2d20a26c9063760fa5cb227f0/Amethyst.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
[amethyst-license]: https://github.com/ianyh/Amethyst/blob/04463970f7e93af2d20a26c9063760fa5cb227f0/LICENSE.md
[amethyst-history]: https://github.com/ianyh/Amethyst/commits/development/
[aero-mouse]: https://github.com/nikitabobko/AeroSpace/blob/bc6be84ab7d6ad60a3661833635912f72707abbf/Sources/AppBundle/mouse/moveWithMouse.swift
[aero-readme]: https://github.com/nikitabobko/AeroSpace/blob/bc6be84ab7d6ad60a3661833635912f72707abbf/README.md#L120-L128
[aero-packages]: https://github.com/nikitabobko/AeroSpace/blob/bc6be84ab7d6ad60a3661833635912f72707abbf/Package.swift
[aero-license]: https://github.com/nikitabobko/AeroSpace/blob/bc6be84ab7d6ad60a3661833635912f72707abbf/LICENSE.txt
[aero-history]: https://github.com/nikitabobko/AeroSpace/commits/main/
[yabai-mouse]: https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/mouse_handler.c
[yabai-actions]: https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/event_loop.c
[yabai-readme]: https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/README.md
[yabai-license]: https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/LICENSE.txt
[yabai-history]: https://github.com/asmvik/yabai/commits/master/
[tiles]: https://www.sempliva.com/tiles/
[spectacle-readme]: https://github.com/eczarny/spectacle
[spectacle-license]: https://github.com/eczarny/spectacle/blob/e75c341ec2cba179c1bb8aa726a870c4132207df/LICENSE.md
[oldshift-readme]: https://github.com/fikovnik/ShiftIt/blob/fb7699aa491a6b81656f152f74b638bb6f9514eb/README.md
[newshift-readme]: https://github.com/citadelgrad/ShiftIt/blob/15bdcf1e1c205f3b5416d6ef944cde7b3ebc74da/README.md
