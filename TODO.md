# Uji.pm Project Roadmap

A modern, declarative, asynchronous GUI toolkit for Perl 5.40+ using The Elm Architecture (TEA),
native FFI via Affix. This is a testbed for cooperative fibers via Acme::Parataxis.

## Next Up (after the current milestone)
- [x] `SpinBox` (numeric stepper; Win32 `UPDOWN` buddy overlaid on a read-only `EDIT`; driver owns the text)
- [x] `ToggleSwitch` (2-state; `BUTTON` with `BS_AUTOCHECKBOX`+`BS_PUSHLIKE`)
- [x] `ToggleButton` (sticky push style, `checked` state; same native mapping)
- [x] `LinkButton` (borderless `BS_FLAT` button, `on_click`; manifest-free `SysLink` approximation)
- [x] `ProgressBar` (determinate; `msctls_progress32` via `ICC_PROGRESS_CLASS`)
- [ ] `DatePicker`
- [x] **Multi-window app** (design ahead: several top-level `Window` nodes, one shared message loop / fiber pump, per-window vtrees reconciled independently, `WM_ACTIVATE` routing)

## Core Architecture
- [x] Unidirectional State Loop (The Elm Architecture: Model-View-Update)
- [x] Cooperative Fiber Event Pump (Acme::Parataxis & non-blocking polling)
- [x] Inter-fiber message queue via `Acme::Parataxis::Channel`
- [x] Background side-effects system (Elm `Cmd`s in dedicated fibers)
- [x] Declarative Virtual DOM (VDOM) tree representation using `perlclass`
- [x] Virtual Node Identity preservation & Reconciler diff/patching engine
- [ ] Subscriptions system (`Sub` for periodic timers, window resize events)

## Layout Engine
- [x] Pure-Perl absolute coordinate calculations (bypassing native layout quirks)
- [x] Window root client-area calculations
- [x] Vertical container (`Column`) with padding and spacing
- [x] Horizontal container (`Row`) with padding and spacing
- [x] Proportionate flexible sizing (`flex => 1`, `flex => 2`)
- [ ] **Auto-resize policy** (design decision needed: how widgets size to content & parent)
  - [x] Intrinsic sizing (measure phase: text metrics -> natural width/height)
  - [ ] Parent-driven resize: re-layout on `WM_SIZE` (already tracked under Windows driver)
  - [ ] Per-widget fit policy (`fill`, `fit`, `stretch`, `shrink`, `fixed`, `min`, `max`)
  - [ ] Constraint/min-max plumbing down the tree
- [ ] Cross-axis alignment (`stretch`, `center`, `start`, `end`)
- [ ] Scrolling and overflow clipping containers (`ScrollView`)

## Widget Set

### Implemented
- [x] `Window` (Top-level application window with title & dimensions)
- [x] `Text` (Static text label)
- [x] `Button` (Clickable push button with `on_click` event)
- [x] `TextInput` (Single-line input with two-way `on_input` binding)
- [x] `PasswordInput` (Masked single-line text; `EDIT` with `ES_PASSWORD`)
- [x] `Slider` (Range slider with `on_change` event; Win32 trackbar)

### Core Inputs (all toolkits must support)
- [x] `Checkbox` (Toggle box with `on_toggle` event)
- [x] `RadioGroup` / `RadioButton` (Exclusive selection; `on_select`)
  - Win32: `BS_AUTORADIOBUTTON` grouped with `WS_GROUP`
  - GTK4: `GtkCheckButton` inside a shared length-1 group
  - Cocoa: `NSButton` with `NSButtonTypeRadio`
- [x] `MultilineText` (Wrapping/scrollable text area; line breaks in `value`; `EDIT` `ES_MULTILINE`+`ES_AUTOVSCROLL`+`WS_VSCROLL`, always-on `multiline`)
- [x] `ComboBox` (Editable dropdown; `options => [...]`, `on_select`)
  - Win32: `COMBOBOX` with `CBS_DROPDOWNLIST` / `CBS_DROPDOWN`; items via `CB_ADDSTRING`; `CBN_SELCHANGE` / `CBN_EDITCHANGE`
  - Reconciles `options` and `value`; editable mode routes `on_input`; `on_select` falls back to typed text
  - Has-strings style fix (`CBS_HASSTRINGS`=0x200); editable caret preserved across re-renders (`CB_GETEDITSEL`/`CB_SETEDITSEL`), not forced to the end
- [x] `ListBox` (Scrollable list of options; `selection`/`on_select`)
  - Win32: `LISTBOX` with `LBS_NOTIFY|LBS_NOINTEGRALHEIGHT|LBS_HASSTRINGS`; items via `LB_ADDSTRING`; `LBN_SELCHANGE`
  - Single selection + `multiple => 1` (`LBS_MULTIPLESEL`): value/`on_select` become arrayrefs; read back via `LB_GETSELCOUNT`/`LB_GETSELITEMS`
- [x] `SpinBox` (Numeric stepper with `min`/`max`/`step`; Win32 `msctls_updown32` buddy + read-only `EDIT`)
- [ ] `DatePicker` (Calendar-based date entry)
- [x] `ToggleSwitch` / `ToggleButton` (2-state sticky push, `checked`/`on_toggle`)

### Buttons & Static Display
- [x] `ToggleButton` (Sticky push style, `checked` state)
- [x] `LinkButton` (Borderless `BS_FLAT` click target, `on_click`)
- [ ] `Image` (Loads/displays static raster from data or path)
- [ ] `Canvas` (Raw 2D drawing surface; `on_draw` callback)
- [x] `ProgressBar` (Determinate `value`; `msctls_progress32` + `PBM_*`)
- [ ] `Spinner` (Activity indicator, no value)
- [ ] `StatusText` (Subtle footer/hint text)

### Layout & Containers
- [x] `Column` + `Row` (Flex containers with padding/spacing/alignment)
- [ ] `TabPanel` (Tabbed sub-views; `panels => [...]`, `on_select`)
- [ ] `ScrollView` (Clipping + scrollable region, `orientation`)
- [ ] `SplitView` (Movable divider between two panes, `orientation`)
- [ ] `GroupBox` (Labeled visual grouping of children)
- [ ] `Spacer` (Explicit flexible whitespace, flex-aware)
- [ ] `Overlay` (Stack children on top of previous; e.g. badge on image)

### Data Display & Navigation
- [ ] `ListView` (Multi-column table; `columns =>`, `rows =>`, `on_select`)
- [ ] `TreeView` (Hierarchical data; `nodes =>`, `on_select`)
- [ ] `StatusBar` (Bottom-of-window status region)
- [ ] `Toolbar` (Row of icon/text actions)
- [ ] `Menu` / `MenuBar` (Application-level menus, accelerators)

### Polling & Dialogs (system-level)
- [ ] `FileOpenDialog` (Native file picker)
- [ ] `FileSaveDialog`
- [ ] `MessageBox` (App-modal alert/confirm)
- [ ] `PromptDialog` (Ask for a string value)
- [ ] `ColorPicker`

### Event convention (draft)
- Value widgets: `on_change` / `on_input` / `on_toggle` / `on_select`, mirroring the text field's two-way binding: the model is the reference and the reconciler pushes diffs back.
- Keyboard/mouse: to be defined alongside a `Subscriptions` system.

### Widget Properties (model-driven bindings)
- Any node prop is exposed to the model via the same three-step pattern:
  1. `field $prop : param : reader` on the node class
  2. a `can()` diff in `Uji::Reconciler::patch`
  3. a matching branch in `Uji::Driver::Win32::set_prop`
- **Implemented**
- [x] `title` on `Window` (live via `SetWindowTextW`)
- [x] `Button` `on_click`: static message hashref sent verbatim, callback invoked and its return value sent
- [x] Live window resize: `WM_SIZE` lParam (client W/H) read synchronously → re-layout
  - [x] Layout stale-bounds fix: requested geometry (`w`/`h`) vs computed bounds (`bx`/`by`/`bw`/`bh`)
  - [x] `enabled` on all widgets (`EnableWindow`)
  - [x] `visible` on all widgets (`ShowWindow`)
  - [x] `focused` on `text_input` / `password` (`SetFocus`, mount-time + live)
  - [x] `tooltip` on all widgets (shared `TOOLTIPS_CLASS32`, delete-then-add, idempotent updates)
  - [x] `readonly` on `text_input` / `password` (`EM_SETREADONLY`)
  - [x] `maxlength` on `text_input` / `password` (`EM_LIMITTEXT`)
  - [x] `step` on `slider` (`TBM_SETLINESIZE` / `TBM_SETPAGESIZE`); on `spin_box` (`UDM_SETACCEL`)
  - [x] `min`/`max` on `slider`/`spin_box`/`progress_bar` (`TBM_SETRANGE` / `UDM_SETRANGE32` / `PBM_SETRANGE32`)
  - [x] `checked` on `checkbox` / `toggle_switch` / `toggle_button` (`BM_SETCHECK`)
  - [x] `value` on `spin_box` (`UDM_SETPOS32` + driver-synced edit text) and `progress_bar` (`PBM_SETPOS`)
- **Batch 2 — Window geometry/state (live via messages, low risk)**
  - [x] `min_w` / `min_h` / `max_w` / `max_h` (`WM_GETMINMAXINFO` handled in wndproc; live re-clamp on `set_prop`)
  - [x] `centered` (compute + `_set_window_outer` `'center'` mode on mount)
  - [x] `topmost` (`SetWindowPos` → `HWND_TOPMOST` / `HWND_NOTOPMOST`)
  - [x] `minimized` / `maximized` (`ShowWindow` `SW_MINIMIZE` / `SW_MAXIMIZE` / `SW_RESTORE`)
  - [x] `resizable` (`WS_THICKFRAME` toggled at mount via style flag)
- **Common widget state (all via messages)**
  - [x] `visible` on all widgets (`ShowWindow` `SW_SHOW`/`SW_HIDE`)
  - [x] `focused` (`SetFocus`) — set at mount and reconciled on change
  - [x] `tooltip` (shared `TOOLTIPS_CLASS32` + `TTM_ADDTOOLW`; lazy-created, delete-then-add for idempotent updates)
  - [ ] `cursor` (`SetClassLongPtrW` / `WM_SETCURSOR`) — low priority, defer
- **Text/display appearance (needs theme plumbing + `WM_CTLCOLOR*`)**
  - [x] `font` / `font_size` (`WM_SETFONT`, `CreateFontIndirectW`, HFONT cache)
  - [x] foreground `color` / `background` (`WM_CTLCOLORSTATIC` / `WM_CTLCOLORBTN` / parent `WM_CTLCOLOR*`, `CreateSolidBrush` cache; no `DefWindowProcW` fall-through — it resets the DC colors the OS chose; default `GetSysColorBrush(COLOR_WINDOW/COLOR_BTNFACE)`)
  - [x] `placeholder` on inputs (grey hint while empty; driver paint handler, disappears on first keystroke)
  - [x] `align` on `Text` (`SS_CENTER` / `SS_RIGHT` / `SS_LEFT`) — mount-time style
- **Mount-time-only props (require a recreate-diff path in the reconciler)**
  - [x] `multiline` on inputs (`ES_MULTILINE` + `ES_AUTOVSCROLL` + `WS_VSCROLL`)
  - [x] `orientation` on `Slider` (`TBS_VERT`)
  - [x] `hint`/`password_char` (`ES_PASSWORD`, `EM_SETPASSWORDCHAR`)
  - [x] `Reconciler::patch` recreation path: `_mount_only_props` per node → `driver->recreate_node($id, $node)` (style baked into the window at creation; `id` preserved so registry/bindings survive) + `Driver::recreate_node`

## Resolved Bug: SpinBox arrows vanishing on hover/click (dark mode)

**Status: FIXED** (regression demo verified: arrows persist through REST/HOVER/PRESSED/RELEASED/AFTER-2nd).
**Report:** "The up/down arrows disappear when the mouse is over them" (became click-blanking too).
**Environment:** Windows dark mode (`AppsUseLightTheme=0`, `SystemUsesLightTheme=0`) + Strawberry Perl.
**Gotcha (user-taught):** the demo spin starts `enabled => 0`; arrows only render when ENABLED, so probes
must enable it first (click the "Enable editing" toggle via real `mouse_event` + `IsWindowEnabled`).

**Diagnosis:** the buddy's own hot-track/click repaints (direct-DC draws, not WM_PAINT — a
`WM_SETREDRAW` freeze did NOT stop them) repaint the face and border but drop the arrow glyphs. An
explicit `InvalidateRect+UpdateWindow` ALWAYS redraws the arrows correctly, even mid-hover (proven by
pixel maps in eg/spin_bisect_probe.pl). RAW edit+updown twins in the SAME window never self-repainted
on hover, which is why they looked "stable" — a red herring.

**The fix (in lib/Uji/Driver/Win32.pm):**
1. MOUNT: side-by-side layout — the EDIT is shrunk to `bw - SM_CXVSCROLL` and the buddy owns the right
   strip (classic Win32 spin layout). Previously the buddy OVERLAID the read-only edit; the edit sat over
   the buddy in the parent's z-order and swallowed arrow clicks (value never changed; caret stayed "in
   front"). This was the real click blocker — the user diagnosed it ("resize the text area so it's not
   100% width and leaves room for the spinner buttons"). Applied at mount AND in `move_widget`.
2. Mount-time deterministic paint in `_mount_spin_buddy` (InvalidateRect+UpdateWindow).
3. `_repaint_active_spin_arrows`, called from `poll_events` every tick: repaints any spin buddy the
   cursor is currently over, plus one repaint on the cursor-exit transition (`aux_over` flag).

**Bonus bug found during the same session:** the progress bar never filled because `PBM_SETRANGE32`
(0x0406) takes `wParam=min, lParam=max` as separate values, but the driver packed them `(max<<16)|min`
(valid only for the trackbar) — making the range 0..6,553,600 so 40 filled ~0%. Fixed at mount and in
the `min`/`max` set_prop branch. Also corrected the slider to real `TBM_SETRANGE` (0x0401, was 0x0406 —
masked by the trackbar's default 0..100 range).
VERIFIED via eg/progress_fill_probe.pl on the live demo: PBM_GETPOS 40→45 AND pixel fill 40%→44%
(dark-green fill #0F7B0F left-anchored; Uji's dark theme paints the FILL darker than the track
#E6E6E6, so a bright-pixel classifier reads it backwards — interesting for theme work later; the bar
may still LOOK empty to a user until the theme uses a bright fill on a dark track).
Both dead-ends were reverted (do NOT reintroduce): `SetWindowTheme('','')` and `UDS_HOTTRACK`.
**Regression tooling kept:** eg/spin_click_probe.pl (drives the real demo, enables the spin, real clicks,
pixel captures), eg/spin_bisect_probe.pl (in-process Uji-vs-raw comparison), eg/progress_fill_probe.pl
(pixel fill + PBM_GETPOS for progress). Deleted (misleading/BRoken): spin_click_value_probe.pl (hit-test
read "none" only because client-coord math was unverified; the z-order question was answered by the
side-by-side fix itself), progress_range_probe.pl + raw_progress_probe.pl (PBM_GETRANGE32/0x040F
READ-BACK VIA lParam POINTER does not work cross-process — SendMessageW copies the VALUE, not the
memory; by-value PBM_GETPOS is the reliable probe).

**UNRELATED bug fixed on the way:** `typedef UDACCEL` had been lost from the driver; a STALE `blib`
(let `use blib` load old code ahead of `-I lib`) masked it AND poisoned some probe iterations. **Always
`perl Build` after editing lib/; probes should NOT use `use blib`.**

---

## Post-Spin-Bug Task Queue (user-directed order; already in Widget Set sections above)

Order the user gave — do THESE next, in this order, after the spinner bug is closed:

1. **Props batch — DONE** (all lines ticked under "Widget Properties": multiline/MultilineText, orientation,
   placeholder/password_char, align, color/background, font/font_size; recreation path + regression probes shipped):
   - `multiline` on inputs (`ES_MULTILINE` 0x0004 + `ES_AUTOVSCROLL` 0x0040 + `WS_VSCROLL` 0x00200000; count as
     `MultilineText` widget too — TODO line 54)
   - `orientation` on `Slider` (`TBS_VERT` 0x0080; line 140)
   - `hint`/`password_char` on password + `placeholder` on inputs (grey hint while empty; line 136/141)
   - `align` on `Text` (`SS_CENTER` 0x1 / `SS_RIGHT` 0x2; line 137)
   - foreground `color` + `background` (`WM_CTLCOLORSTATIC`/`EDIT`/`BTN` + `CreateSolidBrush` cache; line 135)
   - `font`/`font_size` (`WM_SETFONT` + `CreateFontIndirectW` + HFONT cache; line 134)
2. **Widgets:** `StatusText` (line 73), `StatusBar` (`msctls_statusbar32` + `SB_SETTEXT`, line 87),
   `ScrollView` (line 78), `GroupBox` (`BUTTON BS_GROUPBOX` 0x7, line 80), `SplitView` (line 79),
   `TabPanel` (`SysTabControl32` + `TCN_SELCHANGE` + panel swap, line 77), `TreeView` (`SysTreeView32`, line 86),
   `Toolbar` (`ToolbarWindow32` + `TB_ADDBUTTONSW` + `WM_COMMAND`, line 88), `Menu`/`MenuBar` (`CreateMenuW`/
   `SetMenu` + `WM_COMMAND`, line 89).
3. **Dialogs:** `FileOpenDialog`/`FileSaveDialog` (`GetOpenFileNameW`/`GetSaveFileNameW` + `OPENFILENAMEW`),
   `MessageBox` (`MessageBoxW`), `PromptDialog`, `ColorPicker` (lines 92-96).

## Testing
- [x] Headless layout regression tests (`t/t_headless_layout.pl`: proves width tracks available space)
- [x] `perl -w -c` syntax gate on every change
- [x] Unit tests for the Reconciler diff engine, node fields, and container memory stability (`t/002_radio_checkbox.t`, `t/003_reconciler.t`)
- [x] Application round-trip test: click/message → model → view → reconcile → driver state (`t/004_app_flow.t`)
- [x] Real-driver integration test that drives actual HWNDs via `BM_CLICK` and asserts `BN_CLICKED` routing (`t/005_driver_click.t`)
- [x] Shared headless driver mock (`t/lib/MockDriver.pm`) so pure-logic tests never touch Win32

## Documentation
- [x] `Uji` (`lib/Uji.pod`) - pending review
- [x] `Uji::Node::Button` (`lib/Uji/Node/Button.pod`) - pending review
- [x] Remaining node classes (`lib/Uji/Node/*.pod`): Text, TextInput, Password, Slider, Checkbox, Radio, RadioGroup, Column, Row, Window
- [x] Core runtime (`lib/Uji/App.pod`, `lib/Uji/Layout.pod`, `lib/Uji/Reconciler.pod`, `lib/Uji/Driver.pod`, `lib/Uji/Node.pod`)
- [x] Platform drivers (`lib/Uji/Driver/*.pod`): `Uji::Driver::Win32`
- [x] `podchecker` gate on every documented module (all 41 `.pod` files pass)
- [x] Props-batch docs: new `lib/Uji/Node/MultilineText.pod`; updated `Uji`, `Node`, `Text`, `TextInput`, `Password`, `Slider`, `Layout`, `Reconciler`, `Driver::Win32` pods with the interactive/recreative props
- [x] Regression tools kept: `eg/driver_selftest.pl` (in-process assertions: multiline green paint, CTLCOLORSTATIC record, TBM_SETPOS, vertical drag, channel SET; 6/6), `eg/appearance_probe.pl` (cross-process: multiline EDIT present, vertical slider portrait, WM_VSCROLL on_change reaches model; 3/3, correct exit code)

## Platform Drivers
- [ ] **Windows**
  - [x] Window class registration & `PeekMessageW` loop
  - [x] Standard controls (`STATIC`, `BUTTON`, `EDIT`)
  - [x] Common controls (trackbar slider, `msctls_updown32` spin buddy, `msctls_progress32` via `InitCommonControlsEx`)
  - [x] Event routing via `WM_COMMAND` (`BN_CLICKED`, `EN_CHANGE`) + `WM_HSCROLL` (slider) + `WM_VSCROLL` (spin box)
  - [x] Standard system font application (replace default bitmap font with Segoe UI)
  - [x] Window resize handling (`WM_SIZE` -> re-layout pass)
  - [x] Checkbox / radio button mapping (`BS_AUTOCHECKBOX`=0x3, `BS_AUTORADIOBUTTON`=0x9)
  - [x] Combo/list box mapping (`CB_`, `LB_` messages, `WM_COMMAND` notifications)
  - [ ] Native dialogs (`GetOpenFileNameW`, `MessageBoxW`)
  - [ ]
- [ ] **Linux (GTK4)**
  - [ ] GLib non-blocking iteration (`g_main_context_iteration`)
  - [ ] Widget mappings (`GtkButton`, `GtkLabel`, `GtkEntry`, `GtkScale`)
  - [ ] Signal connectors via Affix C callbacks
  - [ ] Layout via `GtkBox`/`GtkGrid` or keep pure-Perl compute
- [ ] **macOS (Cocoa)**
  - [ ] Objective-C runtime bindings (`objc_msgSend`)
  - [ ] `NSApplication` non-blocking event pump (`nextEventMatchingMask`)
  - [ ] Views (`NSButton`, `NSTextField`, `NSWindow`, `NSSlider`)
- [ ] **Terminal (Cancer)**

## Resolved Bug: app does not exit when the last window is closed (WM_DESTROY never put QUIT)

**Status: FIXED** (`close_probe.pl`: `WaitForSingleObject=0 (EXITED)`; `chan_trace_probe.pl`: `[chan-put] QUIT` then `[chan-get] QUIT`; full suite 10 files / 211 tests PASS).
**Report:** "When the last (only) window is closed, the app does not exit" — window disappeared on `WM_CLOSE` but the process stayed alive (`WaitForSingleObject` → 258).
**Root cause (lib/Uji/Driver/Win32.pm):** the multi-window `WM_DESTROY` handler gates `QUIT` on `scalar(keys %surfaces) == 0`, and surfaces are looked up per-HWND via `surface_by_hwnd->{$hwnd}`. But the `WNDPROC` callback declared its first parameter as `Pointer [Void]`, and Affix hands a `Pointer` arg to a Perl callback as a **REF object whose numeric value is the SV's address — not the HWND integer** returned by `CreateWindowExW` (which is the hash key). Trace: `[mount] hwnd=0x2660C8E` vs `[wndproc] int=0x172F5AA5DF8`, `in_map=NO surface_id=undef`. So lookups always missed: `WM_DESTROY` deleted nothing and (with the surface still present) never put `QUIT`. It silently broke `WM_SIZE`/`WM_GETMINMAXINFO` mappings too.
**The fix:** type the WNDPROC first arg as `Size_t` instead of `Pointer [Void]` — Affix then delivers the HWND as a plain integer, the map resolves, and `WM_DESTROY` reaches the surfaces-count check and emits `QUIT`. `DefWindowProcW`/`SendMessageW` already accept integer HWNDs.
**Regression tests:** `t/005_driver_click.t` now posts `WM_CLOSE` to the last window and asserts exactly one `QUIT` on the channel and `surfaces` empty (would have failed pre-fix). Also `t/011_multi_window.t` covers the no-explicit-id window pairing fix.

## Resolved Bug: flex layout runs at 800px default width after the first render (buttons overflow off-window)

**Status: FIXED** (live `eg/widget_button.pl`: `+1` flexed to 225px, `Reset` visible at `(293,40)`, row flush at `360-15`; new regression subtest in `t/004_app_flow.t`; full suite 10 files / 212 tests PASS).
**Report:** "The `+1` button and tooltip button are wide enough to be split in half by the right edge of the window. The reset button is just gone off the side." Window client was ~360px wide but every child came out ~770px wide (800 − 30 of column padding).
**Root cause (lib/Uji/App.pm `_render`):** `view()` rebuilds the window node from scratch on every render, so its auto-generated id is not yet in the driver's surface map when `sync_window_bounds` runs — `patch_windows` transfers the OLD stable id onto the new node only afterwards. `sync_window_bounds` returned early (no surface record), the window node kept its zero bounds, and `Layout::compute` fell back to its `avail_w=800` default; everything was laid out 800px wide on a ~360px window. Introduced together with the window-id-transfer fix (previously windows were recreated each render, which packed real bounds along the mount path).
**The fix:** before layout, adopt the previous window's measured client bounds (`bw`/`bh`) onto the freshly-built window node; `sync_window_bounds` still refreshes a live measure when the id resolves (stable-explicit-id case), then `compute` + a `_move_all` pass place every child. Unpaired single-window apps fall back to pairing with window #0.
**Regression tests:** `t/004_app_flow.t` gained a "flex row stays inside the auto-id window after re-render" subtest (window keeps its mounted 360px width, flex `+1` fits, row ends flush) — it fails against the pre-fix code (window `bw` became 800). `t/lib/MockDriver::sync_window_bounds` now mirrors the real driver by skipping ids that were never mounted.

## Polish & Packaging
- [ ] Standard system font scaling & DPI awareness
- [ ] Dark Mode auto-detection
