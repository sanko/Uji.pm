# Uji.pm Project Roadmap

A modern, declarative, asynchronous GUI toolkit for Perl 5.40+ using The Elm Architecture (TEA),
native FFI via Affix. This is a testbed for cooperative fibers via Acme::Parataxis.

## Next Up (current frontier — recommended order)

The props batch, core + data widgets, dialogs, runtime menu mutation, the UTF-8 boundary, and the
subscriptions system are all shipped (see the Widget Set, Platform Drivers, and Resolved Bug sections
below). Candidates, roughly in recommended order:

- [x] **Auto-resize / fit policy**: per-widget `fit`/`fit_w`/`fit_h` (`fill`/`content`/`fixed` + aliases),
      per-node `min_w`/`min_h`/`max_w`/`max_h` clamps, and `flex` now growing leaves along the main axis;
      listed as DONE in Layout Engine below.
- [ ] **Toolbar icons/labels** (lines 76-101): `TB_SETIMAGELIST`/`CImageList` + a `WIC`/`GDI+` raster
      loader so toolbar buttons stop rendering blank — this unlocks `Image` too.
- [x] **`ListView`** (multi-column table; `SysListView32` `LVM_*` report-view, columns/rows/selection +
      `multiple`/`full_row_select`/`grid_lines`/`header`) — shipped this milestone (see below).
- [ ] **`DatePicker`** (`SysDateTimePick32` + `DTM_*`) — small and self-contained.
- [ ] **Small widgets:** `Spinner` (activity indicator), `Spacer`, `Overlay`, `Canvas` (`on_draw`).
- [ ] **Dark Mode auto-detection + DPI awareness** (lines 306-307).
- [ ] Live sanity pass on `eg/widget_scroll_view.pl` (close out the deferred ScrollView note, lines 297-304).
- [ ] **More subscription sources** on the `Sub` machinery: focus/blur, close-request, and keyboard chords
      (today only `sub_interval` and `sub_on_resize` exist).

### Recently completed (this milestone)
- [x] **`ListView`** (`SysListView32` report view): `list_view` node with `value`/`columns` (`{label,width}`,
      width measured by default)/`rows` (cell arrayrefs or `{value=>, columns=>[]}`)/`on_select` plus
      mount-only `multiple`/`full_row_select`/`grid_lines`/`header`. Columns via `LVM_INSERTCOLUMNW`,
      first-cell rows via `LVM_INSERTITEMW`, later cells via `LVM_SETITEMW` (NOT `LVM_SETITEMTEXTW`,
      which silently no-ops on subitems); selection via `LVM_SETITEMSTATE` (`LVIF_STATE`/`LVIS_SELECTED`,
      `LVM_ENSUREVISIBLE`), multi-select reads the native selection back via `LVM_GETITEMCOUNT`/
      `LVM_GETITEMSTATE`, `LVN_ITEMCHANGED` routed through a driver-side slot table with programmatic
      echo suppressed. Hand-packed `LVCOLUMNW` (72B) / `LVITEMW` (88B) for Win64. See
      `lib/Uji/Node/ListView.pm`, `t/025_list_view.t` (24 subtests), `eg/widget_list_view.pl`, and the
      "Resolved Bug: list_view LVM_* constants and LVITEMW alignment" section below.
- [x] **Subscriptions system** (`Sub`): declarative message sources reconciled by key after every render.
      `sub_interval($ms, $msg)` (periodic timer; phase preserved across renders) and `sub_on_resize($msg)`
      (translated from the reserved platform `RESIZE` event) delivered through `update` like any other
      message. New `lib/Uji/Sub.pm` + `lib/Uji/Sub.pod`, `subscriptions =>` callback on `Uji::App`,
      `sub_interval`/`sub_on_resize` exports, `t/022_subscriptions.t` (9 subtests), `eg/widget_subscriptions.pl`.
      Also pumps synchronously during the frame-drag modal loop (see the resolved-bug note below), so timers and
      redraws no longer freeze while resizing/moving the window.
- [x] **Fit / auto-resize policy** (shipped this milestone): per-widget size policy on every node.
      `fit`/`fit_w`/`fit_h` take `fill` (aliases `stretch`), `content` (`fit`/`shrink`), or `fixed`; a numeric
      `w`/`h` stays fixed; `min_w`/`min_h`/`max_w`/`max_h` now exist on the base node (Window inherits them) and
      clamp the computed box per axis, plumbing up and down the tree; `flex` no longer degrades to intrinsic
      height on vertical axes. New base fields + `fit_policy` in `lib/Uji/Node.pm`, size resolution in
      `lib/Uji/Layout.pm` (`_natural`, `_clamp`, policy-aware `compute`/`_layout_flex`/`_layout_group_box`),
      Reconciler's min/max diff gated to windows, docs in `Node.pod`/`Layout.pod`, `t/023_fit_policy.t`
      (8 subtests), `eg/widget_fit_policy.pl`.
- [x] **Cross-axis alignment**: `align_w`/`align_h` on every node (`'start'`/`'center'`/`'end'`/`'stretch'`),
      offsetting the sub-layout origin by a fraction of the freed cell space before recursing (whole subtree
      shifts together); auto-dies on unknown values. `Layout::_cross_size` mirrors compute()'s per-axis rule;
      applied in `_layout_flex` + `_layout_group_box`. Docs in `Node.pod`/`Layout.pod`, `t/024_align.t`
      (7 subtests), demo rows added to `eg/widget_fit_policy.pl`. Named per-axis to avoid clashing with
      Text/StatusText's existing `align` text prop.
- [x] `SpinBox`, `ToggleSwitch`, `ToggleButton`, `LinkButton`, `ProgressBar`
- [x] **Multi-window app** (several top-level `Window` nodes, one shared message loop / fiber pump,
      per-window vtrees reconciled independently, `WM_ACTIVATE` routing)
- [x] Dialogs: `FileOpenDialog`, `FileSaveDialog`, `MessageBox`, `PromptDialog`, `ColorPicker`
- [x] Runtime menu-bar mutation (`Reconciler` diff of `menu_bar`; `MenuBar` snapshots items at construction)
- [x] Unicode text across the `WString` boundary (`utf8everywhere`) + per-instance window classes
- [ ] `DatePicker` (moved to the frontier list above)

## Core Architecture
- [x] Unidirectional State Loop (The Elm Architecture: Model-View-Update)
- [x] Cooperative Fiber Event Pump (Acme::Parataxis & non-blocking polling)
- [x] Inter-fiber message queue via `Acme::Parataxis::Channel`
- [x] Background side-effects system (Elm `Cmd`s in dedicated fibers)
- [x] Declarative Virtual DOM (VDOM) tree representation using `perlclass`
- [x] Virtual Node Identity preservation & Reconciler diff/patching engine
- [x] Subscriptions system (`Sub` for periodic timers, window resize events) — see `lib/Uji/Sub.pm`,
      `t/022_subscriptions.t`; reconciled by key after each render, delivered through `update`

## Layout Engine
- [x] Pure-Perl absolute coordinate calculations (bypassing native layout quirks)
- [x] Window root client-area calculations
- [x] Vertical container (`Column`) with padding and spacing
- [x] Horizontal container (`Row`) with padding and spacing
- [x] Proportionate flexible sizing (`flex => 1`, `flex => 2`)
- [x] Auto-resize policy (design decision needed: how widgets size to content & parent) -- SHIPPED this
      milestone (see "Recently completed" above)
  - [x] Intrinsic sizing (measure phase: text metrics -> natural width/height)
  - [x] Parent-driven resize: re-layout on `WM_SIZE`
  - [x] Per-widget fit policy (`fill`, `fit`, `stretch`, `shrink`, `fixed`, `min`, `max`)
  - [x] Constraint/min-max plumbing down/up the tree
- [x] Cross-axis alignment (`stretch`, `center`, `start`, `end`) -- SHIPPED this milestone (see "Recently
      completed" above): `align_w`/`align_h` on every node
- [x] Scrolling and overflow clipping containers (`ScrollView`)

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
- [x] `StatusText` (Subtle footer/hint text)

### Image & icon loading (future: drives `Toolbar` icons + `Image` widget + `ListView`/`TreeView`/menu glyphs)
- [ ] Icon loader + `CImageList` plumbing for `TB_SETIMAGELIST` so toolbar buttons can show icons (needed to
      close the toolbar blank-button gap above)
- [ ] SVG loader/decode (Win32 has no native rasterizer; options: bundled pure-Perl decoder, `resvg`/`librsvg`
      via FFI, or `Affix` bindings to `WIC`/`GDI+`)
- [ ] PNG decode via `WIC` (`IWICImagingFactory/D2D`) or `GDI+` for `Image` + icon paths
- [ ] Fallback: draw simple glyph icons ourselves (spin-button style, per-widget) without external images
- [ ] Decide `Image` node API (`src => 'file.png' | 'data:image/png;base64,…'`, `fit`/`fill`/`scale` policy)

### Layout & Containers
- [x] `Column` + `Row` (Flex containers with padding/spacing/alignment)
- [x] `TabPanel` (Tabbed sub-views; `panels => [...]`, `on_select`)
- [x] `ScrollView` (Clipping + scrollable region, `orientation`)
- [x] `SplitView` (Movable divider between two panes, `orientation`)
- [x] `GroupBox` (Labeled visual grouping of children)
- [ ] `Spacer` (Explicit flexible whitespace, flex-aware)
- [ ] `Overlay` (Stack children on top of previous; e.g. badge on image)

### Data Display & Navigation
- [x] `ListView` (Multi-column table; `columns =>`, `rows =>`, `on_select`, `multiple`/`full_row_select`/`grid_lines`/`header`; `SysListView32` `LVM_*` report view with a driver-side slot table for `LVN_ITEMCHANGED` routing) - see `lib/Uji/Node/ListView.pm`, `t/025_list_view.t`, `eg/widget_list_view.pl`
- [x] `TreeView` (Hierarchical data; `nodes =>`, `on_select`)
- [x] `StatusBar` (Bottom-of-window status region)
- [x] `Toolbar` (Row of icon/text actions)
- [ ] **Follow-up needed:** toolbar items render with NO ICONS and the button LABEL TEXT is not visible
      (`TBSTYLE_LIST` + `I_IMAGENONE` buttons; `TB_ADDSTRINGW` string ids are assigned and verified in tests,
      but the live demo shows blank buttons). Needs a live `eg/widget_toolbar.pl` visual pass, likely an
      image-list + toolbar icon plumbing fix. See the "Image & icon loading" work item below.
- [x] `Menu` / `MenuBar` (Application-level menus; window-frame menu bar, recursive submenus,
      separators, checked/greyed items, `WM_COMMAND` routing via the shared 0x4000+ idCommand
      allocator. No accelerators yet — main menu only. See
      `lib/Uji/Node/MenuBar.pm` + `lib/Uji/Node/MenuBar.pod`, `t/018_menu_bar.t`, `eg/widget_menu_bar.pl`.)

### Polling & Dialogs (system-level)
- [x] `FileOpenDialog` (Native file picker)
- [x] `FileSaveDialog`
- [x] `MessageBox` (App-modal alert/confirm)
- [x] `PromptDialog` (Ask for a string value)
- [x] `ColorPicker`

### Event convention (draft)
- Value widgets: `on_change` / `on_input` / `on_toggle` / `on_select`, mirroring the text field's two-way binding: the model is the reference and the reconciler pushes diffs back.
- Time / platform events: declared via the `subscriptions` callback (`Uji::sub_interval`, `Uji::sub_on_resize`) and delivered through `update`; see `lib/Uji/Sub.pod`.
- Keyboard/mouse sub-events (focus, key chords): still to be defined; the `Sub` reconciliation machinery is the intended home.

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
  - [x] `min_w` / `min_h` / `max_w` / `max_h` (`WM_GETMINMAXINFO` handled in wndproc; live re-clamp on `set_prop`;
        now base-node fields so every widget can carry per-axis clamps -- the driver branch stays window-only)
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
    *TreeView is done: `SysTreeView32` + `TVM_INSERTITEMW` + `TVN_SELCHANGED` + slot table + Reconciler diff of
    `nodes`/`expanded`; see `lib/Uji/Node/TreeView.pm`, `t/016_tree_view.t`, `eg/widget_tree_view.pl`.*
    *Toolbar is done: `ToolbarWindow32` + `TB_ADDBUTTONSW` + `TB_ADDSTRINGW` + `WM_COMMAND` routing via driver-wide
    `idCommand` counter (0x4000+) + Reconciler diff of `buttons`; see `lib/Uji/Node/Toolbar.pm`,
    `t/017_toolbar.t`, `eg/widget_toolbar.pl`.*
    *Menu/MenuBar is done: `CreateMenu`/`CreatePopupMenu`/`AppendMenuW` (MF_POPUP/MF_STRING/MF_SEPARATOR/
    MF_CHECKED/MF_GRAYED) + `SetMenu` + `DrawMenuBar` + `WM_COMMAND` routing sharing the same 0x4000+
    idCommand allocator + Reconciler diff of the window's `menu_bar` items via `set_prop('menu_bar')`; attached
    before client-area measurement so the layout sees the reduced rect. See `lib/Uji/Node/MenuBar.pm`,
    `t/018_menu_bar.t`, `eg/widget_menu_bar.pl`. No accelerators yet.*
3. **Dialogs:** `FileOpenDialog`/`FileSaveDialog` (`GetOpenFileNameW`/`GetSaveFileNameW` + `OPENFILENAMEW`),
   `MessageBox` (`MessageBoxW`), `PromptDialog`, `ColorPicker` (lines 92-96).

## Resolved Bug: list_view `LVM_*` constants and `LVITEMW` alignment

**Status: FIXED.** `t/025_list_view.t` 24/24 PASS; full suite 24 files / 491 tests PASS.

**Report:** the first `t/025_list_view.t` run crashed with an access violation (0xC0000005) inside a
`perl -w -c` clean build; after a fix it "ran" but reported column width 0, empty subitem text, and no
native selection, all failing.

**Root causes:**
1. **`LVITEMW` pack misaligned.** `state`/`stateMask` sit at offsets 12/16 (NOT 16/20) with `pszText`
   at 24 and `lParam` at 40 (no pad between `iImage` and `lParam`). The first template inserted a `x4`
   after `iSubItem`, so the control read `iSubItem` as `state`, garbage as `pszText`, and dereferenced a
   bogus text pointer — the access violation. The corrected 88-byte template is
   `'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4'`.
2. **Wrong `LVM_*` column constants.** `LVM_GETCOLUMNWIDTH` is `0x101D` (`LVM_SETCOLUMNWIDTH` `0x101E`,
   `LVM_DELETECOLUMN` `0x101C`, `LVM_GETCOLUMNW` `0x105F`, `LVM_GETCOLUMNCOUNT` `0x105C` was actually
   `LVM_GETFOCUSEDGROUP`). Using `0x1065`/`0x1064` for the width getter/setter silently no-op'd: columns
   inserted (the header reported them via `HDM_ITEMCOUNT`) but every readback returned 0.
3. **`LVM_SETITEMTEXTW` no-ops on subitems > 0.** Setting cell text for columns after the first
   returned FALSE and stored nothing for every style/mask/wParam variation. `LVM_SETITEMW` works, so the
   driver populates later cells with it.

**The fix:** corrected struct template everywhere (driver `_populate_listview`/`_select_listvalue` and the
test's readback), the real column-message constants, and switching cell writes to `LVM_SETITEMW`. As a
probe bonus, subitem-text round-trips only work when the destination column exists, and a real user click
updates the native selection *before* `LVN_ITEMCHANGED` — the multi-select test now simulates that
ordering. Handy truth: `Affix::raw(ptr, len)` reads control-copied buffers back, while Affix `'void*'`
casts do not parse; and the old `0x105C` GETCOLUMNCOUNT mistake first surfaced as "columns inserted but
colcount=0".

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
- [x] `podchecker` gate on every documented module (all `.pod` files pass)
- [x] Subscriptions docs: new `lib/Uji/Sub.pod` (`sub_interval` / `sub_on_resize`, identity rules); `Uji`/`Uji::App` pods gained a Subscriptions section and `subscriptions` param; new `eg/widget_subscriptions.pl` demo
- [x] Fit-policy + alignment docs: `Node.pod` got `fit`/`fit_w`/`fit_h`, `min*`/`max*`, and `align_w`/`align_h`
      params plus samples; `Layout.pod` got a "fit policy" + "cross-axis alignment" section, the `$main` compute
      arg, `_natural`/`_cross_size`, and updated `_layout_flex`/`_intrinsic` notes; new `eg/widget_fit_policy.pl`
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
  - [x] Native dialogs (`GetOpenFileNameW`, `GetSaveFileNameW`, `MessageBoxW`, `ChooseColorW`, `prompt_dialog`) - see `t/020_dialogs.t`
  - [x] Runtime menu-bar mutation (`Reconciler` diffs the window's `menu_bar` items; `MenuBar` snapshots items at construction so in-place model edits are detected) - see `t/018_menu_bar.t` section 6
  - [x] Unicode text (`utf8everywhere`: drivers normalise UTF-8 octets / characters via `_nz` at the `WString` boundary; unique per-instance window classes) - see `t/021_utf8_text.t`, `lib/Uji/Driver.pod/Text and Unicode`
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

## Resolved Bug: `prompt_dialog` OK/Cancel did nothing (window-class registration collision)

**Status: FIXED.** `t/020_dialogs.t` 34/34 (new test 34: a *second* driver instance runs and closes its own
prompt); full suite 20 files / 443 tests PASS.
**Report:** in the live dialogs demo the prompt's OK and Cancel buttons "never closed" the dialog.
**Root cause (lib/Uji/Driver/Win32.pm):** window-class registration is process-global per class *name*.
`RegisterClassExW` silently no-ops when a name already exists, and the registered wndproc closure captures
the FIRST driver to `init()`. Two live drivers (an app plus a `$drv` used only for dialogs) therefore routed
every message for the second driver's windows into the first driver's state; the second driver's
`$prompt_done` flag was never set, so the modal pump never exited.
**The fix:** each driver instance registers uniquely-suffixed custom classes (`UjiWindowClass1`,
`UjiViewportClass2`, `UjiDividerClass3`, `UjiPromptClassN`, …), so instances never share a wndproc. The
class-name assertions in `t/012_widget_queue.t` / `t/014_split_view.t` were relaxed to `^Uji…Class`.
**Bonus fix (same session):** `_ctrl_msg` returned `(1, undef)` for consumed `WM_COMMAND` messages. That
undef LRESULT reached Affix's XS wndproc bridge once per notification (fired by `EN_UPDATE`/`EN_CHANGE` when
an `EDIT` with initial text is created *before* it is registered), producing "Use of uninitialized value in
subroutine entry". Now returns `(1, 0)`; a pre-existing `no warnings 'uninitialized'` workaround in `t/012`
is no longer needed for it.

---

## Resolved Bug: subscriptions/view freeze while dragging the window frame (modal-loop suspension)

**Status: FIXED.** `t/022_subscriptions.t` 9/9 (new subtest "the synchronous modal pump ticks and renders
inline"); full suite 21 files / 452 tests PASS.
**Report:** in `eg/widget_subscriptions.pl` the elapsed clock never updated while dragging the window frame,
then "snapped" to the correct value on release; nothing else in the window redrew during the drag either.
**Root cause:** frame move/resize drops Windows into its own modal loop (`WM_ENTERSIZEMOVE` →
`WM_EXITSIZEMOVE`). The loop dispatches messages to the window procedure, but it does **not** return to the
app's `PeekMessageW` pump, so both cooperative fibers (the poll/tick fiber *and* the render fiber) are
suspended for the whole drag. `WM_SIZE` still re-laid-out the tree synchronously via the resize handler, but
no timer ever fired and no `_drain_and_render` ran, so the model/view never advanced.
**The fix:**
1. `Uji::Driver::Win32` affixes `SetTimer`/`KillTimer` and a `$on_modal_pump` hook (`set_modal_pump`);
   `WM_ENTERSIZEMOVE` arms timer id 1 (16 ms), `WM_EXITSIZEMOVE` kills it, and `WM_TIMER` invokes the pump.
   Windows *does* dispatch `WM_TIMER` inside the modal loop, unlike our fiber pump.
2. `Uji::App::_pump_modal` ticks the subscriptions, and if the channel is non-empty drains + folds +
   re-renders **inline** (a synchronous equivalent of one event-loop pass). `run()` registers it with the
   driver. The prompt-dialog modal pump calls the same hook, so timers keep running behind a prompt too.
**Regression test:** `t/022` forces a due interval, calls `_pump_modal`, and asserts the model advanced and
the view's label updated without any fiber loop.

---

## Resolved Bug: flex layout runs at 800px default width after the first render (buttons overflow off-window)

**Status: FIXED** (live `eg/widget_button.pl`: `+1` flexed to 225px, `Reset` visible at `(293,40)`, row flush at `360-15`; new regression subtest in `t/004_app_flow.t`; full suite 10 files / 212 tests PASS).
**Report:** "The `+1` button and tooltip button are wide enough to be split in half by the right edge of the window. The reset button is just gone off the side." Window client was ~360px wide but every child came out ~770px wide (800 − 30 of column padding).
**Root cause (lib/Uji/App.pm `_render`):** `view()` rebuilds the window node from scratch on every render, so its auto-generated id is not yet in the driver's surface map when `sync_window_bounds` runs — `patch_windows` transfers the OLD stable id onto the new node only afterwards. `sync_window_bounds` returned early (no surface record), the window node kept its zero bounds, and `Layout::compute` fell back to its `avail_w=800` default; everything was laid out 800px wide on a ~360px window. Introduced together with the window-id-transfer fix (previously windows were recreated each render, which packed real bounds along the mount path).
**The fix:** before layout, adopt the previous window's measured client bounds (`bw`/`bh`) onto the freshly-built window node; `sync_window_bounds` still refreshes a live measure when the id resolves (stable-explicit-id case), then `compute` + a `_move_all` pass place every child. Unpaired single-window apps fall back to pairing with window #0.
**Regression tests:** `t/004_app_flow.t` gained a "flex row stays inside the auto-id window after re-render" subtest (window keeps its mounted 360px width, flex `+1` fits, row ends flush) — it fails against the pre-fix code (window `bw` became 800). `t/lib/MockDriver::sync_window_bounds` now mirrors the real driver by skipping ids that were never mounted.

## Known Bugs (deferred)

Both ScrollView live-window issues are believed **fully fixed** (see the two Resolved Bug sections
at the end): the geometry fix openend the gutters so scrollbars are visible and hit-testable;
`_apply_scroll` invalidates every moved content control before repainting; `_wheel_target` is now
correct over both the viewport and its gutter scrollbars. An interactive repro pass on
`eg/widget_scroll_view.pl` was not completed before these fixes landed; a live sanity check is
still recommended to close them out.

- [ ] Standard system font scaling & DPI awareness
- [ ] Dark Mode auto-detection
- [x] **Regression:** `min_w`/`min_h`/`max_w`/`max_h` no longer restrict live MOUSE resizing of the window
      **RESOLVED.** Root cause: `update_registry` refreshed the registry record's node but NOT the surface
      record's `node`, while `WM_GETMINMAXINFO` resolves via `$surfaces->{id}{node}` — so constraints added
      or changed after mount were never seen by drag-resize. Fix: `update_registry` now keeps the surface
      node current too. Also: `SW_MAXIMIZE` (mount + `set_prop`) is refused whenever any min/max constraint
      is set (a fullscreen window bypasses track clamps). Coverage: `t/019_minmax.t` 12 tests.

---

## Resolved Bug: TabPanel widgets blank until moused over (SysTabControl32 z-order occlusion)

**Status: FIXED.** In-process probe (`t/dbg_paint_probe.pl`) shows SysTabControl32 at the BOTTOM of the
z-order after `_apply_tab` and every panel widget painting real ink; full suite 14 files / 335 tests PASS.
**Report:** on a freshly shown tab, all widgets are invisible/blank until the mouse moves over them, at
which point they flicker in one by one.
**Root cause (three Win32 mechanisms interacting):**
1. **Inverted sibling z-order.** New `WS_CHILD` windows default to the BOTTOM of the parent's z-order.
   The tab control is created first, so it ends up at the TOP, sitting over the panel widgets. Its
   opaque body (BTNFACE fill) covers them in every WM_PAINT; a mouse-over forces each widget's own
   repaint, which is why they "appear" one at a time as the cursor crosses them.
2. **Missing `WS_CLIPSIBLINGS` (0x04000000)** on the tab and the sibling widgets: Windows clips
   overlapping sibling windows while painting/erasing, but only when that style is present.
3. **Redundant `TCM_SETCURSEL` on click.** After a user click flips visibility via `TCN_SELCHANGE`, the
   next TEA reconcile diff issues `set_prop('index')` which unconditionally re-sent `TCM_SETCURSEL`,
   triggering a fresh tab repaint over the just-shown controls.
**The fix (lib/Uji/Driver/Win32.pm):**
1. `WS_CLIPSIBLINGS` (0x04000000) added to EVERY control style in `_mount_node` (buttons, statics,
   edits, sliders, spin buddies, check/radio, combos, lists, status bar, group box, scroll view +
   native scrollbars, split divider, and the tab control itself: `0x50…`→`0x54…`, `0x52…`→`0x56…`).
2. SysTabControl32 forced to `HWND_BOTTOM` right after creation (before `TCM_SETCURSEL`, which is what
   raises it), in `move_widget`, and inside `_apply_tab` (hide inactive panels first → set tab to
   HWND_BOTTOM + `UpdateWindow` → show active panel).
3. `_set_branch_visible(…, 1)` now brings each shown control to `HWND_TOP` and forces
   `InvalidateRect`+`UpdateWindow` so freshly exposed panels paint synchronously, not on first hover.
4. `set_prop('index')` only sends `TCM_SETCURSEL` when `TCM_GETCURSEL` differs, killing the redundant
   selection repaint on user clicks.

---

## Resolved Bug: min/max window constraints stopped clamping mouse drags

**Status: FIXED.** `t/019_minmax.t` 12/12 PASS; full suite PASS.
**Root cause:** `Uji::Driver::Win32::update_registry` refreshed the registry record's `node` (and
`$main_vnode`) but NOT `$surfaces->{id}{node}`, while `WM_GETMINMAXINFO` resolved the live window
node from the surface record. Constraints set at mount worked, but constraints added or changed by a
later reconcile never reached drag-resize.
**The fix:** `update_registry` now also keeps `$surfaces->{ $node->id }{node}` current for windows. As
a bonus, `SW_MAXIMIZE` is refused (at mount and via `set_prop('maximized')`) whenever any min/max
constraint is defined, since a fullscreen window bypasses `WM_GETMINMAXINFO` track clamps entirely.

---

## Resolved Bug: SplitView divider drifted from its relative position on window resize

**Status: FIXED.** `t/014_split_view.t` 34/34 PASS incl. a proportional-resize subtest (the divider
ratio is preserved across a `WM_SIZE`-driven re-layout); full suite PASS.
**Root cause:** `split_position` re-resolved the divider from the live `node->divider` (a pixel offset)
on every layout pass, so a window resize jumped the divider instead of keeping its relative fraction.
**The fix:** each placement records `div_track` (available length) and `div_ratio` (divider/track) on
the registry record. When a later layout sees the track changed, it recomputes `divider = ratio * track`
instead of reusing the stale pixel offset; drag + `set_prop('divider')` update the stored ratio too.
`_place_divider` maintains the same ratio guidance for the divider strip.

---

## Resolved Bug: ScrollView geometry — scrollbar double-subtracted / hidden under the viewport, content collapse, clipping

**Status: FIXED.** Geometry probe (`t/dbg_scroll_geom.pl`): viewport shrinks to `bw-gutter`=311 (node 328),
vertical bar sits adjacent at the right edge spanning the full visible height, `page_v`=viewport height,
no spurious horizontal bar; full suite 14 files / 335 tests PASS.
**Report:** in `eg/widget_scroll_view.pl` the vertical scrollbar was invisible / unclickable, and scrolled
content had stale/clipped pixels; a vertical scroll view's content column also collapsed to the width of
its narrowest child.
**Root causes:**
1. **`_place_scrollbars` double-subtracted the scrollbar width.** The vertical bar X was
   `bx + vW - gut_w - sbw`; with `gut_w == sbw` that placed the bar at `bx + vW - 2*sbw`, i.e. INSIDE the
   viewport's bounding box. The horizontal bar likewise overlapped the viewport.
2. **The opaque viewport covered the bars.** `move_widget` sized the viewport to the FULL node rect; the
   bars were lazy-created siblings at the BOTTOM of the z-order, so the viewport painted over them
   (same z-order trap as the tab control).
3. **`Layout::_intrinsic` dropped container padding.** `column`/`row`/`group_box` tracked only the max
   child dimension and added no `pad*2` to the outer axis, so `_layout_flex`'s `inner = outer - pad*2`
   squeeze clipped every child by 2×pad.
4. **ScrollView content collapsed to its intrinsic width** instead of spanning the viewport.
5. **`SB_THUMBTRACK` read the 16-bit wParam thumb**, wrong (and truncating) for ranges > 65535 px.
**The fix:**
- `Uji::Layout::_intrinsic`: column/radio_group return `max_child_w + pad*2` × `pad*2 + Σ(children)+spc`;
  row returns `pad*2 + Σ(children)+spc` × `max_child_h + pad*2`; group_box reserves its
  `pad*2 + 16` label band.
- `Uji::Layout::compute` scroll_view: content expands along the NON-scrolling axis to the viewport
  extent (`iw = avail width` for vertical, `ih = avail height` for horizontal) so it can't collapse.
- `Win32::_place_scrollbars`: gutters are computed first (`view_w = vW-gut_w`, `view_h = vh-gut_h`), a
  cross-overflow pass pulls in the SECOND bar when one gutter shrinks the other axis past the content,
  the viewport is moved/sized to leave the gutters open, bars are placed exactly in the gutters at
  `HWND_TOP` (`cast(0, Pointer[Void])`, SWP_NOACTIVATE), and `page_v/page_h`/ranges use the shrunken
  viewport.
- `Win32::move_widget` scroll_view: the direct full-size `SetWindowPos` on the viewport is removed;
  `_place_scrollbars` owns viewport placement/sizing.
- `Win32::_apply_scroll`: every moved content control is `InvalidateRect`'d before the viewport
  repaint, so scrolled-out regions don't leave stale pixels.
- `Win32::_scrollbar_event`: `SB_THUMBTRACK` reads the 32-bit `SIF_TRACKPOS` (with fallback to the
  16-bit wParam value for synthetic `SendMessage` events), fixing thumb position for large ranges.

**Regression artifacts:** `t/dbg_scroll_geom.pl` (scrollbar geometry + gutter probe; delete once the
live pass is green).

---

## Resolved Bug: ScrollView scroll range not updated by reconciler-driven renders (added/removed content)

**Status: FIXED.** `t/013_multi_window_scroll.t` 21/21 (new: "adding a row grows the scroll range
without a window resize"); full suite 14 files / 338 tests PASS.
**Report:** scrolling down then adding a new row via "Add a row" (a reconciler render) does not
increase the vertical scroll range — the new row is invisible until the user resizes the window,
which forces a full re-layout.
**Root cause (`lib/Uji/Reconciler.pm` → `lib/Uji/Driver/Win32.pm`):** `App::_render` runs
`compute + _move_all` on the fresh vtree *before* `patch_windows` transfers old ids. Pre-patch the
fresh scroll_view has a new (unregistered) id, so `_move_all → move_widget → _place_scrollbars`
is a no-op. Post-patch the id is transferred but the scroll_view's own bounds haven't changed
(it FILLS its parent, same as before), so the generic bounds-diff path in `patch` never re-invokes
`move_widget`. The range (`range_v`) stays at the old content height until a `WM_SIZE` arrives
(`_relayout_now` re-layouts the LIVE tree, which *does* find the registered record and re-runs
`_place_scrollbars`).
**The fix (`lib/Uji/Reconciler.pm`):** at the end of `patch` for a `scroll_view` node, call
`_place_scrollbars` + `_apply_scroll` directly. This re-reads the now-current content height (set
by the pre-patch `compute`), grows/shrinks the gutter scrollbars, and re-offsets every store-tagged
content child. Idempotent on a stable tree; only fires meaningfully when content changed.
**Regression test (`t/013_multi_window_scroll.t`):** clears the viewer, appends rows until the
viewport overflows (asserts `range_v > 0` and `aux_v` exists), appends one more row, and asserts
`range_v` strictly increased — all without a resize.

---

## Resolved Bug: `_wheel_target` fails to find the scroll_view when wheeling over a scrollbar strip

**Status: FIXED.** `t/012_widget_queue.t` 46/46; full suite 338 tests PASS.
**Report:** the `_wheel_target` hit-test used a single `RECT` buffer (`$wrect`) for both the viewport
and each scrollbar rect. Affix `cast()` is *lazy* — it re-reads the underlying buffer on every
access, so `GetWindowRect` on a scrollbar overwrites the buffer and subsequent reads of the viewport
rect (`$r->{left}` etc.) silently return the *scrollbar's* coordinates. After the gutter geometry
fix moved scrollbars *outside* the viewport rect, this lazy overwrite made the post-loop `$in_view`
check test the cursor against the *scrollbar* rect rather than the viewport — so a wheel over the
viewport (but not the scrollbar) failed the containment test entirely.
**The fix:** cache `$in_view` (viewport containment) *before* the scrollbar loop starts, and use a
separate `$r2` cast for the scrollbar rect; allow the target even when the cursor is over a
scrollbar strip that sits outside the viewport (`next unless $in_view || $keyed`). This lets a wheel
aimed at the vertical/horizontal scrollbar of a scroll_view work too (common UX expectation).
