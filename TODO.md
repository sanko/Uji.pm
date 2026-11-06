# Uji.pm Project Roadmap

A modern, declarative, asynchronous GUI toolkit for Perl 5.40+ using The Elm Architecture (TEA),
native FFI via Affix. This is a testbed for cooperative fibers via Acme::Parataxis.

## Core Architecture
- [x] Unidirectional State Loop (The Elm Architecture: Model-View-Update)
- [x] Cooperative Fiber Event Pump (Acme::Parataxis & non-blocking polling)
- [x] Inter-fiber message queue via `Acme::Parataxis::Channel`
- [x] Background side-effects system (Elm `Cmd`s in dedicated fibers)
- [x] Declarative Virtual DOM (VDOM) tree representation using `perlclass`
- [x] Virtual Node Identity preservation & Reconciler diff/patching engine
  - [x] Keyed child reconciliation (`key => $id`) for stable native control identities
  - [x] Unkeyed positional fallback reconciliation
  - [x] Dynamic subtree creation (`mount_widget`) and destruction (`destroy_widget`)
  - [x] Automatic type replacement if node types change
- [ ] Subscriptions system (`Sub` for periodic timers, window resize events)

## Layout Engine
- [x] Pure-Perl absolute coordinate calculations (bypassing native layout quirks)
- [x] Window root client-area calculations
- [x] Vertical container (`Column`) with padding and spacing
- [x] Horizontal container (`Row`) with padding and spacing
- [x] Proportionate flexible sizing (`flex => 1`, `flex => 2`)
- [ ] **Auto-resize policy** (design decision needed: how widgets size to content & parent)
  - [x] Intrinsic sizing (measure phase: text metrics -> natural width/height)
  - [x] Parent-driven resize: re-layout on `WM_SIZE` (already tracked under Windows driver)
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
- [x] `Checkbox` (Toggle box with `on_toggle` event; `BS_AUTOCHECKBOX`)
- [x] `ToggleSwitch` (Sticky push toggle style; `BS_PUSHLIKE`)
- [x] `RadioGroup` / `RadioButton` (Exclusive selection; `on_select`)
  - Win32: `BS_AUTORADIOBUTTON` grouped with `WS_GROUP`
  - GTK4: `GtkCheckButton` inside a shared length-1 group
  - Cocoa: `NSButton` with `NSButtonTypeRadio`
- [x] `MultilineText` (Wrapping/scrollable text area; line breaks in `value`)
- [x] `ComboBox` (Editable dropdown; `options => [...]`, `on_select`)
- [x] `ListBox` (Scrollable list of options; `selection`/`on_select`)
- [x] `SpinBox` (Numeric stepper with `min`/`max`/`step`)
- [x] `DatePicker` (Calendar-based date entry)

### Buttons & Static Display
- [x] `ToggleButton` (Sticky push style, `checked` state)
- [ ] `LinkButton` (Hyperlink styling, `on_click`)
- [ ] `Image` (Loads/displays static raster from data or path)
- [ ] `Canvas` (Raw 2D drawing surface; `on_draw` callback)
- [x] `ProgressBar` (Determinate/indeterminate `value`)
- [x] `Spinner` (Activity indicator, no value)

### Layout & Containers
- [x] `Column` + `Row` (Flex containers with padding/spacing/alignment)
- [x] `TabPanel` (Tabbed sub-views; `panels => [...]`, `on_select`)
- [x] `ScrollView` (Clipping + scrollable region, `orientation`)
- [x] `SplitView` (Movable divider between two panes, `orientation`)
- [x] `GroupBox` (Labeled visual grouping of children)
- [x] `Spacer` (Explicit flexible whitespace, flex-aware)
- [ ] `Overlay` (Stack children on top of previous; e.g. badge on image)

### Data Display & Navigation
- [ ] `ListView` (Multi-column table; `columns =>`, `rows =>`, `on_select`)
- [ ] `TreeView` (Hierarchical data; `nodes =>`, `on_select`)
- [ ] `Toolbar` (Row of icon/text actions)
- [x] `Menu` / `MenuBar` (Application-level menus, accelerators)

### Polling & Dialogs (system-level)
- [x] `FileOpenDialog` (Native file picker)
- [x] `FileSaveDialog`
- [x] `MessageBox` (App-modal alert/confirm)
- [ ] `PromptDialog` (Ask for a string value)
- [ ] `ColorPicker`

### Event convention (draft)
- Value widgets: `on_change` / `on_input` / `on_toggle` / `on_select`, mirroring the text field's two-way binding: the model is the reference and the reconciler pushes diffs back.
- Keyboard/mouse: to be defined alongside a `Subscriptions` system.

## Platform Drivers
- [ ] **Windows**
  - [x] Window class registration & `PeekMessageW` loop
  - [x] Standard controls (`STATIC`, `BUTTON`, `EDIT`)
  - [x] Common controls (`TRACKBAR` slider, via `InitCommonControlsEx`)
  - [x] Event routing via `WM_COMMAND` (`BN_CLICKED`, `EN_CHANGE`) + `WM_HSCROLL`
  - [x] Standard system font application (replace default bitmap font with Segoe UI)
  - [x] Window resize handling (`WM_SIZE` -> re-layout pass)
  - [x] Checkbox / radio button mapping (`BS_AUTOCHECKBOX`, `BS_AUTORADIOBUTTON`)
  - [x] Combo/list box mapping (`CB_`, `LB_` messages, `WM_COMMAND` notifications)
  - [ ] Native dialogs (`GetOpenFileNameW`, `MessageBoxW`)
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

## Polish & Packaging
- [ ] Standard system font scaling & DPI awareness
- [ ] Dark Mode auto-detection
