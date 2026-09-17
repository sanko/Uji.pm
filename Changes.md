# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

[Unreleased]: /compare/v0.0.1...HEAD
[v0.0.1]: /releases/tag/v0.0.1