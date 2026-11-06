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
- [x] Subscriptions system (`Sub` for periodic timers, window resize events)

## Layout Engine
- [x] Pure-Perl coordinate calculations (bypassing native layout quirks)
- [x] Window root client-area calculations
- [x] Vertical container (`Column`) with padding, spacing, and cross-axis alignment
- [x] Horizontal container (`Row`) with padding, spacing, and cross-axis alignment
- [x] Cross-axis alignment (`align => 'stretch'|'start'|'center'|'end'`, `align_self`)
- [x] Proportionate flexible sizing (`flex => 1`, `flex => 2`)
- [x] Constraint plumbing down the tree (`min_w`, `max_w`, `min_h`, `max_h` on all nodes)
- [x] Intrinsic sizing (measure phase: text metrics -> natural width/height)
- [x] Auto-resize policy:
  - [x] Window auto-sizing to wrapped content when unconstrained
  - [x] Parent-driven resize: live re-layout on `WM_SIZE`
- [x] Overflow clipping policy:
  - Default: `clip => 0` (unclipped for tooltips, focus rings, shadows)
  - Explicit: `clip => 1` for clipping containers
- [x] Scrolling and overflow clipping containers (`ScrollView`)

## Widget Set

### Implemented & Tested (Win32)
- [x] `Window` (Top-level application window with title, dimensions & menu bar)
- [x] `Text` (Static text label)
- [x] `Button` (Clickable push button with `on_click` event)
- [x] `TextInput` (Single-line input with two-way `on_input` binding)
- [x] `Password` (Masked single-line text; `EDIT` with `ES_PASSWORD`)
- [x] `Slider` (Range slider with `on_change` event; Win32 trackbar)
- [x] `Checkbox` (Toggle box with `on_toggle` event; `BS_AUTOCHECKBOX`)
- [x] `ToggleSwitch` (Sticky push toggle style; `BS_PUSHLIKE`)
- [x] `RadioGroup` / `Radio` (Exclusive selection with `WS_GROUP`; `on_select`)
- [x] `MultilineText` (Wrapping/scrollable text area; `ES_MULTILINE`)
- [x] `ComboBox` (Editable/dropdown selection; `CB_` messages, `on_select`, `on_input`)
- [x] `ListBox` (Scrollable list of options; `LB_` messages, `on_select`)
- [x] `SpinBox` (Numeric stepper with buddy up-down control; `UDM_`)
- [x] `DatePicker` (Calendar-based date entry; `SysDateTimePick32`)
- [x] `ProgressBar` (Determinate & animated marquee modes via `PBM_`)
- [x] `Spacer` (Flexible or fixed whitespace primitive)
- [x] `GroupBox` (Etched frame with label, custom padding, and child nesting)
- [x] `ScrollView` (Hardware-clipped scrollable viewport with native scrollbars)
- [x] `TabPanel` / `Tab` (Multi-page tabbed container with dynamic VDOM switching)
- [x] `SplitView` (Horizontal and vertical resizable split panes with draggable divider)
- [x] `ListView` (Multi-column native data table with headers, sorting, multi-select, cell widgets)

### Buttons & Static Display
- [ ] `ToggleButton` (Sticky push style, `checked` state)
- [ ] `LinkButton` (Hyperlink styling, `on_click`)
- [ ] `Image` (Loads/displays static raster from data or path)
- [ ] `Canvas` (Raw 2D drawing surface; `on_draw` callback)
- [ ] `Spinner` (Activity indicator, no value)
- [ ] `StatusText` (Subtle footer/hint text)

### Layout & Containers
- [x] `Column` + `Row` (Flex containers with padding/spacing/alignment)
- [x] `Spacer` (Explicit flexible whitespace, flex-aware)
- [x] `GroupBox` (Labeled visual grouping of children)
- [x] `ScrollView` (Clipping + scrollable region)
- [x] `TabPanel` (Tabbed sub-views; `tabs => [...]`, `on_select`)
- [x] `SplitView` (Movable divider between two panes, horizontal & vertical)
- [ ] `Overlay` (Stack children on top of previous; e.g. badge on image)

### Data Display & Navigation
- [x] `ListView` (Multi-column table in Report mode)
  - [x] Column headers with alignment (`left`, `center`, `right`)
  - [x] Interactive column sorting (`on_sort`) with native $\uparrow$/$\downarrow$ sort arrows
  - [x] Drag-and-drop column reordering (`column_reorder`)
  - [x] Single and multi-selection (`multiselect => 1`, `on_select`)
  - [x] Row double-click and Enter activation (`on_activate`)
  - [x] Right-click context menus (`context_menu`) with hit-testing
  - [x] Row checkboxes (`checkboxes => 1`, `on_check`)
  - [x] Cell custom draw (`type => 'progress_bar'`, `type => 'badge'`)
  - [x] Column auto-sizing (`width => 'auto'`)
- [ ] `TreeView` (Hierarchical data; `nodes =>`, `on_select`)
- [ ] `Toolbar` (Row of icon/text actions)
- [x] `Menu` / `MenuBar` (Application-level menus, accelerators, context menus)
*Note on `StatusBar`: Modern UI guidelines across GTK4, WinUI 3, and macOS deprecate dedicated status bars in favor of flex `Row` + `Spacer` + `StatusText`.*

### Polling & Dialogs (system-level)
- [x] `FileOpenDialog` (`GetOpenFileNameW` as Elm `Cmd`)
- [x] `FileSaveDialog` (`GetSaveFileNameW` as Elm `Cmd`)
- [x] `MessageBox` (`MessageBoxW` as Elm `Cmd`)
- [ ] `PromptDialog` (Ask for a string value)
- [ ] `ColorPicker`
