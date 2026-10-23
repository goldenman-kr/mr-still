# Design

## Source of truth
- Status: Active; refreshed 2026-10-22.
- Native macOS photo browser. Evidence: approved `.omx/plans/photo-viewer-implementation-plan.md`, test specification, and user's D2/D3 acceptance.
- No pre-existing UI or assets. The approved plan applies except the refinements below.

## Brand
- App display name: Mr. Still. Bundle identifier: `photoviewer.app.kryp.xyz`.
- Quiet, precise, fast. Photos dominate; controls use standard macOS appearance.
- Avoid decorative dashboards, gradients, web-like cards, and permanently black letterboxing.

## Product goals
- Browse local photos, inspect at exact pixel scale, switch instantly between browsing and unobstructed viewing.
- No editing, catalog database, automatic slideshow timer.
- Success: correct selection/zoom, responsive large-folder browsing, safe file operations.

## Personas and jobs
- A Mac owner browsing personal photo directories with keyboard and mouse.
- Open a folder or Finder image, select and compare, inspect metadata, copy/trash, print.

## Information architecture
- Browser: upper-left folder tree/path; lower-left file tools/list; right full-height viewer/status.
- Favorites is a persistent virtual directory group above Home. Directory context menus add/remove favorites and open Finder; image context menus reveal files in Finder.
- File pane includes immediate subfolders before images, with folder icons in every view. Double-click/Return opens the primary folder and synchronizes the tree. Viewer navigation includes images only. Copy/trash operations remain image-only.
- Home initially expands one level only; capability queries and asynchronous loading must not force additional expansion. External-file opening reveals its ancestors.
- Slide: viewer occupies window. Fullscreen is an overlay state preserving browser/slide origin.
- File menu: Open, Open Folder, Open Recent, Print. View menu: mode, Fit, zoom, fullscreen.

## Design principles
- Use macOS conventions: Shift range, Command additive selection, Control/right-click contextual menu.
- Zoom: Command +/−, Option+scroll, pinch where available; only viewer focus handles viewer zoom keys.
- Decimal zoom with logarithmic slider; allow very small positive Fit values. Manual entry supports fractional percentages up to 300%; no artificial 1% floor. Adaptive slider lower bound includes current Fit.
- Display percentages with at most two decimal places (2026-10-22 user refinement), trim trailing zeros; below 0.01% show `<0.01` beside the percent label. Keep full internal precision and do not round image geometry to display precision.
- Escape closes transient UI first, then fullscreen, then slide.
- Fullscreen: hovering the bottom 44pt reveals the status controls as an overlay; leaving hides them. The image canvas bounds/Fit do not change on reveal. Keep controls visible while actively editing zoom or using their popover.
- Info circle is the rightmost status control. Physical I toggles image metadata and physical F toggles fullscreen, including Korean input sources. Keep Command-F as an alias; editable text retains normal typing priority; held keys do not repeatedly toggle.
- All status controls form a trailing-aligned group; file details use the remaining space on the left. Metadata uses a scrollable group/item/value table with full values available for selection/copy.
- Double-clicking the image toggles browser and slide modes. Fullscreen double-click leaves the saved origin mode unchanged.
- Slide/fullscreen viewing uses a container outside the split view so hidden split dividers cannot draw over the photograph.

## Visual language
- Dark Aqua; canvas calibrated RGB approximately 0.10/0.11/0.13. Panels use native dark backgrounds.
- System fonts, SF Symbols with labels/tooltips, 8pt spacing, compact 28–36pt toolbars.
- 4pt dark gray dividers; path header uses a subtly lighter background than the tree. Native selection accent; subtle 2–3 backing sheets for multi-selection.
- App icon: a simple geometric photo/landscape mark, dark background and blue/teal accent, legible at small sizes; reproducible native vector drawing packaged as ICNS.
- No required motion; honor reduced motion by avoiding decorative animation.

## Components
- Thumbnail rows distribute spare width equally between leading/trailing edges and columns, recomputing on resize and view-mode changes. Partial last rows retain column alignment.
- AppKit split views, outline, collection/table, image canvas, status controls, metadata popover, standard print panel.
- Layout metrics centrally owned by window controller; core math owns minimum-size/zoom invariants.
- Empty, loading, failed, selected, disabled states are explicit.

## Accessibility
- Standard controls with accessible labels, tooltips, keyboard focus rings and VoiceOver names.
- Tree keys navigate tree; file keys navigate selection; viewer keys navigate images; text editing wins.
- Adequate dark-theme contrast; image controls remain discoverable without hover.

## Responsive behavior
- Start 1200×800pt with 360pt left pane. Left min 280pt, right min 400pt; top min 160pt, bottom min 240pt. Browser content minimum is 684×404pt including 4pt dividers.
- Width changes affect right first; reduce left only after right minimum. Height adjusts both left panels within minima.
- Slide hides left without losing its width. Return from smaller slide window grows to browser minimum. Keep both split panes installed via a stable viewer host; move only the viewer and freeze hidden split geometry during slide/fullscreen.
- Browser double-click explicitly selects the clicked item before activation; image activation uses the viewer’s slide entry, while folders navigate.
- File → 기본 이미지 앱으로 설정 requests the default application for the seven supported UTTypes only on user action. Requests run sequentially through NSWorkspace, with verified per-format results.

## Interaction states
- Folder history is shared across all panes and viewing modes, with back/forward controls before the path, Option-left/right, and mouse buttons 3/4. Preserve Option-arrow text editing. Buttons disable at history boundaries and while loading. Only successful distinct-folder navigation commits history; refreshes preserve the forward branch, new navigation replaces it. Failed loads preserve the current folder and selection. History is session-local.
- Loading: small progress indicator/status; stale asynchronous responses must never replace current selection.
- Empty: Open Folder action or descriptive no-images message. Errors explain inaccessible/corrupt files while navigation remains possible.
- Multi-selection: only current image is decoded for viewer; display count and decorative stack.
- Network volumes can be slow/offline; directory and file work run off main thread.

## Content voice
- Concise Korean UI labels; conventional menu shortcuts. File names and metadata remain original.
- Distinguish unsupported, inaccessible, and empty. Never report failed file operations as completed.

## Implementation constraints
- Swift/AppKit, Image I/O, Core Graphics. No third-party dependency. macOS 14+ target.
- Non-sandboxed personal local app; normal OS permissions still apply. Finder Quick Look remains system-provided.
- 100% means image pixels to backing pixels, independent of point layout and embedded DPI.
- Bounded thumbnail caching/concurrency. Print current image using system dialog, fit printable paper.
- Test core logic and temporary file operations, build native app, inspect screenshots and record visual verdict JSON.
- Standalone `visual-verdict` skill is absent locally; use direct screenshot review against this contract and persist evidence without claiming the unavailable skill ran.

## Open questions
- No blocking product questions. Minimum sizes/colors remain user-tunable after the first build.
- Signing verified: local Apple Development signing identity. Applications installation authorized by the user on 2026-10-22.
