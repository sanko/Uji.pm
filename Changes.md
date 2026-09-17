# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
  - `sortable` (header-click column sorting, `LVN_COLUMNCLICK = -108`), `on_sort`
    (`sub ($col, $dir)` with per-click asc/desc toggle), and per-column `sort =>
    'numeric'` (default `'text'`): the driver sorts a slot table of RAW cells and
    rebuilds the native rows, so formatted columns still sort numerically. Sort is
    a display concern - the model `rows` are untouched and the app re-sorts them
    in `on_sort`.
  - `reorderable` (drag column headers to reorder, `LVS_EX_HEADERDRAGDROP =
    0x10`) and `on_reorder` (`sub ($order)`): the driver polls
    `LVM_GETCOLUMNORDERARRAY` (`0x103B`) each event-loop pass and reports a
    change. `lv_column_order` exposes the read (and is used by the tests).
  - `format` on a column definition (e.g. `{ label => 'Price', width => 80,
    format => '$%0.2f' }`): numeric cells are `sprintf`'d for display; non-numeric
    cells pass through untouched and sorting always uses the raw cell.
    Formatting is a display concern - the model `rows` are untouched.
  - `align` on a column definition (`'left'`/`'center'`/`'right'`, default
    `'left'`): maps to the native `LVCFMT_LEFT`/`LVCFMT_CENTER`/`LVCFMT_RIGHT`
    (with `LVCFMT_JUSTIFYMASK`) so headers and cells align per column.
  - a visible sort-direction indicator: the active column's header label is
    re-stamped with `▲` (ascending) / `▼` (descending) after a sort, the glyph
    follows the column when headers are drag-reordered, and a rows-only reconcile
    preserves it.

### Changed
  - list_view reconcile distinguishes a C<columns> change (rebuilds the header:
    widths, drag order and sort glyph are re-applied from the model) from a
    C<rows>-only change (native live widths, a user's drag-reordered column order
    and the sort glyph all survive a re-sort).
  - `list_view` widget (see `t/025_list_view.t`): a multi-column, scrollable
    selection table over `SysListView32` in report view. `columns` (`{label,width}`,
    width measured from the label by default), `rows` (cell arrayrefs or
    `{value=>, columns=>[]}` hashrefs, value defaulting to the first cell),
    `value`/`multiple` (arrayref of selected values), and mount-only
    `full_row_select`/`grid_lines`/`header`. Columns insert via `LVM_INSERTCOLUMNW`,
    the first cell of each row via `LVM_INSERTITEMW`, later cells via `LVM_SETITEMW`
    (NOT `LVM_SETITEMTEXTW`, which silently no-ops on subitems); selection is
    applied with `LVM_SETITEMSTATE` (`LVIF_STATE`/`LVIS_SELECTED`) + `LVM_ENSUREVISIBLE`
    and multi-selection reads the native state back through `LVM_GETITEMCOUNT` /
    `LVM_GETITEMSTATE`. `LVN_ITEMCHANGED` routes through a driver-side slot table
    (row index -> value) with programmatic selection suppressed. Hand-packed
    `LVCOLUMNW` (72 bytes) / `LVITEMW` (88 bytes) structs for Win64.
    `lib/Uji/Node/ListView.pm`, `eg/widget_list_view.pl`.
  - Documentation for every module that lacked it: `LinkButton`, `ProgressBar`,
    `SpinBox`, `SplitView`, `TabPanel`, `ToggleButton`, `ToggleSwitch`,
    `Driver::Cocoa`, and `Driver::GTK4` node/driver pods, plus missing `Uji.pod`
    helper sections (`status_text`, `status_bar`, `group_box`, `scroll_view`,
    `split_view`, `tab_panel`, `tree_view`, `toolbar`, `menu_bar`).

### Changed
  - It exists! (all prior work: the Elm-architecture runtime, layout engine,
    reconciler, Win32/mock drivers, and the rest of the widget set)

### Fixed
  - list_view crashed with an access violation (0xC0000005) because the `LVITEMW`
    pack was misaligned: `state`/`stateMask` live at offsets 12/16 (not 16/20),
    `pszText` at 24, `lParam` at 40. The corrected template is
    `'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4'`.
  - list_view used the wrong `LVM_*` messages for columns: `LVM_GETCOLUMNWIDTH` is
    `0x101D` (not `0x1065`), `LVM_SETCOLUMNWIDTH` `0x101E`, `LVM_DELETECOLUMN`
    `0x101C` (not `0x1064`), `LVM_GETCOLUMNW` `0x105F`; `0x105C` is not
    `LVM_GETCOLUMNCOUNT` (it returns 0) and is no longer used. The old messages
    inserted columns but every width readback returned 0.
  - list_view cell text for subitems (columns after the first) is set with
    `LVM_SETITEMW` because `LVM_SETITEMTEXTW` returns FALSE and stores nothing for
    subitems > 0.
  - list_view `on_select` never fired on a real click: the driver dispatched on
    `LVN_ITEMCHANGED = -102`, but `-102` is `LVN_INSERTITEM` (the populate-time
    notify flood). The real selection notification is `LVN_ITEMCHANGED = -101`
    (`LVN_FIRST - 1`, which has no A/W variant); the driver now keys on `-101`.
  - list_view cell lookups packed a third spurious zero into the `LVITEMW` before
    `pszText`, shifting `pszText` to NULL; the probe's reader now packs the exact
    15 fields.

[Unreleased]: /compare/v0.0.1...HEAD
[v0.0.1]: /releases/tag/v0.0.1