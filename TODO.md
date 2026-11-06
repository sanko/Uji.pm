# Uji.pm Project Roadmap

A modern, declarative, asynchronous GUI toolkit for Perl 5.40+ using The Elm Architecture (TEA),
native FFI via Affix. This is a testbed for cooperative fibers via Acme::Parataxis.

## Widget Set

- [x] `Window` (Top-level application window with title, dimensions & menu bar)
  - [ ] Modal dialog windows and child window parenting
  - [ ] Taskbar progress bar integration (`ITaskbarList3`)
- [x] `Text` (Static text label)
- [x] `Button` (Clickable push button with `on_click` event)
- [x] `TextInput` / `Password` (Single-line input with two-way `on_input` binding)
  - [x] Core functionality
  - [ ] Placeholder text / prompt hint banners (Win32: `EM_SETCUEBANNER`)
  - [ ] Clear-text button utility (`clearable => 1`)
- [x] `Slider` (Range slider with `on_change` event)
  - [x] Core functionality
  - [ ] Live drag tracking (`on_slide` for live updates vs `on_change` for final commit)
  - [ ] Step increment snapping
- [x] `Checkbox` / `ToggleSwitch` (Toggle boxes with `on_toggle` event)
- [x] `RadioGroup` / `Radio` (Exclusive selection with `WS_GROUP`)
- [x] `MultilineText` (Wrapping/scrollable text area)
- [x] `ComboBox` (Editable/dropdown selection with `options`)
  - [x] Core functionality
  - [ ] Dynamic auto-complete filtering as the user types
- [x] `ListBox` (Scrollable list of options)
- [x] `SpinBox` (Numeric stepper with buddy up-down control)
  - [x] Core functionality
  - [ ] Live drag tracking (`on_slide` for live updates vs `on_change` for final commit)
  - [ ] Step increment snapping
- [x] `DatePicker` (Calendar-based date entry)
  - [x] Core functionality
  - [ ] Date range constraints (`min_date`, `max_date`)
  - [ ] Nullable / blank dates (`allow_none => 1`)
- [x] `ProgressBar` (Determinate & animated marquee modes)
- [x] `Spacer` (Flexible or fixed whitespace primitive)
- [x] `GroupBox` (Etched frame with label, custom padding, and child nesting)
- [x] `ScrollView` (Hardware-clipped scrollable viewport with native scrollbars)
  - [x] Core functionality
  - [ ] Programmatic scroll positioning API
- [x] `TabPanel` / `Tab` (Multi-page tabbed container with dynamic VDOM switching)
  - [x] Core functionality
  - [ ] Dynamic tab management (`on_close` / dynamic tab addition & removal)
  - [ ] Closable tabs with close cross buttons (`closable => 1`)
  - [ ] Icon support per tab (`icon => ...`)
  - [ ] Individual tab disabled states (`enabled => 0`)
- [x] `SplitView` (Horizontal and vertical resizable split panes with draggable divider)
  - [x] Core functionality
  - [ ] Collapsible / expandable panes (drawer collapse/expand toggle)
  - [ ] Absolute pixel width/height for sidebars (e.g. `sidebar_width => 250`)
  - [ ] Double-click splitter handle to reset split ratio to default (e.g. `0.5`)
  - [ ] Multi-pane nested split layout propagation
- [x] `ListView` (Multi-column native data table with sorting, multi-select, cell widgets, virtual rows, and in-place editing)
- [ ] `ToggleButton` (Sticky push style, `checked` state)
- [ ] `LinkButton` (Hyperlink styling, `on_click`)
- [ ] `Image` (Loads/displays static raster from data or path)
- [ ] `Canvas` (Raw 2D drawing surface; `on_draw` callback)
- [ ] `Spinner` (Activity indicator, no value)
- [ ] `StatusText` (Subtle footer/hint text)
- [ ] `Overlay` (Stack children on top of previous; e.g. badge on image)
- [ ] `TreeView` (Hierarchical tree data; `nodes =>`, `on_select`)
- [ ] `Toolbar` (Row of icon/text actions)
- [x] `Menu` / `MenuBar` (Application-level menus, accelerators, context menus)
- [x] `FileOpenDialog` (`GetOpenFileNameW` as Elm `Cmd`)
- [x] `FileSaveDialog` (`GetSaveFileNameW` as Elm `Cmd`)
- [x] `MessageBox` (`MessageBoxW` as Elm `Cmd`)
- [ ] `PromptDialog` (Ask for a string value)
- [ ] `ColorPicker`

## Platform Drivers

### Windows

- [x] Window class registration & `PeekMessageW` loop
- [x] Standard controls (`STATIC`, `BUTTON`, `EDIT`, `LISTBOX`, `COMBOBOX`)
- [x] Common controls (`TRACKBAR`, `UPDOWN`, `DATETIMEPICK`, `PROGRESS`, `TAB`, `LISTVIEW`)
- [x] Dynamic control destruction (`DestroyWindow`)
- [x] Event routing via `WM_COMMAND` + `WM_NOTIFY` + `WM_HSCROLL` + `WM_VSCROLL` + `WM_CONTEXTMENU`
- [x] Standard system font application (`DEFAULT_GUI_FONT` via `WM_SETFONT`)
- [x] Window resize handling (`WM_SIZE` -> re-layout pass)
- [x] Native menus, context menus, and system dialogs

### Linux (GTK4)

### macOS (Cocoa)

### Terminal (Cancer)

## Polish & Packaging

- [ ] Standard system font scaling & DPI awareness
- [ ] Dark Mode auto-detection
