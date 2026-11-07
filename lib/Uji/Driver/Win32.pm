use v5.40;
use experimental 'class';
use Uji::Driver;
class Uji::Driver::Win32 v0.0.1 : isa(Uji::Driver) {

    # user32.dll, gdi32.dll
    use Affix  qw[:memory :types :core];
    use Encode qw[decode];
    field $channel : reader;
    field $registry;
    field $wndproc_cb;
    field $main_hwnd;
    field $main_vnode      : reader;
    field $tooltip_hwnd    : reader                 = undef;
    field $suppress_events : reader(_is_suppressed) = 0;
    field $gui_font;
    field $dragging_splitter   = undef;    # { record => $rec, start_pt => [x, y], orig_ratio => 0.5 }
    field $active_inplace_edit = undef;    # { hwnd, edit_hwnd, row_idx, col_id, orig_wndproc }
    ADJUST {
        $registry = {};
        typedef WNDPROC => Callback [ [ Pointer [Void], UInt, Size_t, SSize_t ] => SSize_t ];
        typedef WNDCLASSEXW => Struct [
            cbSize        => UInt,
            style         => UInt,
            lpfnWndProc   => WNDPROC(),
            cbClsExtra    => Int,
            cbWndExtra    => Int,
            hInstance     => Pointer [Void],
            hIcon         => Pointer [Void],
            hCursor       => Pointer [Void],
            hbrBackground => Pointer [Void],
            lpszMenuName  => WString,
            lpszClassName => WString,
            hIconSm       => Pointer [Void]
        ];
        affix 'user32', 'RegisterClassExW', [ Pointer [ WNDCLASSEXW() ] ] => UShort;
        affix 'user32', 'CreateWindowExW',
            [ ULong, WString, WString, ULong, Int, Int, Int, Int, Pointer [Void], Size_t, Pointer [Void], Pointer [Void] ] => SSize_t;
        affix 'user32', 'DestroyWindow',    [ Pointer [Void] ]                                           => Int;
        affix 'user32', 'ShowWindow',       [ Pointer [Void], Int ]                                      => Int;
        affix 'user32', 'SetWindowTextW',   [ Pointer [Void], WString ]                                  => Int;
        affix 'user32', 'EnableWindow',     [ Pointer [Void], Int ]                                      => Int;
        affix 'user32', 'SetFocus',         [ Pointer [Void] ]                                           => Pointer [Void];
        affix 'user32', 'SetWindowPos',     [ Pointer [Void], Pointer [Void], Int, Int, Int, Int, UInt ] => Int;
        affix 'user32', 'DefWindowProcW',   [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;
        affix 'user32', 'PeekMessageW',     [ Pointer [Void], Pointer [Void], UInt, UInt, UInt ]         => Int;
        affix 'user32', 'TranslateMessage', [ Pointer [Void] ]                                           => Int;
        affix 'user32', 'DispatchMessageW', [ Pointer [Void] ]                                           => SSize_t;
        affix 'user32', 'UpdateWindow',     [ Pointer [Void] ]                                           => Int;
        affix 'user32', 'InvalidateRect',   [ Pointer [Void], Pointer [Void], Int ]                      => Int;
        affix 'user32', 'LoadCursorW',      [ Pointer [Void], Size_t ]                                   => Pointer [Void];
        affix 'user32', 'GetSystemMetrics', [Int]                                                        => Int;
        affix 'user32', 'SendMessageW',     [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;
        affix 'user32', 'GetWindowLongW',   [ Pointer [Void], Int ]                                      => Int;
        affix 'user32', 'SetWindowLongW',   [ Pointer [Void], Int, Int ]                                 => Int;

        # Atomic multi-window positioning & redrawing
        affix 'user32', 'BeginDeferWindowPos', [Int]                                                                        => Pointer [Void];
        affix 'user32', 'DeferWindowPos',      [ Pointer [Void], Pointer [Void], Pointer [Void], Int, Int, Int, Int, UInt ] => Pointer [Void];
        affix 'user32', 'EndDeferWindowPos',   [ Pointer [Void] ]                                                           => Int;
        affix 'user32', 'RedrawWindow',        [ Pointer [Void], Pointer [Void], Pointer [Void], UInt ]                     => Int;

        # Same entry point, but with a marshalled wide-string lParam (combo/list item text).
        affix 'user32', [ 'SendMessageW', 'SendMessageWStr' ], [ Pointer [Void], UInt, Size_t, WString ] => SSize_t;

        # Menus
        affix 'user32', 'CreateMenu',       []                                                                 => Pointer [Void];
        affix 'user32', 'CreatePopupMenu',  []                                                                 => Pointer [Void];
        affix 'user32', 'AppendMenuW',      [ Pointer [Void], UInt, Size_t, WString ]                          => Int;
        affix 'user32', 'SetMenu',          [ Pointer [Void], Pointer [Void] ]                                 => Int;
        affix 'user32', 'DrawMenuBar',      [ Pointer [Void] ]                                                 => Int;
        affix 'user32', 'DestroyMenu',      [ Pointer [Void] ]                                                 => Int;
        affix 'user32', 'TrackPopupMenuEx', [ Pointer [Void], UInt, Int, Int, Pointer [Void], Pointer [Void] ] => Int;

        # Dialogs
        affix 'user32', 'MessageBoxW', [ Pointer [Void], WString, WString, UInt ] => Int;

        # File open/save dialogs
        typedef OPENFILENAMEW => Struct [
            lStructSize       => ULong,
            hwndOwner         => Pointer [Void],
            hInstance         => Pointer [Void],
            lpstrFilter       => Pointer [Void],
            lpstrCustomFilter => Pointer [Void],
            nMaxCustFilter    => ULong,
            nFilterIndex      => ULong,
            lpstrFile         => Pointer [Void],
            nMaxFile          => ULong,
            lpstrFileTitle    => Pointer [Void],
            nMaxFileTitle     => ULong,
            lpstrInitialDir   => WString,
            lpstrTitle        => WString,
            Flags             => ULong,
            nFileOffset       => UShort,
            nFileExtension    => UShort,
            lpstrDefExt       => WString,
            lCustData         => SSize_t,
            lpfnHook          => Pointer [Void],
            lpTemplateName    => Pointer [Void]
        ];
        affix 'comdlg32', 'GetOpenFileNameW', [ Pointer [ OPENFILENAMEW() ] ] => Int;
        affix 'comdlg32', 'GetSaveFileNameW', [ Pointer [ OPENFILENAMEW() ] ] => Int;

        # Read native control text
        typedef RECT => Struct [ left => Int, top => Int, right => Int, bottom => Int ];
        typedef POINT => Struct [ x => Int, y => Int ];
        typedef SYSTEMTIME => Struct [
            wYear         => UShort,
            wMonth        => UShort,
            wDayOfWeek    => UShort,
            wDay          => UShort,
            wHour         => UShort,
            wMinute       => UShort,
            wSecond       => UShort,
            wMilliseconds => UShort
        ];
        typedef NMHDR            => Struct [ hwndFrom => Pointer [Void], idFrom => Size_t, code => Int ];
        typedef NMDATETIMECHANGE => Struct [ nmhdr    => NMHDR(), dwFlags => ULong, st => SYSTEMTIME() ];
        typedef UDACCEL          => Struct [ nSec     => UInt, nInc => UInt ];
        typedef MINMAXINFO =>
            Struct [ ptReserved => POINT(), ptMaxSize => POINT(), ptMaxPosition => POINT(), ptMinTrackSize => POINT(), ptMaxTrackSize => POINT() ];
        typedef TOOLINFO => Struct [
            cbSize     => UInt,
            uFlags     => UInt,
            hwnd       => Pointer [Void],
            uId        => Size_t,
            rect       => RECT(),
            hinst      => Pointer [Void],
            lpszText   => WString,
            lParam     => SSize_t,
            lpReserved => Pointer [Void]
        ];
        typedef LVHITTESTINFO => Struct [ pt => POINT(), flags => UInt, iItem => Int, iSubItem => Int ];
        typedef SCROLLINFO => Struct [ cbSize => UInt, fMask => UInt, nMin => Int, nMax => Int, nPage => UInt, nPos => Int, nTrackPos => Int ];
        typedef TCITEMW =>
            Struct [ mask => UInt, dwState => ULong, dwStateMask => ULong, pszText => WString, cchTextMax => Int, iImage => Int, lParam => SSize_t ];
        affix 'user32', 'SetScrollInfo',        [ Pointer [Void], Int, Pointer [ SCROLLINFO() ], Int ] => Int;
        affix 'user32', 'GetScrollInfo',        [ Pointer [Void], Int, Pointer [ SCROLLINFO() ] ]      => Int;
        affix 'user32', 'GetWindowTextLengthW', [ Pointer [Void] ]                                     => Int;
        affix 'user32', 'GetWindowTextW',       [ Pointer [Void], Pointer [Void], Int ]                => Int;
        affix 'user32', 'GetClientRect',        [ Pointer [Void], Pointer [Void] ]                     => Int;
        affix 'user32', 'GetWindowRect',        [ Pointer [Void], Pointer [Void] ]                     => Int;
        affix 'user32', 'AdjustWindowRectEx',   [ Pointer [ RECT() ], UInt, Int, UInt ]                => Int;

        # Text metrics for intrinsic sizing (measure natural widget size)
        affix 'user32', 'GetDC',                 [ Pointer [Void] ]                               => Pointer [Void];
        affix 'user32', 'ReleaseDC',             [ Pointer [Void], Pointer [Void] ]               => Int;
        affix 'gdi32',  'GetStockObject',        [Int]                                            => Pointer [Void];
        affix 'gdi32',  'SelectObject',          [ Pointer [Void], Pointer [Void] ]               => Pointer [Void];
        affix 'gdi32',  'GetTextExtentPoint32W', [ Pointer [Void], WString, Int, Pointer [Void] ] => Int;
        typedef SIZE => Struct [ cx => Int, cy => Int ];
        affix 'user32', 'SetCapture',     [ Pointer [Void] ]                                     => Pointer [Void];
        affix 'user32', 'ReleaseCapture', []                                                     => Int;
        affix 'user32', 'SetCursor',      [ Pointer [Void] ]                                     => Pointer [Void];
        affix 'user32', 'GetCursorPos',   [ Pointer [ POINT() ] ]                                => Int;
        affix 'user32', 'ScreenToClient', [ Pointer [Void], Pointer [ POINT() ] ]                => Int;
        affix 'user32', 'FillRect',       [ Pointer [Void], Pointer [ RECT() ], Pointer [Void] ] => Int;
        typedef LVCOLUMNW =>
            Struct [ mask => UInt, fmt => Int, cx => Int, pszText => WString, cchTextMax => Int, iSubItem => Int, iImage => Int, iOrder => Int ];
        typedef HDITEMW => Struct [
            mask       => UInt,
            cxy        => Int,
            pszText    => WString,
            hbm        => Pointer [Void],
            cchTextMax => Int,
            fmt        => Int,
            lParam     => SSize_t,
            iImage     => Int,
            iOrder     => Int,
            type       => UInt,
            pvFilter   => Pointer [Void]
        ];
        typedef LVITEMW => Struct [
            mask       => UInt,
            iItem      => Int,
            iSubItem   => Int,
            state      => UInt,
            stateMask  => UInt,
            pszText    => Pointer [Void],    # Persistent C pointer buffer
            cchTextMax => Int,
            iImage     => Int,
            lParam     => SSize_t
        ];
        typedef NMLISTVIEW => Struct [
            hdr       => NMHDR(),
            iItem     => Int,
            iSubItem  => Int,
            uNewState => UInt,
            uOldState => UInt,
            uChanged  => UInt,
            ptAction  => POINT(),
            lParam    => SSize_t
        ];

        # NMLVDISPINFOW struct for LVN_GETDISPINFOW and LVN_ENDLABELEDITW
        typedef NMLVDISPINFOW => Struct [
            hwndFrom => Pointer [Void],    # 0
            idFrom   => Size_t,            # 8
            code     => Int,               # 16
            _pad_hdr => Int,               # 20

            # Embedded LVITEMW:
            mask       => UInt,              # 24
            iItem      => Int,               # 28
            iSubItem   => Int,               # 32
            state      => UInt,              # 36
            stateMask  => UInt,              # 40
            _pad_item  => Int,               # 44
            pszText    => Pointer [Void],    # 48
            cchTextMax => Int,               # 56
            iImage     => Int,               # 60
            lParam     => SSize_t            # 64
        ];

        # GDI functions for cell drawing
        affix 'gdi32',  'SetBkMode',        [ Pointer [Void], Int ]                                    => Int;
        affix 'gdi32',  'SetTextColor',     [ Pointer [Void], ULong ]                                  => ULong;
        affix 'gdi32',  'CreateSolidBrush', [ULong]                                                    => Pointer [Void];
        affix 'gdi32',  'DeleteObject',     [ Pointer [Void] ]                                         => Int;
        affix 'user32', 'DrawTextW',        [ Pointer [Void], WString, Int, Pointer [ RECT() ], UInt ] => Int;
        affix 'user32', 'FrameRect',        [ Pointer [Void], Pointer [ RECT() ], Pointer [Void] ]     => Int;
        typedef NMLVCUSTOMDRAW => Struct [
            hwndFrom    => Pointer [Void],    # offset 0
            idFrom      => Size_t,            # offset 8
            code        => Int,               # offset 16
            _pad_hdr    => Int,               # offset 20 (64-bit alignment padding)
            dwDrawStage => UInt,              # offset 24
            _pad_ds     => Int,               # offset 28
            hdc         => Pointer [Void],    # offset 32
            rc          => RECT(),            # offset 40 (16 bytes)
            dwItemSpec  => Size_t,            # offset 56 (row index)
            uItemState  => UInt,              # offset 64
            _pad_is     => Int,               # offset 68
            lItemlParam => SSize_t,           # offset 72
            clrText     => UInt,              # offset 80
            clrTextBk   => UInt,              # offset 84
            iSubItem    => Int,               # offset 88 (column index)
            dwItemType  => UInt               # offset 92
        ];

        # Comctl32 Window Subclassing API for in-place cell editing
        typedef SUBCLASSPROC => Callback [ [ Pointer [Void], UInt, Size_t, SSize_t, Size_t, SSize_t ] => SSize_t ];
        affix 'comctl32', 'SetWindowSubclass',    [ Pointer [Void], SUBCLASSPROC(), Size_t, SSize_t ] => Int;
        affix 'comctl32', 'RemoveWindowSubclass', [ Pointer [Void], SUBCLASSPROC(), Size_t ]          => Int;
        affix 'comctl32', 'DefSubclassProc',      [ Pointer [Void], UInt, Size_t, SSize_t ]           => SSize_t;
        #
        typedef NMITEMACTIVATE => Struct [
            hdr       => NMHDR(),
            iItem     => Int,
            iSubItem  => Int,
            uNewState => UInt,
            uOldState => UInt,
            uChanged  => UInt,
            ptAction  => POINT(),
            lParam    => SSize_t,
            uKeyFlags => UInt
        ];

        # DEFAULT_GUI_FONT (17) matches standard controls and font metrics
        $gui_font = GetStockObject(17);

        # Common controls (listview, tab, bar, updown, progress, date)
        typedef INITCOMMONCONTROLSEX => Struct [ dwSize => ULong, dwICC => ULong ];
        affix 'comctl32', 'InitCommonControlsEx', [ Pointer [ INITCOMMONCONTROLSEX() ] ] => Int;
        my $icc   = malloc( sizeof( INITCOMMONCONTROLSEX() ) );
        my $icc_s = cast( $icc, INITCOMMONCONTROLSEX() );
        $icc_s->{dwSize} = sizeof( INITCOMMONCONTROLSEX() );
        $icc_s->{dwICC}  = 0x00000001 | 0x00000004 | 0x00000008 | 0x00000010 | 0x00000020 | 0x00000100;
        InitCommonControlsEx($icc);
        free($icc);
    }

    method _apply_font ($hwnd) {
        return unless $hwnd && $gui_font;
        SendMessageW( $hwnd, 0x0030, Affix::address($gui_font), 1 );
    }

    method init ($app_channel) {
        $channel = $app_channel;
        my $self_ref = $self;
        $wndproc_cb = sub ( $hwnd, $msg, $wparam, $lparam ) {

            # Paint background behind static text and checkboxes so labels don't smear
            if ( $msg == 0x0138 || $msg == 0x0135 ) {    # WM_CTLCOLORSTATIC / WM_CTLCOLORBTN
                return 6;                                # HBRUSH for COLOR_WINDOW + 1
            }
            if ( $msg == 0x0111 ) {                      # WM_COMMAND
                my $control_id  = $wparam & 0xFFFF;
                my $notify_code = ( $wparam >> 16 ) & 0xFFFF;
                my $record      = $self_ref->_get_registry_record($control_id);
                if ($record) {
                    my $node = $record->{node};

                    # BN_CLICKED (0) -> Button / Menu click
                    if ( $notify_code == 0 && $node->can('on_click') && $node->on_click ) {
                        $self_ref->channel->put( $node->on_click );
                    }
                    elsif ( $notify_code == 0 && $node->can('on_toggle') && $node->on_toggle ) {
                        my $checked    = SendMessageW( $record->{hwnd}, 0x00F0, 0, 0 );    # BM_GETCHECK
                        my $action_msg = $node->on_toggle->( $checked ? 1 : 0 );
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                    elsif ( $notify_code == 0 && $node->can('on_select') && $node->on_select ) {
                        my $action_msg = $node->on_select->( $node->value );
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                    elsif ( $notify_code == 1 && $node->type eq 'combo_box' && $node->on_select ) {
                        my $idx = SendMessageW( $record->{hwnd}, 0x0147, 0, 0 );           # CB_GETCURSEL
                        if ( $idx >= 0 && $idx <= $#{ $node->options } ) {
                            my $action_msg = $node->on_select->( $node->options->[$idx]{value} );
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                    }
                    elsif ( $notify_code == 5 && $node->type eq 'combo_box' && $node->can('on_input') && $node->on_input ) {
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text       = $self_ref->_get_text( $record->{hwnd} );
                        my $action_msg = $node->on_input->($text);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                    elsif ( $notify_code == 1 && $node->type eq 'list_box' && $node->on_select ) {
                        my $idx = SendMessageW( $record->{hwnd}, 0x0188, 0, 0 );    # LB_GETCURSEL
                        if ( $idx >= 0 && $idx <= $#{ $node->options } ) {
                            my $action_msg = $node->on_select->( $node->options->[$idx]{value} );
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                    }
                    elsif ( $notify_code == 0x0300 && $node->type eq 'spin_box' && $node->on_change ) {
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text = $self_ref->_get_text( $record->{hwnd} );
                        if ( $text =~ /^\s*(-?\d+)\s*$/ ) {
                            my $num = $1;
                            $num = $node->min if $num < $node->min;
                            $num = $node->max if $num > $node->max;
                            my $action_msg = $node->on_change->($num);
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                    }

                    # EN_CHANGE (0x0300) -> Text changed by user typing
                    elsif ( $notify_code == 0x0300 && $node->can('on_input') && $node->on_input ) {
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text       = $self_ref->_get_text( $record->{hwnd} );
                        my $action_msg = $node->on_input->($text);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                }
            }
            elsif ( $msg == 0x007B ) {    # WM_CONTEXTMENU
                my $target_hwnd = cast( $wparam, Pointer [Void] );
                my $rec         = $self_ref->_get_registry_by_hwnd($target_hwnd);
                if ( $rec && $rec->{node}->can('context_menu') && $rec->{node}->context_menu ) {
                    $self_ref->_show_context_menu( $rec, $lparam );
                    return 0;
                }
            }
            elsif ( $msg == 0x004E ) {    # WM_NOTIFY
                my $hdr    = cast( $lparam, NMHDR() );
                my $record = $self_ref->_get_registry_record( $hdr->{idFrom} );

                # NM_CUSTOMDRAW (-12) -> Custom cell drawing (progress bars & badges)
                if ( $record && $record->{node}->type eq 'list_view' && $hdr->{code} == -12 ) {
                    return $self_ref->_handle_list_view_custom_draw( $record, $lparam );
                }

                # Selection & Checkbox notifications for ListView
                # - NM_CLICK (-2): Mouse click settled completely
                # - LVN_ITEMCHANGED (-100): Selection gained via keyboard or code
                if ( $record && $record->{node}->type eq 'list_view' && ( $hdr->{code} == -100 || $hdr->{code} == -2 ) ) {
                    return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                    my $should_notify = 0;
                    if ( $hdr->{code} == -2 ) {    # NM_CLICK
                        my $node = $record->{node};

                        # Virtual Checkbox Handling via Hit-Test
                        if ( $node->virtual && $node->checkboxes ) {
                            my $pt_buf = malloc( sizeof( POINT() ) );
                            GetCursorPos($pt_buf);
                            ScreenToClient( $record->{hwnd}, $pt_buf );
                            my $ht_buf = malloc( sizeof( LVHITTESTINFO() ) );
                            my $ht     = cast( $ht_buf, LVHITTESTINFO() );
                            $ht->{pt}{x} = cast( $pt_buf, POINT() )->{x};
                            $ht->{pt}{y} = cast( $pt_buf, POINT() )->{y};
                            SendMessageW( $record->{hwnd}, 0x1012, 0, Affix::address($ht_buf) );    # LVM_HITTEST

                            if ( ( $ht->{flags} & 0x0008 ) && $ht->{iItem} >= 0 ) {                 # LVHT_ONITEMSTATEICON (0x0008)
                                my $iItem = $ht->{iItem};
                                my $row;
                                if ( $node->on_row ) {
                                    $row = $node->on_row->($iItem);
                                }
                                if ( $row && $node->on_check ) {
                                    my $is_chk = ref $row eq 'HASH' ? ( $row->{checked} // 0 ) : 0;
                                    my $action = $node->on_check->( $iItem, $row, $is_chk ? 0 : 1 );
                                    $self_ref->channel->put($action) if $action;
                                }
                                free($ht_buf);
                                free($pt_buf);
                                return 0;    # Handled!
                            }
                            free($ht_buf);
                            free($pt_buf);
                        }
                        $should_notify = 1;
                    }
                    elsif ( $hdr->{code} == -100 ) {    # LVN_ITEMCHANGED
                        my $nmlv = cast( $lparam, NMLISTVIEW() );
                        my $node = $record->{node};

                        # Row Checkbox Toggled (Standard non-virtual mode)
                        if ( !$node->virtual && $node->checkboxes && $node->on_check ) {
                            my $old_chk = ( $nmlv->{uOldState} >> 12 ) & 3;
                            my $new_chk = ( $nmlv->{uNewState} >> 12 ) & 3;
                            if ( ( $new_chk == 1 || $new_chk == 2 ) && $new_chk != $old_chk ) {
                                my $is_chk = ( $new_chk == 2 ? 1 : 0 );
                                my $row    = ( $nmlv->{iItem} >= 0 && $nmlv->{iItem} < @{ $node->rows } ) ? $node->rows->[ $nmlv->{iItem} ] : undef;
                                my $action = $node->on_check->( $nmlv->{iItem}, $row, $is_chk );
                                $self_ref->channel->put($action) if $action;
                            }
                        }

                        # Only notify on selection GAINED (ignore transient deselections)
                        if ( ( $nmlv->{uNewState} & 0x0002 ) && !( $nmlv->{uOldState} & 0x0002 ) ) {
                            $should_notify = 1;
                        }
                    }
                    if ($should_notify) {
                        my $node = $record->{node};
                        if ( $node->on_select ) {
                            my $indices = $self_ref->_get_list_view_selected_indices( $record->{hwnd} );
                            my $rows    = $node->rows // [];
                            if ( $node->multiselect ) {
                                my @sel_rows = map { $node->on_row ? $node->on_row->($_) : ( $_ >= 0 && $_ < @$rows ) ? $rows->[$_] : () } @$indices;
                                my $action_msg = $node->on_select->( $indices, \@sel_rows );
                                $self_ref->channel->put($action_msg) if $action_msg;
                            }
                            else {
                                my $first_idx = @$indices ? $indices->[0] : -1;
                                my $first_row
                                    = $node->on_row                            ? ( $first_idx >= 0 ? $node->on_row->($first_idx) : undef ) :
                                    ( $first_idx >= 0 && $first_idx < @$rows ) ? $rows->[$first_idx] :
                                    undef;
                                my $action_msg = $node->on_select->( $first_idx, $first_row );
                                $self_ref->channel->put($action_msg) if $action_msg;
                            }
                        }
                    }
                }

                # NM_DBLCLK (-3) or NM_RETURN (-4) -> Double-click or Enter activation
                if ( $record && $record->{node}->type eq 'list_view' && ( $hdr->{code} == -3 || $hdr->{code} == -4 ) ) {
                    my $node    = $record->{node};
                    my $row_idx = -1;
                    my $col_idx = -1;
                    if ( $hdr->{code} == -3 ) {
                        my $nma = cast( $lparam, NMITEMACTIVATE() );
                        $row_idx = $nma->{iItem};
                        $col_idx = $nma->{iSubItem};
                    }
                    else {
                        my $indices = $self_ref->_get_list_view_selected_indices( $record->{hwnd} );
                        $row_idx = $indices->[0] if @$indices;
                    }
                    my $cols = $node->columns // [];
                    if ( $node->on_edit && $col_idx >= 0 && $col_idx <= $#$cols && $cols->[$col_idx]{editable} ) {
                        $self_ref->_start_inplace_edit( $record, $row_idx, $col_idx );
                        return 0;
                    }
                    elsif ( $node->on_activate && $row_idx >= 0 ) {
                        my $row;
                        if ( $node->on_row ) {
                            $row = $node->on_row->($row_idx);
                        }
                        else {
                            my $rows = $node->rows // [];
                            $row = $row_idx < @$rows ? $rows->[$row_idx] : undef;
                        }
                        my $action_msg = $node->on_activate->( $row_idx, $row );
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                }

                # LVN_KEYDOWN (-155) -> F2 (edit) or Space (checkbox)
                if ( $record && $record->{node}->type eq 'list_view' && $hdr->{code} == -155 ) {
                    my $wVKey = cast( Affix::address($lparam) + 24, 'UShort' );    # offset 24 on x64
                    my $node  = $record->{node};
                    if ( $wVKey == 0x71 ) {                                        # VK_F2
                        my $indices = $self_ref->_get_list_view_selected_indices( $record->{hwnd} );
                        if (@$indices) {
                            my $row_idx = $indices->[0];
                            my $cols    = $node->columns // [];
                            for my $c ( 0 .. $#$cols ) {
                                if ( $cols->[$c]{editable} ) {
                                    $self_ref->_start_inplace_edit( $record, $row_idx, $c );
                                    last;
                                }
                            }
                        }
                    }
                    elsif ( $wVKey == 0x20 && $node->virtual && $node->checkboxes ) {    # VK_SPACE
                        my $indices = $self_ref->_get_list_view_selected_indices( $record->{hwnd} );
                        for my $iItem (@$indices) {
                            my $row;
                            if ( $node->on_row ) {
                                $row = $node->on_row->($iItem);
                            }
                            if ( $row && $node->on_check ) {
                                my $is_chk     = ref $row eq 'HASH' ? ( $row->{checked} // 0 ) : 0;
                                my $action_msg = $node->on_check->( $iItem, $row, $is_chk ? 0 : 1 );
                                $self_ref->channel->put($action_msg) if $action_msg;
                            }
                        }
                    }
                }

                # LVN_COLUMNCLICK (-108) -> User clicked a column header
                if ( $record && $record->{node}->type eq 'list_view' && $hdr->{code} == -108 ) {
                    my $nmlv    = cast( $lparam, NMLISTVIEW() );
                    my $col_idx = $nmlv->{iSubItem};
                    my $node    = $record->{node};
                    if ( $node->on_sort && $node->columns && $col_idx <= $#{ $node->columns } ) {
                        my $col_id   = $node->columns->[$col_idx]{id} // $node->columns->[$col_idx]{text};
                        my $curr_dir = ( ( $node->sort_column // '' ) eq $col_id ) ? ( $node->sort_direction // 'asc' ) : 'desc';
                        my $new_dir  = ( $curr_dir eq 'asc' )                      ? 'desc'                             : 'asc';
                        my $action   = $node->on_sort->( $col_id, $new_dir );
                        $self_ref->channel->put($action) if $action;
                    }
                }

                # LVN_GETDISPINFOW (-177) -> Virtual Mode row data provider
                if ( $record && $record->{node}->type eq 'list_view' && $hdr->{code} == -177 ) {
                    my $di    = cast( $lparam, NMLVDISPINFOW() );
                    my $node  = $record->{node};
                    my $r_idx = $di->{iItem};
                    my $c_idx = $di->{iSubItem};
                    my $cols  = $node->columns // [];
                    my $row;
                    if ( $node->on_row ) {
                        $row = $node->on_row->($r_idx);
                    }
                    elsif ( $r_idx >= 0 && $r_idx < @{ $node->rows // [] } ) {
                        $row = $node->rows->[$r_idx];
                    }
                    if ($row) {
                        if ( $di->{mask} & 0x0001 ) {    # LVIF_TEXT
                            my $cid       = ( $c_idx <= $#$cols ) ? ( $cols->[$c_idx]{id} // $cols->[$c_idx]{text} // '' ) : '';
                            my $val       = ref $row eq 'HASH'    ? ( $row->{$cid} // '' ) : ( $row->[$c_idx] // '' );
                            my $utf16     = Encode::encode( 'UTF-16LE', "$val\0" );
                            my $max_bytes = ( $di->{cchTextMax} - 1 ) * 2;
                            my $copy_len  = length($utf16) > $max_bytes ? $max_bytes : length($utf16);
                            memcpy( $di->{pszText}, $utf16, $copy_len );
                        }
                        if ( ( $di->{mask} & 0x0008 ) && ( $di->{stateMask} & 0x3000 ) ) {    # LVIF_STATE, LVIS_STATEIMAGEMASK
                            my $is_chk = ref $row eq 'HASH' ? ( $row->{checked} // 0 ) : 0;
                            $di->{state} = ( $is_chk ? 2 : 1 ) << 12;
                        }
                    }
                    return 0;
                }
                if ( $record && $record->{node}->type eq 'date_picker' && $hdr->{code} == -759 ) {
                    my $change = cast( $lparam, NMDATETIMECHANGE() );
                    my $node   = $record->{node};
                    if ( $node->on_change ) {
                        my $value = $change->{dwFlags} == 1 ? '' :
                            sprintf( '%04d-%02d-%02d', $change->{st}{wYear}, $change->{st}{wMonth}, $change->{st}{wDay} );
                        my $action_msg = $node->on_change->($value);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                }
                if ( $record && $record->{node}->type eq 'tab_panel' && $hdr->{code} == -551 ) {
                    my $idx  = SendMessageW( $record->{hwnd}, 0x130B, 0, 0 );    # TCM_GETCURSEL
                    my $node = $record->{node};
                    if ( $node->on_select ) {
                        my $action_msg = $node->on_select->($idx);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                }
            }
            elsif ( $msg == 0x0115 ) {    # WM_VSCROLL -> ScrollView vertical scroll
                my $record = $self_ref->_get_registry_by_hwnd($hwnd);
                if ( $record && $record->{node}->type eq 'scroll_view' ) {
                    $self_ref->_handle_vscroll( $record, $wparam );
                    return 0;
                }
            }
            elsif ( $msg == 0x020A ) {    # WM_MOUSEWHEEL -> forward mousewheel to scrollview
                $self_ref->_handle_mousewheel( $hwnd, $wparam );
                return 0;
            }
            elsif ( $msg == 0x0002 ) {    # WM_DESTROY -> only quit if the root main window is destroyed
                if ( defined $main_hwnd && Affix::address($hwnd) == $main_hwnd ) {
                    $self_ref->channel->put( { type => 'QUIT' } );
                }
            }
            elsif ( $msg == 0x0005 ) {    # WM_SIZE -> window was resized
                my $addr = Affix::address($hwnd);
                if ( defined $main_hwnd && $addr == $main_hwnd ) {

                    # Only the top-level window triggers root layout recomputation
                    my $cw = $lparam & 0xFFFF;
                    my $ch = ( $lparam >> 16 ) & 0xFFFF;
                    $self_ref->channel->put( { type => 'RESIZE' } );
                    my $cb = $self_ref->_get_resize_handler;
                    $cb->( $cw, $ch ) if $cb;
                }
                else {
                    # Child sub-window (ScrollView) was resized; refresh its scrollbar metrics
                    my $rec = $self_ref->_get_registry_by_hwnd($hwnd);
                    if ( $rec && $rec->{node}->type eq 'scroll_view' ) {
                        $self_ref->_update_scroll_info( $rec->{node}->id );
                    }
                }
            }
            elsif ( $msg == 0x0024 ) {    # WM_GETMINMAXINFO -> clamp main window track sizes
                my $addr = Affix::address($hwnd);
                if ( defined $main_hwnd && $addr == $main_hwnd ) {
                    my $vn = $self_ref->main_vnode;
                    if ($vn) {
                        my $mmi = cast( $lparam, MINMAXINFO() );
                        my ( $min_w, $min_h ) = ( $vn->min_w, $vn->min_h );
                        my ( $max_w, $max_h ) = ( $vn->max_w, $vn->max_h );
                        if ( $min_w || $min_h || $max_w || $max_h ) {
                            if ( $min_w || $min_h ) {
                                my ( $ow, $oh ) = $self_ref->_frame_size_for_client( $min_w || 1, $min_h || 1 );
                                $mmi->{ptMinTrackSize}{x} = $ow if $min_w;
                                $mmi->{ptMinTrackSize}{y} = $oh if $min_h;
                            }
                            if ( $max_w || $max_h ) {
                                my ( $ow, $oh ) = $self_ref->_frame_size_for_client( $max_w || 1, $max_h || 1 );
                                $mmi->{ptMaxTrackSize}{x} = $ow if $max_w;
                                $mmi->{ptMaxTrackSize}{y} = $oh if $max_h;
                            }
                            return 0;
                        }
                    }
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
            }
            elsif ( $msg == 0x0114 ) {    # WM_HSCROLL -> slider/trackbar drag
                my $slider_hwnd = $lparam;
                my $record      = $self_ref->_get_registry_by_hwnd($slider_hwnd);
                if ($record) {
                    my $node = $record->{node};
                    if ( $node->can('on_change') && $node->on_change ) {
                        my $pos = SendMessageW( $slider_hwnd, 0x0400, 0, 0 );    # TBM_GETPOS
                        my $msg = $node->on_change->($pos);
                        $self_ref->channel->put($msg) if $msg;
                    }
                }
            }

            # Paint native grey background for splitter bars
            if ( $msg == 0x0014 ) {    # WM_ERASEBKGND
                my $rec = $self_ref->_get_registry_by_hwnd($hwnd);
                if ( $rec && $rec->{node}->type eq 'split_view' ) {
                    my $hdc  = cast( $wparam, Pointer [Void] );
                    my $rptr = malloc( sizeof( RECT() ) );
                    GetClientRect( $hwnd, $rptr );
                    FillRect( $hdc, $rptr, cast( 16, Pointer [Void] ) );    # 16 = COLOR_BTNFACE + 1
                    free($rptr);
                    return 1;
                }
            }

            # Sizing mouse cursors on hover over splitter bars
            if ( $msg == 0x0020 ) {    # WM_SETCURSOR
                my $rec = $self_ref->_get_registry_by_hwnd($hwnd);
                if ( $rec && $rec->{node}->type eq 'split_view' ) {
                    my $cur = $rec->{node}->orientation eq 'vertical' ? 32645 : 32644;    # IDC_SIZENS (32645), IDC_SIZEWE (32644)
                    SetCursor( LoadCursorW( undef, $cur ) );
                    return 1;
                }
            }

            # Start dragging splitter bar
            if ( $msg == 0x0201 ) {    # WM_LBUTTONDOWN
                my $rec = $self_ref->_get_registry_by_hwnd($hwnd);
                if ( $rec && $rec->{node}->type eq 'split_view' ) {
                    SetCapture($hwnd);
                    $self_ref->_start_splitter_drag($rec);
                    return 0;
                }
            }

            # Dragging splitter bar
            if ( $msg == 0x0200 ) {    # WM_MOUSEMOVE
                if ( $self_ref->_is_dragging_splitter ) {
                    $self_ref->_update_splitter_drag();
                    return 0;
                }
            }

            # End dragging splitter bar
            if ( $msg == 0x0202 ) {    # WM_LBUTTONUP
                if ( $self_ref->_is_dragging_splitter ) {
                    ReleaseCapture();
                    $self_ref->_end_splitter_drag();
                    return 0;
                }
            }
            return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
        };
        my $wndclass = malloc( sizeof( WNDCLASSEXW() ) );
        my $wc       = cast( $wndclass, WNDCLASSEXW() );
        $wc->{cbSize}        = sizeof( WNDCLASSEXW() );
        $wc->{style}         = 0x0003;
        $wc->{lpfnWndProc}   = $wndproc_cb;
        $wc->{hInstance}     = undef;
        $wc->{hCursor}       = LoadCursorW( undef, 32512 );
        $wc->{hbrBackground} = cast( 6, Pointer [Void] );
        $wc->{lpszClassName} = 'UjiWindowClass';
        RegisterClassExW($wndclass);
    }

    method _get_text ($hwnd) {
        my $len = GetWindowTextLengthW($hwnd);
        return '' if $len <= 0;
        my $buf       = malloc( ( $len + 1 ) * sizeof(WChar) );
        my $copied    = GetWindowTextW( $hwnd, $buf, $len + 1 );
        my $raw_bytes = Affix::raw( $buf, $copied * sizeof(WChar) );
        free($buf);
        my $text = Encode::decode( 'UTF-16LE', $raw_bytes );
        $text =~ s/\r\n/\n/g;
        return $text;
    }
    method _get_registry_record ($id) { $registry->{$id} }

    method _get_registry_by_hwnd ($hwnd) {
        my $addr = Affix::address($hwnd);
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless defined $rec->{hwnd};
            return $rec if Affix::address( $rec->{hwnd} ) == $addr;
            return $rec if defined $rec->{aux_hwnd} && Affix::address( $rec->{aux_hwnd} ) == $addr;
        }
        return undef;
    }

    method _option_index ( $node, $value ) {
        my $options = $node->options;
        for my $i ( 0 .. $#$options ) {
            return $i if ( $options->[$i]{value} // '' ) eq ( $value // '' );
        }
        return -1;
    }
    method _option_label ($opt) { $opt->{label} // $opt->{value} // '' }

    method _populate_options ( $hwnd, $node, $kind ) {
        my ( $reset, $add ) = $kind eq 'combo_box' ? ( 0x014B, 0x0143 ) : ( 0x0184, 0x0180 );
        SendMessageW( $hwnd, $reset, 0, 0 );
        SendMessageWStr( $hwnd, $add, 0, $self->_option_label($_) ) for @{ $node->options };
    }

    method _set_combo_value ( $hwnd, $node, $value ) {
        my $idx = $self->_option_index( $node, $value );
        SendMessageW( $hwnd, 0x014E, $idx, 0 ) if $idx >= 0;
        if ( $node->editable ) {
            my $text = $idx >= 0 ? $self->_option_label( $node->options->[$idx] ) : $value;
            $suppress_events = 1;
            SetWindowTextW( $hwnd, $text );
            $suppress_events = 0;
        }
    }

    method _set_list_selection ( $hwnd, $node, $value ) {
        my $idx = $self->_option_index( $node, $value );
        SendMessageW( $hwnd, 0x0186, $idx, 0 );
    }

    method _native_newlines ($text) {
        $text =~ s/\r?\n/\r\n/g;
        return $text;
    }

    method _set_spin_range ( $record, $min, $max ) {
        SendMessageW( $record->{aux_hwnd}, 0x046F, $min, $max );
    }

    method _set_spin_accel ( $record, $step ) {
        $step = 1 unless $step && $step > 0;
        my $buf = malloc( sizeof( UDACCEL() ) );
        my $acc = cast( $buf, UDACCEL() );
        $acc->{nSec} = 0;
        $acc->{nInc} = $step;
        SendMessageW( $record->{aux_hwnd}, 0x046B, 1, Affix::address($buf) );
        free($buf);
    }

    method _set_spin_value ( $record, $value ) {
        $suppress_events = 1;
        SendMessageW( $record->{aux_hwnd}, 0x0471, 0, $value );
        SetWindowTextW( $record->{hwnd}, '' . $value );
        $suppress_events = 0;
    }

    method _set_date_value ( $hwnd, $value ) {
        return unless $value =~ /^(\d{4})-(\d{2})-(\d{2})$/;
        my ( $year, $month, $day ) = ( $1, $2, $3 );
        my $buf = malloc( sizeof( SYSTEMTIME() ) );
        my $st  = cast( $buf, SYSTEMTIME() );
        $st->{wYear}         = $year;
        $st->{wMonth}        = $month;
        $st->{wDay}          = $day;
        $st->{wDayOfWeek}    = 0;
        $st->{wHour}         = 0;
        $st->{wMinute}       = 0;
        $st->{wSecond}       = 0;
        $st->{wMilliseconds} = 0;
        SendMessageW( $hwnd, 0x1002, 0, Affix::address($buf) );
        free($buf);
    }
    method _is_mounted () { $main_hwnd ? 1 : 0 }

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };
        if ( $node->type eq 'window' ) {
            $main_vnode = $node;
        }
    }

    method mount ($vtree) {
        $main_vnode = $vtree;

        # Auto-size window to intrinsic content size when width or height are not explicitly specified
        my ( $req_cw, $req_ch );
        if ( ( !$vtree->w || !$vtree->h ) && $vtree->child ) {
            my $temp_layout = Uji::Layout->new( driver => $self );
            my ( $iw, $ih ) = $temp_layout->_intrinsic( $vtree->child );
            $req_cw = $vtree->w || ( $iw < 360 ? 360 : $iw );
            $req_ch = $vtree->h || ( $ih < 220 ? 220 : $ih );
        }
        else {
            $req_cw = $vtree->w || 640;
            $req_ch = $vtree->h || 480;
        }

        # Calculate initial outer dimensions (client area + title bar + borders)
        my ( $init_ow, $init_oh ) = $self->_frame_size_for_client( $req_cw, $req_ch );

        # WS_OVERLAPPEDWINDOW (0x10CF0000); drop WS_THICKFRAME (0x00040000) when not resizable
        my $style = $vtree->resizable ? 0x10CF0000 : 0x10CB0000;
        $main_hwnd = CreateWindowExW( 0, 'UjiWindowClass', $vtree->title, $style, 100, 100, $init_ow, $init_oh, undef, 0, undef, undef );
        $registry->{ $vtree->id } = { hwnd => $main_hwnd, node => $vtree };

        # Lay out against real measured client area
        my ( $cw, $ch ) = $self->_get_client_size($main_hwnd);
        $vtree->set_bounds( 0, 0, $cw, $ch );

        # Centering window on screen
        if ( $vtree->centered ) {
            $self->_set_window_outer( $main_hwnd, $cw, $ch, 'center' );
            my ( $nw, $nh ) = $self->_get_client_size($main_hwnd);
            $vtree->set_bounds( 0, 0, $nw, $nh );
        }

        # Boot the menu bar early
        if ( $vtree->can('menu_bar') && $vtree->menu_bar ) {
            $self->_mount_menu_bar( $main_hwnd, $vtree->menu_bar );
        }
        SetWindowPos( $main_hwnd, $vtree->topmost ? -1 : -2, 0, 0, 0, 0, 0x0003 ) if $vtree->topmost;
        ShowWindow( $main_hwnd, $vtree->maximized ? 3 : $vtree->minimized ? 2 : 5 );
        UpdateWindow($main_hwnd);
    }

    method mount_widget ( $vnode, $parent_node_id = undef ) {
        my $parent_hwnd      = $main_hwnd;
        my $parent_scroll_id = undef;
        if ($parent_node_id) {
            my $prec = $registry->{$parent_node_id};
            if ($prec) {
                $parent_hwnd      = $prec->{hwnd} || $prec->{parent_hwnd} || $main_hwnd;
                $parent_scroll_id = ( $prec->{node}->type eq 'scroll_view' ) ? $prec->{node}->id : $prec->{parent_scroll_id};
            }
        }
        $self->_mount_node( $vnode, $parent_hwnd, $parent_scroll_id );
        if ($parent_scroll_id) {
            $self->_update_scroll_info($parent_scroll_id);
        }
        RedrawWindow( $parent_hwnd, undef, undef, 0x0185 );
    }

    method _mount_menu_bar ( $hwnd, $menu_bar_node ) {
        my $hmenu_bar = CreateMenu();
        for my $m ( @{ $menu_bar_node->menus } ) {
            my $hpopup = CreatePopupMenu();
            for my $item ( @{ $m->items } ) {
                if ( $item->type eq 'menu_separator' ) {
                    AppendMenuW( $hpopup, 0x0800, 0, undef );    # MF_SEPARATOR
                }
                elsif ( $item->type eq 'menu_item' ) {
                    $registry->{ $item->id } = { hwnd => undef, node => $item };
                    my $text  = $item->label . ( $item->shortcut ? "\t" . $item->shortcut : '' );
                    my $flags = 0x0000;                                                             # MF_STRING
                    $flags |= 0x0008 if $item->checked;                                             # MF_CHECKED
                    $flags |= 0x0001 unless $item->enabled;                                         # MF_GRAYED
                    AppendMenuW( $hpopup, $flags, $item->id, $text );
                }
            }
            AppendMenuW( $hmenu_bar, 0x0010, Affix::address($hpopup), $m->label );                  # MF_POPUP
        }
        SetMenu( $hwnd, $hmenu_bar );
        DrawMenuBar($hwnd);
    }

    # Shows an interactive right-click context menu and dispatches selection via WM_COMMAND
    method _show_context_menu ( $record, $lparam ) {
        my $node = $record->{node};
        my ( $screen_x, $screen_y );
        my $lx = $lparam & 0xFFFF;
        my $ly = ( $lparam >> 16 ) & 0xFFFF;
        $lx = $lx - 0x10000 if $lx > 0x7FFF;
        $ly = $ly - 0x10000 if $ly > 0x7FFF;
        if ( $lx == -1 && $ly == -1 ) {
            my $pt_buf = malloc( sizeof( POINT() ) );
            GetCursorPos($pt_buf);
            my $pt = cast( $pt_buf, POINT() );
            ( $screen_x, $screen_y ) = ( $pt->{x}, $pt->{y} );
            free($pt_buf);
        }
        else {
            ( $screen_x, $screen_y ) = ( $lx, $ly );
        }
        my $menu_def = $node->context_menu;
        my $cm;
        if ( ref $menu_def eq 'CODE' ) {
            if ( $node->type eq 'list_view' ) {
                my $indices = $self->_get_list_view_selected_indices( $record->{hwnd} );
                my $rows    = $node->rows // [];

                # If no row is selected, hit-test the item under the mouse cursor
                if ( !@$indices ) {
                    my $pt_buf = malloc( sizeof( POINT() ) );
                    my $pt     = cast( $pt_buf, POINT() );
                    $pt->{x} = $screen_x;
                    $pt->{y} = $screen_y;
                    ScreenToClient( $record->{hwnd}, $pt_buf );
                    my $ht_buf = malloc( sizeof( LVHITTESTINFO() ) );
                    my $ht     = cast( $ht_buf, LVHITTESTINFO() );
                    $ht->{pt}{x} = $pt->{x};
                    $ht->{pt}{y} = $pt->{y};
                    SendMessageW( $record->{hwnd}, 0x1012, 0, Affix::address($ht_buf) );    # LVM_HITTEST
                    my $hit_idx = $ht->{iItem};
                    free($ht_buf);
                    free($pt_buf);

                    if ( $hit_idx >= 0 && $hit_idx < @$rows ) {
                        $indices = [$hit_idx];

                        # Select the right-clicked row natively
                        my $sptr  = malloc( sizeof( LVITEMW() ) );
                        my $sitem = cast( $sptr, LVITEMW() );
                        $sitem->{state}     = 0x0002 | 0x0001;
                        $sitem->{stateMask} = 0x0002 | 0x0001;
                        SendMessageW( $record->{hwnd}, 0x102B, $hit_idx, Affix::address($sptr) );
                        free($sptr);
                    }
                }
                if ( $node->multiselect ) {
                    my @sel_rows = map { ( $_ >= 0 && $_ < @$rows ) ? $rows->[$_] : () } @$indices;
                    $cm = $menu_def->( $indices, \@sel_rows );
                }
                else {
                    my $idx = @$indices                      ? $indices->[0] : -1;
                    my $row = ( $idx >= 0 && $idx < @$rows ) ? $rows->[$idx] : undef;
                    $cm = $menu_def->( $idx, $row );
                }
            }
            else {
                $cm = $menu_def->();
            }
        }
        else {
            $cm = $menu_def;
        }
        return unless $cm && $cm->can('items');
        my $hpopup = CreatePopupMenu();
        for my $item ( @{ $cm->items } ) {
            if ( $item->type eq 'menu_separator' ) {
                AppendMenuW( $hpopup, 0x0800, 0, undef );
            }
            elsif ( $item->type eq 'menu_item' ) {
                $registry->{ $item->id } = { hwnd => undef, node => $item };
                my $text  = $item->label . ( $item->shortcut ? "\t" . $item->shortcut : '' );
                my $flags = 0x0000;
                $flags |= 0x0008 if $item->checked;
                $flags |= 0x0001 unless $item->enabled;
                AppendMenuW( $hpopup, $flags, $item->id, $text );
            }
        }
        TrackPopupMenuEx( $hpopup, 0x0000, $screen_x, $screen_y, $main_hwnd, undef );
        DestroyMenu($hpopup);
    }

    method destroy_widget ($id) {
        $self->_commit_inplace_edit(0) if $active_inplace_edit && $active_inplace_edit->{record}{node}->id == $id;
        my $record = delete $registry->{$id};
        return unless $record;
        if ( my $hwnd = $record->{hwnd} ) {
            $self->_set_tooltip( $hwnd, undef );
            DestroyWindow($hwnd);
        }
        if ( my $aux_hwnd = $record->{aux_hwnd} ) {
            $self->_set_tooltip( $aux_hwnd, undef );
            DestroyWindow($aux_hwnd);
        }
    }

    method _frame_size_for_client ( $cw, $ch ) {
        my $rect_ptr = malloc( sizeof( RECT() ) );
        my $rect     = cast( $rect_ptr, RECT() );
        $rect->{left}   = 0;
        $rect->{top}    = 0;
        $rect->{right}  = $cw;
        $rect->{bottom} = $ch;
        AdjustWindowRectEx( $rect_ptr, 0x10CF0000, 0, 0 );
        my ( $w, $h ) = ( $rect->{right} - $rect->{left}, $rect->{bottom} - $rect->{top} );
        free($rect_ptr);
        return ( $w, $h );
    }

    method _set_window_outer ( $hwnd, $cw, $ch, $mode = 'none' ) {
        my $rect_ptr = malloc( sizeof( RECT() ) );
        my $rect     = cast( $rect_ptr, RECT() );
        $rect->{left}   = $rect->{top} = 0;
        $rect->{right}  = $cw;
        $rect->{bottom} = $ch;
        AdjustWindowRectEx( $rect_ptr, 0x10CF0000, 0, 0 );
        my ( $ow, $oh ) = ( $rect->{right} - $rect->{left}, $rect->{bottom} - $rect->{top} );
        my ( $x,  $y );

        if ( $mode eq 'center' ) {
            my $sw = GetSystemMetrics(0);
            my $sh = GetSystemMetrics(1);
            $x = int( ( $sw - $ow ) / 2 );
            $y = int( ( $sh - $oh ) / 2 );
        }
        else {
            my $wrect_ptr = malloc( sizeof( RECT() ) );
            my $wrect     = cast( $wrect_ptr, RECT() );
            GetWindowRect( $hwnd, $wrect_ptr );
            ( $x, $y ) = ( $wrect->{left}, $wrect->{top} );
            free($wrect_ptr);
        }
        SetWindowPos( $hwnd, undef, $x, $y, $ow, $oh, 0x0004 );
        free($rect_ptr);
    }

    # Lazily create shared tooltip control
    method _ensure_tooltip () {
        return $tooltip_hwnd if $tooltip_hwnd;
        $tooltip_hwnd = CreateWindowExW( 0, 'tooltips_class32', undef, 0x80000003, 0, 0, 0, 0, $main_hwnd, 0, undef, undef );
        return $tooltip_hwnd;
    }

    method _set_tooltip ( $hwnd, $text ) {
        return unless $hwnd;
        my $tip = $tooltip_hwnd || $self->_ensure_tooltip();
        return unless $tip;
        my $ti_ptr = malloc( sizeof( TOOLINFO() ) );
        my $ti     = cast( $ti_ptr, TOOLINFO() );
        $ti->{cbSize} = sizeof( TOOLINFO() );
        $ti->{uFlags} = 0x0001 | 0x0010;
        $ti->{hwnd}   = $main_hwnd;
        $ti->{uId}    = $hwnd;
        SendMessageW( $tip, 0x0433, 0, Affix::address($ti_ptr) );

        if ( defined $text ) {
            $ti->{lpszText} = $text;
            SendMessageW( $tip, 0x0432, 0, Affix::address($ti_ptr) );
        }
        free($ti_ptr);
    }

    method sync_window_bounds ($vtree) {
        return unless $main_hwnd;
        my ( $cw, $ch ) = $self->_get_client_size($main_hwnd);
        $vtree->set_bounds( 0, 0, $cw, $ch );
    }

    method mount_children ($vtree) {
        if ( $vtree->child ) {
            $self->_mount_node( $vtree->child, $main_hwnd );

            # Force all child windows and sub-views to paint synchronously on startup
            RedrawWindow( $main_hwnd, undef, undef, 0x0185 );
        }
    }

    method _get_client_size ($hwnd) {
        my $rect = malloc( sizeof( RECT() ) );
        my $r    = cast( $rect, RECT() );
        GetClientRect( $hwnd, $rect );
        my ( $w, $h ) = ( $r->{right} - $r->{left}, $r->{bottom} - $r->{top} );
        free($rect);
        return ( $w, $h );
    }

    method measure_text ( $text, $font_hwnd = $main_hwnd ) {
        my $dc = GetDC($font_hwnd);
        return ( 0, 0 ) unless $dc;

        # Select standard GUI font for measurement
        SelectObject( $dc, $gui_font );
        my $buf = malloc( sizeof( SIZE() ) );
        my $sz  = cast( $buf, SIZE() );
        GetTextExtentPoint32W( $dc, $text, length $text, $buf );
        my ( $w, $h ) = ( $sz->{cx}, $sz->{cy} );
        free($buf);
        ReleaseDC( $font_hwnd, $dc );
        return ( $w, $h );
    }

    method poll_events () {
        my $msg_ptr = malloc(48);
        while ( PeekMessageW( $msg_ptr, undef, 0, 0, 1 ) ) {
            TranslateMessage($msg_ptr);
            DispatchMessageW($msg_ptr);
        }
        free($msg_ptr);
    }

    method _update_scroll_info ($vnode_id) {
        my $record = $registry->{$vnode_id};
        return unless $record && $record->{hwnd};
        my $node       = $record->{node};
        my $viewport_h = $node->bh;
        my $content_h  = $node->content_h || $viewport_h;
        my $sptr       = malloc( sizeof( SCROLLINFO() ) );
        my $si         = cast( $sptr, SCROLLINFO() );
        $si->{cbSize} = sizeof( SCROLLINFO() );
        $si->{fMask}  = 0x0001 | 0x0002 | 0x0004;         # SIF_RANGE | SIF_PAGE | SIF_POS
        $si->{nMin}   = 0;
        $si->{nMax}   = $content_h;
        $si->{nPage}  = $viewport_h;
        $si->{nPos}   = $record->{scroll_y} // 0;
        SetScrollInfo( $record->{hwnd}, 1, $sptr, 1 );    # 1 = SB_VERT
        free($sptr);
    }

    method _handle_vscroll ( $record, $wparam ) {
        my $action      = $wparam & 0xFFFF;
        my $scroll_hwnd = $record->{hwnd};
        my $sptr        = malloc( sizeof( SCROLLINFO() ) );
        my $si          = cast( $sptr, SCROLLINFO() );
        $si->{cbSize} = sizeof( SCROLLINFO() );
        $si->{fMask}  = 0x0017;                           # SIF_ALL
        GetScrollInfo( $scroll_hwnd, 1, $sptr );
        my $cur_pos = $si->{nPos};
        my $new_pos = $cur_pos;
        my $page    = $si->{nPage};
        my $max_pos = $si->{nMax} - $page + 1;
        $max_pos = 0 if $max_pos < 0;
        if    ( $action == 0 )                 { $new_pos -= 26; }
        elsif ( $action == 1 )                 { $new_pos += 26; }
        elsif ( $action == 2 )                 { $new_pos -= $page; }
        elsif ( $action == 3 )                 { $new_pos += $page; }
        elsif ( $action == 4 || $action == 5 ) { $new_pos = $si->{nTrackPos}; }
        elsif ( $action == 6 )                 { $new_pos = $si->{nMin}; }
        elsif ( $action == 7 )                 { $new_pos = $max_pos; }
        $new_pos = $si->{nMin} if $new_pos < $si->{nMin};
        $new_pos = $max_pos    if $new_pos > $max_pos;
        free($sptr);

        if ( $new_pos != $cur_pos ) {
            $self->_scroll_to_y( $record, $new_pos );
        }
    }

    method _handle_mousewheel ( $hwnd, $wparam ) {
        my $target_rec = $self->_get_registry_by_hwnd($hwnd);
        if ( $target_rec && $target_rec->{parent_scroll_id} ) {
            $target_rec = $self->_get_registry_record( $target_rec->{parent_scroll_id} );
        }
        unless ( $target_rec && $target_rec->{node}->type eq 'scroll_view' ) {
            for my $id ( keys %$registry ) {
                my $r = $registry->{$id};
                if ( $r->{node}->type eq 'scroll_view' ) {
                    $target_rec = $r;
                    last;
                }
            }
        }
        return unless $target_rec && $target_rec->{node}->type eq 'scroll_view';
        my $delta = ( $wparam >> 16 ) & 0xFFFF;
        $delta = $delta - 0x10000 if $delta > 0x7FFF;
        my $step    = int( ( $delta / 120 ) * 38 );
        my $cur_y   = $target_rec->{scroll_y} // 0;
        my $new_y   = $cur_y - $step;
        my $node    = $target_rec->{node};
        my $max_pos = ( $node->content_h || $node->bh ) - $node->bh;
        $max_pos = 0        if $max_pos < 0;
        $new_y   = 0        if $new_y < 0;
        $new_y   = $max_pos if $new_y > $max_pos;
        $self->_scroll_to_y( $target_rec, $new_y ) if $new_y != $cur_y;
    }

    method _scroll_to_y ( $record, $new_y ) {
        my $old_y = $record->{scroll_y} // 0;
        return if $new_y == $old_y;
        $record->{scroll_y} = $new_y;
        my $sptr = malloc( sizeof( SCROLLINFO() ) );
        my $si   = cast( $sptr, SCROLLINFO() );
        $si->{cbSize} = sizeof( SCROLLINFO() );
        $si->{fMask}  = 0x0004;                   # SIF_POS
        $si->{nPos}   = $new_y;
        SetScrollInfo( $record->{hwnd}, 1, $sptr, 1 );
        free($sptr);
        $self->_reposition_scroll_children($record);
        my $node = $record->{node};

        if ( $node->can('on_scroll') && $node->on_scroll ) {
            my $msg = $node->on_scroll->( $record->{scroll_x} // 0, $new_y );
            $channel->put($msg) if $msg;
        }
    }

    method _reposition_scroll_children ($record) {
        my $pid = $record->{node}->id;
        my $sy  = $record->{scroll_y} // 0;
        my $sx  = $record->{scroll_x} // 0;
        my @children;
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless $rec->{parent_scroll_id} && $rec->{parent_scroll_id} == $pid;
            next unless $rec->{hwnd};
            push @children, $rec;
        }
        if (@children) {
            my $flags = 0x0004 | 0x0010 | 0x0100;                   # SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOCOPYBITS
            my $hdwp  = BeginDeferWindowPos( scalar(@children) );
            if ($hdwp) {
                for my $rec (@children) {
                    my $n = $rec->{node};
                    $hdwp = DeferWindowPos( $hdwp, $rec->{hwnd}, undef, $n->bx - $sx, $n->by - $sy, $n->bw, $n->bh, $flags );
                }
                EndDeferWindowPos($hdwp) if $hdwp;
            }
            else {
                for my $rec (@children) {
                    my $n = $rec->{node};
                    SetWindowPos( $rec->{hwnd}, undef, $n->bx - $sx, $n->by - $sy, $n->bw, $n->bh, $flags );
                }
            }
        }

        # Redraw the entire scrollview canvas and all children synchronously:
        # RDW_INVALIDATE (0x1) | RDW_ERASE (0x4) | RDW_ALLCHILDREN (0x80) | RDW_UPDATENOW (0x100) = 0x0185
        RedrawWindow( $record->{hwnd}, undef, undef, 0x0185 );
    }

    method _mount_node ( $vnode, $parent_hwnd, $parent_scroll_id = undef ) {
        if ( $vnode->type eq 'spacer' ) {
            return;
        }
        if ( $vnode->type eq 'spin_box' ) {
            $self->_mount_spin_box( $vnode, $parent_hwnd, $parent_scroll_id );
            return;
        }

        # ScrollView container: sub-window with WS_CLIPCHILDREN
        if ( $vnode->type eq 'scroll_view' ) {
            my $style = 0x52200000 | 0x00800000;    # WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_VSCROLL | WS_BORDER
            my $hwnd  = CreateWindowExW( 0, 'UjiWindowClass', undef, $style, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id,
                undef, undef );
            $registry->{ $vnode->id } = {
                hwnd             => $hwnd,
                node             => $vnode,
                parent_hwnd      => $parent_hwnd,
                parent_scroll_id => $parent_scroll_id,
                scroll_y         => $vnode->scroll_y // 0,
                scroll_x         => $vnode->scroll_x // 0
            };
            $self->_update_scroll_info( $vnode->id );
            if ( $vnode->child ) {
                $self->_mount_node( $vnode->child, $hwnd, $vnode->id );
            }
            return;
        }    # SplitView: splitter bar is a native sub-window that handles drag and cursor changes
        if ( $vnode->type eq 'split_view' ) {
            my $style    = 0x54000000;        # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS
            my $bar_hwnd = CreateWindowExW(
                0,              'UjiWindowClass', undef,        $style,     $vnode->bar_bx, $vnode->bar_by,
                $vnode->bar_bw, $vnode->bar_bh,   $parent_hwnd, $vnode->id, undef,          undef
            );
            $registry->{ $vnode->id } = { hwnd => $bar_hwnd, node => $vnode, parent_hwnd => $parent_hwnd, parent_scroll_id => $parent_scroll_id };

            # Mount first and second panes
            $self->_mount_node( $vnode->first,  $parent_hwnd, $parent_scroll_id ) if $vnode->first;
            $self->_mount_node( $vnode->second, $parent_hwnd, $parent_scroll_id ) if $vnode->second;
            return;
        }
        my ( $class, $style, $initial_text );
        if ( $vnode->type eq 'button' ) {
            $class        = 'BUTTON';
            $style        = 0x50000000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text' ) {
            $class        = 'STATIC';
            $style        = 0x50000000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text_input' ) {
            $class        = 'EDIT';
            $style        = 0x50800080;
            $initial_text = $vnode->value // '';
        }
        elsif ( $vnode->type eq 'password' ) {
            $class        = 'EDIT';
            $style        = 0x508000A0;
            $initial_text = $vnode->value // '';
        }
        elsif ( $vnode->type eq 'multiline_text' ) {
            $class        = 'EDIT';
            $style        = 0x50A01044;
            $initial_text = $self->_native_newlines( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'slider' ) {
            $class = 'msctls_trackbar32';
            $style = 0x50000001;
        }
        elsif ( $vnode->type eq 'checkbox' ) {
            $class        = 'BUTTON';
            $style        = 0x50000003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'toggle_switch' ) {
            $class        = 'BUTTON';
            $style        = 0x50001003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'radio' ) {
            $class        = 'BUTTON';
            $style        = $vnode->first ? 0x50020009 : 0x50000009;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'combo_box' ) {
            $class = 'COMBOBOX';
            $style = $vnode->editable ? 0x50200042 : 0x50200003;
        }
        elsif ( $vnode->type eq 'list_box' ) {
            $class = 'LISTBOX';
            $style = 0x50A00001;
        }
        elsif ( $vnode->type eq 'date_picker' ) {
            $class = 'SysDateTimePick32';
            $style = 0x50000000;
        }
        elsif ( $vnode->type eq 'group_box' ) {
            $class        = 'BUTTON';
            $style        = 0x50000007;            # WS_CHILD | WS_VISIBLE | BS_GROUPBOX
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'progress_bar' ) {
            $class = 'msctls_progress32';

            # WS_CHILD | WS_VISIBLE | (PBS_MARQUEE if indeterminate)
            $style = 0x50000000 | ( $vnode->indeterminate ? 0x0008 : 0 );
        }
        elsif ( $vnode->type eq 'tab_panel' ) {
            $class = 'SysTabControl32';
            $style = 0x54000000;                   # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS
        }
        elsif ( $vnode->type eq 'list_view' ) {
            $class = 'SysListView32';

            # Base styles: WS_CHILD | WS_VISIBLE | WS_BORDER | WS_CLIPSIBLINGS | LVS_REPORT (0x1) | LVS_SHOWSELALWAYS (0x8)
            $style = 0x54800009;
            $style |= 0x00000004 unless $vnode->multiselect;    # LVS_SINGLESEL (0x4)
            $style |= 0x00001000 if $vnode->virtual;            # LVS_OWNERDATA (0x1000) for virtual mode
            $style |= 0x00000200 if $vnode->on_edit;            # LVS_EDITLABELS (0x200) for in-place editing
        }
        else {
            $registry->{ $vnode->id } = { hwnd => undef, node => $vnode, parent_hwnd => $parent_hwnd, parent_scroll_id => $parent_scroll_id };
            $self->_mount_node( $_, $parent_hwnd, $parent_scroll_id ) for @{ $vnode->children };
            return;
        }
        my $init_x = $vnode->bx;
        my $init_y = $vnode->by;
        if ($parent_scroll_id) {
            my $prec = $registry->{$parent_scroll_id};
            if ($prec) {
                $init_x -= ( $prec->{scroll_x} // 0 );
                $init_y -= ( $prec->{scroll_y} // 0 );
            }
        }
        my $hwnd
            = CreateWindowExW( 0, $class, $initial_text, $style, $init_x, $init_y, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef, undef );
        $registry->{ $vnode->id } = { hwnd => $hwnd, node => $vnode, parent_hwnd => $parent_hwnd, parent_scroll_id => $parent_scroll_id };
        $self->_apply_font($hwnd);
        EnableWindow( $hwnd, $vnode->enabled ? 1 : 0 );
        ShowWindow( $hwnd, $vnode->visible   ? 5 : 0 );
        $self->_set_tooltip( $hwnd, $vnode->tooltip ) if defined $vnode->tooltip;
        if ( $vnode->type eq 'text_input' || $vnode->type eq 'password' || $vnode->type eq 'multiline_text' ) {
            SendMessageW( $hwnd, 0x00CF, $vnode->readonly ? 1 : 0, 0 );
            SendMessageW( $hwnd, 0x00C5, $vnode->maxlength, 0 ) if $vnode->maxlength;
            SetFocus($hwnd) if $vnode->focused;
        }
        if ( $vnode->type eq 'slider' ) {
            SendMessageW( $hwnd, 0x0406, 1, ( $vnode->max << 16 ) | $vnode->min );
            SendMessageW( $hwnd, 0x0405, 1, $vnode->value );
            SendMessageW( $hwnd, 0x041C, 1, $vnode->step );
            SendMessageW( $hwnd, 0x041D, 1, $vnode->step );
        }
        if ( $vnode->type eq 'checkbox' || $vnode->type eq 'toggle_switch' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->checked ? 1 : 0, 0 );
        }
        if ( $vnode->type eq 'radio' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->selected ? 1 : 0, 0 );
        }
        if ( $vnode->type eq 'combo_box' ) {
            $suppress_events = 1;
            $self->_populate_options( $hwnd, $vnode, 'combo_box' );
            $self->_set_combo_value( $hwnd, $vnode, $vnode->value );
            $suppress_events = 0;
            SetFocus($hwnd) if $vnode->focused;
        }
        if ( $vnode->type eq 'list_box' ) {
            $suppress_events = 1;
            $self->_populate_options( $hwnd, $vnode, 'list_box' );
            $self->_set_list_selection( $hwnd, $vnode, $vnode->selection );
            $suppress_events = 0;
        }
        if ( $vnode->type eq 'date_picker' ) {
            $self->_set_date_value( $hwnd, $vnode->value );
            SetFocus($hwnd) if $vnode->focused;
        }
        if ( $vnode->type eq 'list_view' ) {

            # Enable callback mask for virtual mode checkboxes
            SendMessageW( $hwnd, 0x100B, 0x3000, 0 )    # LVM_SETCALLBACKMASK, LVIS_STATEIMAGEMASK
                if $vnode->virtual && $vnode->checkboxes;
            #
            $self->_populate_list_view( $hwnd, $vnode );

            # If an initial scroll_to_row target was specified at mount time, jump to it immediately
            SendMessageW( $hwnd, 0x1013, $vnode->scroll_to_row, 0 )    # LVM_ENSUREVISIBLE
                if $vnode->can('scroll_to_row') && defined $vnode->scroll_to_row && $vnode->scroll_to_row >= 0;
        }
        if ( $vnode->type eq 'progress_bar' ) {
            SendMessageW( $hwnd, 0x0406, $vnode->min,   $vnode->max );    # PBM_SETRANGE32
            SendMessageW( $hwnd, 0x0402, $vnode->value, 0 );              # PBM_SETPOS
            if ( $vnode->indeterminate ) {
                SendMessageW( $hwnd, 0x040A, 1, 30 );                     # PBM_SETMARQUEE (start, 30ms)
            }
        }

        # If it's a group box, mount its inner children after creating the group box HWND
        if ( $vnode->type eq 'group_box' && $vnode->child ) {
            $self->_mount_node( $vnode->child, $parent_hwnd, $parent_scroll_id );
        }
        if ( $vnode->type eq 'tab_panel' ) {
            my $tabs = $vnode->tabs;
            for my $i ( 0 .. $#$tabs ) {
                my $tb      = $tabs->[$i];
                my $tci_ptr = malloc( sizeof( TCITEMW() ) );
                my $tci     = cast( $tci_ptr, TCITEMW() );
                $tci->{mask}    = 0x0001;                                       # TCIF_TEXT
                $tci->{pszText} = $tb->label;
                SendMessageW( $hwnd, 0x133E, $i, Affix::address($tci_ptr) );    # TCM_INSERTITEMW
                free($tci_ptr);
            }
            SendMessageW( $hwnd, 0x130C, $vnode->selected, 0 );                 # TCM_SETCURSEL
            if ( my $at = $vnode->active_tab ) {
                $self->_mount_node( $at->child, $parent_hwnd, $parent_scroll_id ) if $at->child;
            }
            return;
        }
    }

    # SpinBox = EDIT + UPDOWN buddy control
    method _mount_spin_box ( $vnode, $parent_hwnd, $parent_scroll_id = undef ) {
        my $init_x = $vnode->bx;
        my $init_y = $vnode->by;
        if ($parent_scroll_id) {
            my $prec = $registry->{$parent_scroll_id};
            if ($prec) {
                $init_x -= ( $prec->{scroll_x} // 0 );
                $init_y -= ( $prec->{scroll_y} // 0 );
            }
        }

        # EDIT: WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_NUMBER
        my $edit_style = 0x50800080 | 0x2000;
        my $edit       = CreateWindowExW( 0, 'EDIT', '' . ( $vnode->value // 0 ),
            $edit_style, $init_x, $init_y, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef, undef );

# UPDOWN: WS_CHILD | WS_VISIBLE | UDS_ALIGNRIGHT (0x4) | UDS_SETBUDDYINT (0x2) | UDS_AUTOBUDDY (0x10) | UDS_ARROWKEYS (0x20) | UDS_NOTHOUSANDS (0x80) | UDS_HOTTRACK (0x100)
        my $updown_style = 0x500001B6;
        my $updown       = CreateWindowExW( 0, 'msctls_updown32', undef, $updown_style, 0, 0, 0, 0, $parent_hwnd, 0, undef, undef );
        my $record       = { hwnd => $edit, aux_hwnd => $updown, node => $vnode, parent_scroll_id => $parent_scroll_id };
        $registry->{ $vnode->id } = $record;
        $self->_apply_font($edit);
        $self->_apply_font($updown);

        # Attach buddy: with UDS_ALIGNRIGHT, Windows docks the updown control inside the right edge of edit
        SendMessageW( $updown, 0x0469, $edit, 0 );    # UDM_SETBUDDY
        $self->_set_spin_range( $record, $vnode->min, $vnode->max );
        $self->_set_spin_accel( $record, $vnode->step );
        $self->_set_spin_value( $record, $vnode->value );
        EnableWindow( $edit,   $vnode->enabled ? 1 : 0 );
        EnableWindow( $updown, $vnode->enabled ? 1 : 0 );
        ShowWindow( $edit,   $vnode->visible ? 5 : 0 );
        ShowWindow( $updown, $vnode->visible ? 5 : 0 );

        if ( defined $vnode->tooltip ) {
            $self->_set_tooltip( $edit,   $vnode->tooltip );
            $self->_set_tooltip( $updown, $vnode->tooltip );
        }
        SetFocus($edit) if $vnode->focused;
    }

    method set_prop ( $vnode_id, $prop_name, $value ) {
        my $record = $registry->{$vnode_id};
        return unless $record;
        if ( $prop_name eq 'scroll_y' ) {
            if ( $record->{node}->type eq 'scroll_view' ) {
                $self->_scroll_to_y( $record, $value );
                return;
            }
        }
        elsif ( $prop_name eq 'scroll_to_row' ) {
            if ( $record->{node}->type eq 'list_view' ) {
                if ( defined $value && $value >= 0 ) {
                    SendMessageW( $record->{hwnd}, 0x1013, $value, 0 );    # LVM_ENSUREVISIBLE
                    RedrawWindow( $record->{hwnd}, undef, undef, 0x0185 );
                }
                return;
            }
        }
        elsif ( $prop_name eq 'split' ) {
            if ( $record->{node}->type eq 'split_view' ) {
                my $node = $record->{node};
                SetWindowPos( $record->{hwnd}, undef, $node->bar_bx, $node->bar_by, $node->bar_bw, $node->bar_bh, 0x0004 | 0x0100 );
                return;
            }
        }
        elsif ( $prop_name eq 'title' ) {
            $main_hwnd = $record->{hwnd};
            SetWindowTextW( $main_hwnd, $value );
        }
        elsif ( $prop_name eq 'topmost' ) {
            SetWindowPos( $record->{hwnd}, $value ? -1 : -2, 0, 0, 0, 0, 0x0013 );
        }
        elsif ( $prop_name eq 'minimized' || $prop_name eq 'maximized' ) {
            if ($value) {
                ShowWindow( $record->{hwnd}, $prop_name eq 'minimized' ? 2 : 3 );
            }
            else {
                ShowWindow( $record->{hwnd}, 9 );
            }
        }
        elsif ( $prop_name =~ /^(min|max)_[wh]$/ ) {
            my $vn = $main_vnode || $record->{node};
            my ( $cw, $ch ) = $self->_get_client_size( $record->{hwnd} );
            my ( $nw, $nh ) = ( $cw, $ch );
            if ( $vn->min_w && $nw < $vn->min_w ) { $nw = $vn->min_w }
            if ( $vn->min_h && $nh < $vn->min_h ) { $nh = $vn->min_h }
            if ( $vn->max_w && $nw > $vn->max_w ) { $nw = $vn->max_w }
            if ( $vn->max_h && $nh > $vn->max_h ) { $nh = $vn->max_h }
            $self->_set_window_outer( $record->{hwnd}, $nw, $nh ) if $nw != $cw || $nh != $ch;
        }
        elsif ( $prop_name eq 'label' ) {
            SetWindowTextW( $record->{hwnd}, $value );
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'options' ) {
            my $node = $record->{node};
            return unless $node->type eq 'combo_box' || $node->type eq 'list_box';
            $suppress_events = 1;
            $self->_populate_options( $record->{hwnd}, $node, $node->type );
            if ( $node->type eq 'combo_box' ) {
                $self->_set_combo_value( $record->{hwnd}, $node, $node->value );
            }
            else {
                $self->_set_list_selection( $record->{hwnd}, $node, $node->selection );
            }
            $suppress_events = 0;
        }
        elsif ( $prop_name eq 'selection' ) {
            return unless $record->{node}->type eq 'list_box';
            $self->_set_list_selection( $record->{hwnd}, $record->{node}, $value );
        }
        elsif ( $prop_name eq 'selected' ) {
            if ( $record->{node}->type eq 'tab_panel' ) {
                SendMessageW( $record->{hwnd}, 0x130C, $value, 0 );    # TCM_SETCURSEL
                return;
            }
            elsif ( $record->{node}->type eq 'list_view' ) {
                $suppress_events = 1;
                my $sptr  = malloc( sizeof( LVITEMW() ) );
                my $sitem = cast( $sptr, LVITEMW() );

                # Clear all previous selections
                $sitem->{state}     = 0;
                $sitem->{stateMask} = 0x0002;
                SendMessageW( $record->{hwnd}, 0x102B, -1, Affix::address($sptr) );

                # Set selection(s)
                my @to_select = ref $value eq 'ARRAY' ? @$value : ( ( defined $value && $value >= 0 ) ? ($value) : () );
                for my $idx (@to_select) {
                    $sitem->{state}     = 0x0002 | 0x0001;
                    $sitem->{stateMask} = 0x0002 | 0x0001;
                    SendMessageW( $record->{hwnd}, 0x102B, $idx, Affix::address($sptr) );
                }
                free($sptr);
                $suppress_events = 0;
                return;
            }
        }
        elsif ( $prop_name eq 'value' ) {
            if ( $record->{node}->type eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0405, 1, $value );
                return;
            }
            if ( $record->{node}->type eq 'progress_bar' ) {
                my $hwnd = $record->{hwnd};
                my $max  = $record->{node}->max // 100;
                if ( $value < $max ) {

                    # Classic Win32 instant-draw trick: stepping backward by 1 forces
                    # ComCtl32 to cancel the 400ms visual easing animation
                    SendMessageW( $hwnd, 0x0402, $value + 1, 0 );    # PBM_SETPOS
                    SendMessageW( $hwnd, 0x0402, $value,     0 );    # PBM_SETPOS
                }
                else {
                    # At maximum: temporarily expand range by 1 to force instant 100% completion
                    SendMessageW( $hwnd, 0x0406, $record->{node}->min, $max + 1 );    # PBM_SETRANGE32
                    SendMessageW( $hwnd, 0x0402, $max + 1,             0 );
                    SendMessageW( $hwnd, 0x0402, $max,                 0 );
                    SendMessageW( $hwnd, 0x0406, $record->{node}->min, $max );        # Restore range
                }
                return;
            }
            if ( $record->{node}->type eq 'combo_box' ) {
                $suppress_events = 1;
                $self->_set_combo_value( $record->{hwnd}, $record->{node}, $value );
                $suppress_events = 0;
                return;
            }
            if ( $record->{node}->type eq 'spin_box' ) {
                $self->_set_spin_value( $record, $value );
                return;
            }
            if ( $record->{node}->type eq 'date_picker' ) {
                $self->_set_date_value( $record->{hwnd}, $value );
                return;
            }
            if ( $record->{node}->type eq 'radio_group' ) {
                my $selected_radio = '';
                for my $child ( @{ $record->{node}->children } ) {
                    $selected_radio = $child->id if $child->value eq $value;
                }
                for my $child ( @{ $record->{node}->children } ) {
                    my $cr = $registry->{ $child->id };
                    next unless $cr;
                    SendMessageW( $cr->{hwnd}, 0x00F1, $child->id eq $selected_radio ? 1 : 0, 0 );
                }
                return;
            }
            my $text    = $record->{node}->type eq 'multiline_text' ? $self->_native_newlines($value) : $value;
            my $current = $self->_get_text( $record->{hwnd} );
            if ( $current ne $value ) {
                $suppress_events = 1;
                SetWindowTextW( $record->{hwnd}, $text );
                $suppress_events = 0;
                my $len = length $value;
                SendMessageW( $record->{hwnd}, 0x00B1, $len, $len );
            }
        }
        elsif ( $prop_name eq 'indeterminate' ) {
            if ( $record->{node}->type eq 'progress_bar' ) {
                my $hwnd  = $record->{hwnd};
                my $style = GetWindowLongW( $hwnd, -16 );
                if ($value) {
                    SetWindowLongW( $hwnd, -16, $style | 0x0008 );
                    SendMessageW( $hwnd, 0x040A, 1, 30 );
                }
                else {
                    SendMessageW( $hwnd, 0x040A, 0, 0 );
                    SetWindowLongW( $hwnd, -16, $style & ~0x0008 );
                    SendMessageW( $hwnd, 0x0402, $record->{node}->value // 0, 0 );
                }
                return;
            }
        }
        elsif ( $prop_name eq 'enabled' ) {
            EnableWindow( $record->{hwnd},     $value ? 1 : 0 );
            EnableWindow( $record->{aux_hwnd}, $value ? 1 : 0 ) if $record->{aux_hwnd};
        }
        elsif ( $prop_name eq 'visible' ) {
            ShowWindow( $record->{hwnd},     $value ? 5 : 0 );
            ShowWindow( $record->{aux_hwnd}, $value ? 5 : 0 ) if $record->{aux_hwnd};
        }
        elsif ( $prop_name eq 'focused' ) {
            SetFocus( $record->{hwnd} ) if $value;
        }
        elsif ( $prop_name eq 'tooltip' ) {
            $self->_set_tooltip( $record->{hwnd},     $value );
            $self->_set_tooltip( $record->{aux_hwnd}, $value ) if $record->{aux_hwnd};
        }
        elsif ( $prop_name eq 'readonly' ) {
            return unless $record->{node}->type =~ /^(?:text_input|password|multiline_text)$/;
            SendMessageW( $record->{hwnd}, 0x00CF, $value ? 1 : 0, 0 );
        }
        elsif ( $prop_name eq 'maxlength' ) {
            return unless $record->{node}->type =~ /^(?:text_input|password|multiline_text)$/;
            SendMessageW( $record->{hwnd}, 0x00C5, $value, 0 );
        }
        elsif ( $prop_name eq 'step' ) {
            return unless $record->{node}->type eq 'slider' || $record->{node}->type eq 'spin_box';
            if ( $record->{node}->type eq 'spin_box' ) {
                $self->_set_spin_accel( $record, $value );
            }
            else {
                SendMessageW( $record->{hwnd}, 0x041C, 1, $value );
                SendMessageW( $record->{hwnd}, 0x041D, 1, $value );
            }
        }
        elsif ( $prop_name eq 'checked' ) {
            return unless $record->{node}->type eq 'checkbox' || $record->{node}->type eq 'toggle_switch';
            SendMessageW( $record->{hwnd}, 0x00F1, $value ? 1 : 0, 0 );
        }
        elsif ( $prop_name eq 'min' || $prop_name eq 'max' ) {
            my $node = $record->{node};
            return unless $node->type eq 'slider' || $node->type eq 'spin_box';
            my $min = $prop_name eq 'min' ? $value : $node->min;
            my $max = $prop_name eq 'max' ? $value : $node->max;
            if ( $node->type eq 'spin_box' ) {
                $self->_set_spin_range( $record, $min, $max );
            }
            else {
                SendMessageW( $record->{hwnd}, 0x0406, 1, ( $max << 16 ) | $min );
            }
        }
        elsif ( $prop_name eq 'columns' ) {
            if ( $record->{node}->type eq 'list_view' ) {
                $self->_populate_list_view( $record->{hwnd}, $record->{node} );
                return;
            }
        }
        elsif ( $prop_name eq 'rows' ) {
            if ( $record->{node}->type eq 'list_view' ) {
                if ( $record->{node}->virtual ) {

                    # Only set item count if it actually changed to avoid scrollbar disruption
                    my $old_count = SendMessageW( $record->{hwnd}, 0x1004, 0, 0 );    # LVM_GETITEMCOUNT
                    my $new_count = $record->{node}->total_row_count;
                    if ( $old_count != $new_count ) {
                        SendMessageW( $record->{hwnd}, 0x102F, $new_count, 2 );       # LVSICF_NOSCROLL (0x2) preserves scroll position
                    }
                    $self->_apply_header_sort_arrows( $record->{hwnd}, $record->{node} );
                    RedrawWindow( $record->{hwnd}, undef, undef, 0x0185 );
                    return;
                }

                # Standard mode
                $self->_populate_list_view_rows( $record->{hwnd}, $record->{node} );
                $self->_apply_header_sort_arrows( $record->{hwnd}, $record->{node} );
                RedrawWindow( $record->{hwnd}, undef, undef, 0x0185 );
                return;
            }
        }
    }

    method move_widget ( $vnode_id, $x, $y, $w, $h ) {
        my $record = $registry->{$vnode_id};
        return unless $record && $record->{hwnd};
        if ( my $pid = $record->{parent_scroll_id} ) {
            my $prec = $registry->{$pid};
            if ($prec) {
                $x -= ( $prec->{scroll_x} // 0 );
                $y -= ( $prec->{scroll_y} // 0 );
            }
        }

        # SWP_NOCOPYBITS (0x0100) prevents stale pixel tearing during re-layout moves
        SetWindowPos( $record->{hwnd}, undef, $x, $y, $w, $h, 0x0004 | 0x0100 );
        if ( $record->{node}->type eq 'scroll_view' ) {
            $self->_update_scroll_info($vnode_id);
            RedrawWindow( $record->{hwnd}, undef, undef, 0x0185 );
        }
        elsif ( $record->{node}->type eq 'split_view' ) {
            my $node = $record->{node};
            SetWindowPos( $record->{hwnd}, undef, $node->bar_bx, $node->bar_by, $node->bar_bw, $node->bar_bh, 0x0004 | 0x0100 );
            return;
        }
    }

    method show_message_box (%args) {
        my $title   = $args{title}   // 'Message';
        my $message = $args{message} // '';
        my $type    = $args{type}    // 'ok';
        my $icon    = $args{icon}    // 'info';
        my $flags   = 0x00000000;                                       # MB_OK
        if    ( $type eq 'ok_cancel' )     { $flags = 0x00000001; }
        elsif ( $type eq 'yes_no' )        { $flags = 0x00000004; }
        elsif ( $type eq 'yes_no_cancel' ) { $flags = 0x00000003; }
        if    ( $icon eq 'warning' )       { $flags |= 0x00000030; }
        elsif ( $icon eq 'error' )         { $flags |= 0x00000010; }
        elsif ( $icon eq 'question' )      { $flags |= 0x00000020; }
        else                               { $flags |= 0x00000040; }    # MB_ICONINFORMATION
        my $res = MessageBoxW( $main_hwnd, $message, $title, $flags );
        return 'ok'     if $res == 1;
        return 'cancel' if $res == 2;
        return 'yes'    if $res == 6;
        return 'no'     if $res == 7;
        return 'unknown';
    }

    method show_file_open_dialog (%args) {
        return $self->_show_file_dialog( \%args, 1 );
    }

    method show_file_save_dialog (%args) {
        return $self->_show_file_dialog( \%args, 0 );
    }

    method _show_file_dialog ( $args, $is_open ) {
        my $buf = malloc( 1024 * sizeof(WChar) );

        # Build double-null terminated wide filter string: "Label\0Pattern\0Label2\0Pattern2\0\0"
        my $raw_filter  = '';
        my $filter_list = $args->{filter} // [ 'All Files (*.*)' => '*.*' ];
        for ( my $i = 0; $i < @$filter_list; $i += 2 ) {
            $raw_filter .= Encode::encode( 'UTF-16LE', $filter_list->[$i] ) . "\0\0";
            $raw_filter .= Encode::encode( 'UTF-16LE', $filter_list->[ $i + 1 ] ) . "\0\0";
        }
        $raw_filter .= "\0\0";    # Terminal double-null for OPENFILENAMEW
        my $filter_len = length($raw_filter);
        my $filter_buf = malloc($filter_len);
        memcpy( $filter_buf, $raw_filter, $filter_len );

        # Zero-initialize the output buffer so lpstrFile is empty
        memcpy( $buf, "\0" x ( 1024 * sizeof(WChar) ), 1024 * sizeof(WChar) );
        my $ofn_ptr = malloc( sizeof( OPENFILENAMEW() ) );
        my $ofn     = cast( $ofn_ptr, OPENFILENAMEW() );
        $ofn->{lStructSize}     = sizeof( OPENFILENAMEW() );
        $ofn->{hwndOwner}       = $main_hwnd;
        $ofn->{lpstrFilter}     = $filter_buf;
        $ofn->{lpstrFile}       = $buf;
        $ofn->{nMaxFile}        = 1024;
        $ofn->{lpstrInitialDir} = $args->{initial_dir} if $args->{initial_dir};
        $ofn->{lpstrTitle}      = $args->{title} // ( $is_open ? 'Open File' : 'Save File' );

        # OFN_EXPLORER (0x00080000) | OFN_FILEMUSTEXIST (0x1000) | OFN_PATHMUSTEXIST (0x800)
        $ofn->{Flags} = $is_open ? ( 0x00080000 | 0x00001000 | 0x00000800 ) : ( 0x00080000 | 0x00000002 );
        my $ok     = $is_open ? GetOpenFileNameW($ofn_ptr) : GetSaveFileNameW($ofn_ptr);
        my $result = '';
        if ($ok) {
            my $raw = Affix::raw( $buf, 1024 * sizeof(WChar) );
            $result = Encode::decode( 'UTF-16LE', $raw );
            $result =~ s/\0.*$//s;
        }
        free($filter_buf);
        free($buf);
        free($ofn_ptr);
        return $ok ? $result : undef;
    }
    method _is_dragging_splitter () { defined $dragging_splitter }

    method _start_splitter_drag ($record) {
        $dragging_splitter = { record => $record };
    }

    method _end_splitter_drag () {
        $dragging_splitter = undef;
    }

    method _update_splitter_drag () {
        return unless $dragging_splitter;
        my $record = $dragging_splitter->{record};
        my $node   = $record->{node};
        my $pt_buf = malloc( sizeof( POINT() ) );
        GetCursorPos($pt_buf);
        ScreenToClient( $record->{parent_hwnd} // $main_hwnd, $pt_buf );
        my $pt = cast( $pt_buf, POINT() );
        my ( $mx, $my ) = ( $pt->{x}, $pt->{y} );
        free($pt_buf);
        my $s = $node->splitter_size // 6;
        my $new_ratio;

        if ( $node->orientation eq 'vertical' ) {
            my $avail = $node->bh - $s;
            return if $avail <= 0;
            my $rel_y = $my - $node->by - int( $s / 2 );
            $new_ratio = $rel_y / $avail;
            my $min_r = ( $node->min_first || 40 ) / $avail;
            my $max_r = 1.0 - ( ( $node->min_second || 40 ) / $avail );
            $new_ratio = $min_r if $new_ratio < $min_r;
            $new_ratio = $max_r if $new_ratio > $max_r;
        }
        else {
            my $avail = $node->bw - $s;
            return if $avail <= 0;
            my $rel_x = $mx - $node->bx - int( $s / 2 );
            $new_ratio = $rel_x / $avail;
            my $min_r = ( $node->min_first || 40 ) / $avail;
            my $max_r = 1.0 - ( ( $node->min_second || 40 ) / $avail );
            $new_ratio = $min_r if $new_ratio < $min_r;
            $new_ratio = $max_r if $new_ratio > $max_r;
        }
        $new_ratio = sprintf( '%.3f', $new_ratio );
        if ( $new_ratio != $node->split && $node->on_change ) {
            my $msg = $node->on_change->( 0 + $new_ratio );
            $channel->put($msg) if $msg;
        }
    }

    method _get_list_view_selected_indices ($hwnd) {
        my @selected;
        my $idx = -1;
        while (1) {
            $idx = SendMessageW( $hwnd, 0x100C, $idx, 0x0002 );    # LVM_GETNEXTITEM, LVNI_SELECTED
            last if $idx < 0;
            push @selected, $idx;
        }
        return \@selected;
    }

    method _populate_list_view ( $hwnd, $node ) {
        my $suppress_token = $suppress_events;
        $suppress_events = 1;

        # Extended Styles: Full row select, double buffering, optional gridlines, column reordering, checkboxes
        my $ex = 0x00000020;                                                 # LVS_EX_FULLROWSELECT
        $ex |= 0x00000001 if $node->gridlines;                               # LVS_EX_GRIDLINES
        $ex |= 0x00000010 if $node->column_reorder;                          # LVS_EX_HEADERDRAGDROP
        $ex |= 0x00000004 if $node->checkboxes;                              # LVS_EX_CHECKBOXES
        $ex |= 0x00010000;                                                   # LVS_EX_DOUBLEBUFFER
        SendMessageW( $hwnd, 0x1036, 0, $ex );                               # LVM_SETEXTENDEDLISTVIEWSTYLE
        my $header = SendMessageW( $hwnd, 0x101F, 0, 0 );                    # LVM_GETHEADER
        my $count  = $header ? SendMessageW( $header, 0x1200, 0, 0 ) : 0;    # HDM_GETITEMCOUNT

        # Save existing user-adjusted column widths (LVM_GETCOLUMNWIDTH = 0x101D)
        my @saved_widths;
        if ( $count > 0 ) {
            for my $i ( 0 .. $count - 1 ) {
                my $cw = SendMessageW( $hwnd, 0x101D, $i, 0 );
                push @saved_widths, $cw if $cw > 0;
            }
        }
        SendMessageW( $hwnd, 0x101C, 0, 0 ) for 1 .. $count;                 # LVM_DELETECOLUMN
        SendMessageW( $hwnd, 0x1009, 0, 0 );                                 # LVM_DELETEALLITEMS
        $self->_populate_list_view_columns( $hwnd, $node, \@saved_widths );
        $self->_populate_list_view_rows( $hwnd, $node );
        $self->_apply_header_sort_arrows( $hwnd, $node ) if $header;
        $suppress_events = $suppress_token;
    }

    method _apply_header_sort_arrows ( $hwnd, $node ) {
        my $header = SendMessageW( $hwnd, 0x101F, 0, 0 );                    # LVM_GETHEADER
        return unless $header;
        my $cols     = $node->columns        // [];
        my $sort_col = $node->sort_column    // '';
        my $sort_dir = $node->sort_direction // 'asc';
        for my $i ( 0 .. $#$cols ) {
            my $col_id = $cols->[$i]{id} // $cols->[$i]{text} // '';
            my $hptr   = malloc( sizeof( HDITEMW() ) );
            my $hitem  = cast( $hptr, HDITEMW() );
            $hitem->{mask} = 0x0004;                                       # HDI_FORMAT
            SendMessageW( $header, 0x120B, $i, Affix::address($hptr) );    # HDM_GETITEMW
            $hitem->{mask} = 0x0004;
            $hitem->{fmt} &= ~( 0x0400 | 0x0200 );                         # Clear HDF_SORTUP / HDF_SORTDOWN
            if ( $col_id eq $sort_col ) {
                $hitem->{fmt} |= ( $sort_dir eq 'desc' ? 0x0200 : 0x0400 );
            }
            SendMessageW( $header, 0x120C, $i, Affix::address($hptr) );    # HDM_SETITEMW
            free($hptr);
        }
    }

    method _populate_list_view_columns ( $hwnd, $node, $saved_widths = [] ) {
        my $cols = $node->columns // [];
        for my $i ( 0 .. $#$cols ) {
            my $col  = $cols->[$i];
            my $cptr = malloc( sizeof( LVCOLUMNW() ) );
            my $c    = cast( $cptr, LVCOLUMNW() );
            $c->{mask} = 0x0001 | 0x0002 | 0x0004 | 0x0008;                # LVCF_FMT | LVCF_WIDTH | LVCF_TEXT | LVCF_SUBITEM

            # Preserve user-dragged width if present; otherwise use VDOM width
            my $w_spec = ( $saved_widths && $i < @$saved_widths ) ? $saved_widths->[$i] : ( $col->{width} // 100 );
            my $cx     = ( $w_spec eq 'auto' )                    ? -1                  : 0 + $w_spec;
            $c->{cx}       = $cx;
            $c->{pszText}  = $col->{text} // "Col $i";
            $c->{iSubItem} = $i;
            my $align = $col->{align} // 'left';
            $c->{fmt} = ( $align eq 'right' ) ? 0x0001 : ( $align eq 'center' ) ? 0x0002 : 0x0000;
            SendMessageW( $hwnd, 0x1061, $i, Affix::address($cptr) );      # LVM_INSERTCOLUMNW
            free($cptr);

            # If width => 'auto' was specified, automatically resize to longest content item
            SendMessageW( $hwnd, 0x101E, $i, -1 ) if $w_spec eq 'auto';    # LVM_SETCOLUMNWIDTH, LVSCW_AUTOSIZE
        }
    }

    method _populate_list_view_rows ( $hwnd, $node ) {
        my $suppress_token = $suppress_events;
        $suppress_events = 1;

        # Virtual Mode: instant allocation via LVM_SETITEMCOUNT (0x102F)
        if ( $node->virtual ) {
            my $count = $node->total_row_count;
            SendMessageW( $hwnd, 0x102F, $count, 0 );                      # LVM_SETITEMCOUNT
            RedrawWindow( $hwnd, undef, undef, 0x0185 );
            $suppress_events = $suppress_token;
            return;
        }

        # Standard Non-Virtual Mode (full row population)
        SendMessageW( $hwnd, 0x1009, 0, 0 );    # LVM_DELETEALLITEMS
        my $cols = $node->columns // [];
        my $rows = $node->rows    // [];
        for my $r_idx ( 0 .. $#$rows ) {
            my $row        = $rows->[$r_idx];
            my $first_text = '';
            if ( ref $row eq 'HASH' ) {
                my $key = @$cols ? ( $cols->[0]{id} // $cols->[0]{text} // '' ) : '';
                $first_text = '' . ( $row->{$key} // '' );
            }
            elsif ( ref $row eq 'ARRAY' ) {
                $first_text = '' . ( $row->[0] // '' );
            }
            else {
                $first_text = '' . ( $row // '' );
            }

            # Allocate persistent wide-string buffer in C memory for column 0
            my $utf16_first = Encode::encode( 'UTF-16LE', $first_text . "\0" );
            my $buf1        = malloc( length($utf16_first) );
            memcpy( $buf1, $utf16_first, length($utf16_first) );
            my $iptr = malloc( sizeof( LVITEMW() ) );
            my $item = cast( $iptr, LVITEMW() );
            $item->{mask}     = 0x0001;                                 # LVIF_TEXT
            $item->{iItem}    = $r_idx;
            $item->{iSubItem} = 0;
            $item->{pszText}  = $buf1;
            SendMessageW( $hwnd, 0x104D, 0, Affix::address($iptr) );    # LVM_INSERTITEMW
            free($buf1);
            free($iptr);

            # Populate sub-items (Columns 1..N)
            for my $c_idx ( 1 .. $#$cols ) {
                my $sub_text = '';
                if ( ref $row eq 'HASH' ) {
                    my $key = $cols->[$c_idx]{id} // $cols->[$c_idx]{text} // '';
                    $sub_text = '' . ( $row->{$key} // '' );
                }
                elsif ( ref $row eq 'ARRAY' ) {
                    $sub_text = '' . ( $row->[$c_idx] // '' );
                }
                my $utf16_sub = Encode::encode( 'UTF-16LE', $sub_text . "\0" );
                my $buf2      = malloc( length($utf16_sub) );
                memcpy( $buf2, $utf16_sub, length($utf16_sub) );
                my $sptr  = malloc( sizeof( LVITEMW() ) );
                my $sitem = cast( $sptr, LVITEMW() );
                $sitem->{mask}     = 0x0001;                                     # LVIF_TEXT
                $sitem->{iItem}    = $r_idx;
                $sitem->{iSubItem} = $c_idx;
                $sitem->{pszText}  = $buf2;
                SendMessageW( $hwnd, 0x1074, $r_idx, Affix::address($sptr) );    # LVM_SETITEMTEXTW
                free($buf2);
                free($sptr);
            }
        }

        # Set row check state if native checkboxes are enabled
        if ( $node->checkboxes ) {
            my $sptr  = malloc( sizeof( LVITEMW() ) );
            my $sitem = cast( $sptr, LVITEMW() );
            $sitem->{stateMask} = 0x3000;    # LVIS_STATEIMAGEMASK
            for my $r_idx ( 0 .. $#$rows ) {
                my $row        = $rows->[$r_idx];
                my $is_checked = ref $row eq 'HASH' ? ( $row->{checked} // 0 ) : 0;
                $sitem->{state} = ( $is_checked ? 2 : 1 ) << 12;
                SendMessageW( $hwnd, 0x102B, $r_idx, Affix::address($sptr) );    # LVM_SETITEMSTATE
            }
            free($sptr);
        }

        # Select specified row(s) (supports both scalar index and arrayref of indices)
        if ( defined $node->selected ) {
            my @to_select = ref $node->selected eq 'ARRAY' ? @{ $node->selected } : ( $node->selected >= 0 ? ( $node->selected ) : () );
            if (@to_select) {
                my $sptr  = malloc( sizeof( LVITEMW() ) );
                my $sitem = cast( $sptr, LVITEMW() );
                $sitem->{state}     = 0x0002 | 0x0001;                           # LVIS_SELECTED | LVIS_FOCUSED
                $sitem->{stateMask} = 0x0002 | 0x0001;
                for my $s_idx (@to_select) {
                    if ( $s_idx >= 0 && $s_idx < @$rows ) {
                        SendMessageW( $hwnd, 0x102B, $s_idx, Affix::address($sptr) );    # LVM_SETITEMSTATE
                    }
                }
                free($sptr);
            }
        }
        $suppress_events = $suppress_token;
    }

    method _handle_list_view_custom_draw ( $record, $lparam ) {
        my $cd    = cast( $lparam, NMLVCUSTOMDRAW() );
        my $stage = $cd->{dwDrawStage};
        if ( $stage == 0x00000001 ) {    # CDDS_PREPAINT
            return 0x00000020;           # CDRF_NOTIFYITEMDRAW
        }
        elsif ( $stage == 0x00010001 ) {    # CDDS_ITEMPREPAINT
            return 0x00000020;              # CDRF_NOTIFYSUBITEMDRAW
        }
        elsif ( $stage == 0x00030001 ) {    # CDDS_SUBITEM | CDDS_ITEMPREPAINT
            my $row_idx = $cd->{dwItemSpec};
            my $col_idx = $cd->{iSubItem};
            my $node    = $record->{node};
            my $cols    = $node->columns // [];
            return 0 if $col_idx > $#$cols;
            my $col  = $cols->[$col_idx];
            my $type = $col->{type} // 'text';
            if ( $type eq 'progress_bar' || $type eq 'badge' ) {
                my $hwnd = $record->{hwnd};
                my $hdc  = $cd->{hdc};
                my $row;

                # Fetch row data transparently (works for both virtual and standard lists)
                if ( $node->on_row ) {
                    $row = $node->on_row->($row_idx);
                }
                else {
                    my $rows = $node->rows // [];
                    return 0 if $row_idx > $#$rows;
                    $row = $rows->[$row_idx];
                }
                my $cid = $col->{id} // $col->{text} // '';
                my $val = ref $row eq 'HASH' ? ( $row->{$cid} // '' ) : ( $row->[$col_idx] // '' );

                # Query exact sub-item rectangle
                my $rptr = malloc( sizeof( RECT() ) );
                my $r    = cast( $rptr, RECT() );
                $r->{top}  = $col_idx;
                $r->{left} = 0;                                                    # LVIR_BOUNDS
                SendMessageW( $hwnd, 0x1038, $row_idx, Affix::address($rptr) );    # LVM_GETSUBITEMRECT
                if ( $type eq 'progress_bar' ) {
                    $self->_draw_cell_progress_bar( $hdc, $rptr, $val );
                }
                elsif ( $type eq 'badge' ) {
                    $self->_draw_cell_badge( $hdc, $rptr, $val );
                }
                free($rptr);
                return 0x00000004;                                                 # CDRF_SKIPDEFAULT (do not draw standard text over our graphics)
            }
        }
        return 0;                                                                  # CDRF_DODEFAULT
    }

    method _draw_cell_progress_bar ( $hdc, $rptr, $val ) {
        my $r = cast( $rptr, RECT() );
        my ( $x1, $y1, $x2, $y2 ) = ( $r->{left} + 4, $r->{top} + 3, $r->{right} - 4, $r->{bottom} - 3 );
        return if $x2 <= $x1 || $y2 <= $y1;

        # Background track
        my $track_rptr = malloc( sizeof( RECT() ) );
        my $tr         = cast( $track_rptr, RECT() );
        $tr->{left}   = $x1;
        $tr->{top}    = $y1;
        $tr->{right}  = $x2;
        $tr->{bottom} = $y2;
        my $track_br = CreateSolidBrush(0x00EFECE8);    # subtle grey track
        FillRect( $hdc, $track_rptr, $track_br );
        DeleteObject($track_br);
        my ($num) = "$val" =~ /([\d.]+)/;
        $num = 0 unless defined $num;
        $num = 100 if $num > 100;

        # Fill bar
        my $fill_w = int( ( $x2 - $x1 ) * ( $num / 100 ) );
        if ( $fill_w > 0 ) {
            my $fill_rptr = malloc( sizeof( RECT() ) );
            my $fr        = cast( $fill_rptr, RECT() );
            $fr->{left}   = $x1;
            $fr->{top}    = $y1;
            $fr->{right}  = $x1 + $fill_w;
            $fr->{bottom} = $y2;

            # Modern blue fill (#0078D4 = BGR 0x00D47800)
            my $fill_br = CreateSolidBrush(0x00D47800);
            FillRect( $hdc, $fill_rptr, $fill_br );
            DeleteObject($fill_br);
            free($fill_rptr);
        }

        # Border outline
        my $frame_br = CreateSolidBrush(0x00DAD4CE);
        FrameRect( $hdc, $track_rptr, $frame_br );
        DeleteObject($frame_br);

        # Centered percentage label
        SetBkMode( $hdc, 1 );                                                    # TRANSPARENT
        SetTextColor( $hdc, 0x00000000 );
        DrawTextW( $hdc, "$val", -1, $track_rptr, 0x0001 | 0x0004 | 0x0020 );    # DT_CENTER | DT_VCENTER | DT_SINGLELINE
        free($track_rptr);
    }

    method _draw_cell_badge ( $hdc, $rptr, $val ) {
        my $r = cast( $rptr, RECT() );
        my ( $x1, $y1, $x2, $y2 ) = ( $r->{left} + 6, $r->{top} + 3, $r->{right} - 6, $r->{bottom} - 3 );
        return if $x2 <= $x1 || $y2 <= $y1;

        # Color palettes (BGR): Green for Running, Amber for Idle/Warning, Red for Suspended/Error
        my ( $bg_color, $fg_color, $border_color );
        my $v = lc "$val";
        if ( $v =~ /^(?:running|active|done|success|ok)$/ ) {
            $bg_color     = 0x00D4EDDA;    # Soft Green
            $fg_color     = 0x00155724;    # Dark Green text
            $border_color = 0x00C3E6CB;
        }
        elsif ( $v =~ /^(?:idle|pending|warning|pause)$/ ) {
            $bg_color     = 0x00FFF3CD;    # Soft Amber
            $fg_color     = 0x00856404;    # Dark Amber text
            $border_color = 0x00FFEEBA;
        }
        elsif ( $v =~ /^(?:suspended|error|failed|dead|stopped)$/ ) {
            $bg_color     = 0x00F8D7DA;    # Soft Red
            $fg_color     = 0x00721C24;    # Dark Red text
            $border_color = 0x00F5C6CB;
        }
        else {
            $bg_color     = 0x00E2E3E5;    # Soft Grey
            $fg_color     = 0x00383D41;
            $border_color = 0x00D6D8DB;
        }
        my $badge_rptr = malloc( sizeof( RECT() ) );
        my $br         = cast( $badge_rptr, RECT() );
        $br->{left}   = $x1;
        $br->{top}    = $y1;
        $br->{right}  = $x2;
        $br->{bottom} = $y2;
        my $b_brush = CreateSolidBrush($bg_color);
        FillRect( $hdc, $badge_rptr, $b_brush );
        DeleteObject($b_brush);
        my $f_brush = CreateSolidBrush($border_color);
        FrameRect( $hdc, $badge_rptr, $f_brush );
        DeleteObject($f_brush);
        SetBkMode( $hdc, 1 );
        SetTextColor( $hdc, $fg_color );
        DrawTextW( $hdc, "$val", -1, $badge_rptr, 0x0001 | 0x0004 | 0x0020 );
        free($badge_rptr);
    }

    method _start_inplace_edit ( $record, $row_idx, $col_idx ) {
        return if $active_inplace_edit;
        my $hwnd = $record->{hwnd};
        my $node = $record->{node};
        my $cols = $node->columns // [];
        return if $col_idx > $#$cols;
        my $col    = $cols->[$col_idx];
        my $col_id = $col->{id} // $col->{text};

        # Query exact cell rectangle (LVM_GETSUBITEMRECT = 0x1038)
        my $rptr = malloc( sizeof( RECT() ) );
        my $r    = cast( $rptr, RECT() );
        $r->{top}  = $col_idx;
        $r->{left} = 0;          # LVIR_BOUNDS
        SendMessageW( $hwnd, 0x1038, $row_idx, Affix::address($rptr) );

        # Extract current cell text
        my $current_text = '';
        if ( $node->on_row ) {
            my $row = $node->on_row->($row_idx);
            $current_text = ref $row eq 'HASH' ? ( $row->{$col_id} // '' ) : ( $row->[$col_idx] // '' );
        }
        elsif ( $row_idx >= 0 && $row_idx < @{ $node->rows // [] } ) {
            my $row = $node->rows->[$row_idx];
            $current_text = ref $row eq 'HASH' ? ( $row->{$col_id} // '' ) : ( $row->[$col_idx] // '' );
        }

        # Create floating in-place EDIT control directly over the cell
        # Inset slightly so it fits inside the cell gridline boundaries
        my ( $x, $y, $w, $h ) = ( $r->{left} + 1, $r->{top} + 1, ( $r->{right} - $r->{left} ) - 2, ( $r->{bottom} - $r->{top} ) - 2 );
        free($rptr);
        my $style     = 0x50800080;    # WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL
        my $edit_hwnd = CreateWindowExW( 0, 'EDIT', $current_text, $style, $x, $y, $w, $h, $hwnd, 9999, undef, undef );
        $self->_apply_font($edit_hwnd);
        SetFocus($edit_hwnd);
        SendMessageW( $edit_hwnd, 0x00B1, 0, -1 );    # EM_SETSEL (highlight text)

        # Install native subclass procedure using SetWindowSubclass
        my $self_ref = $self;
        my $subclass_cb;
        $subclass_cb = sub ( $ehwnd, $emsg, $ewp, $elp, $uIdSubclass, $dwRefData ) {
            if ( $emsg == 0x0100 ) {                  # WM_KEYDOWN
                if ( $ewp == 0x0D ) {                 # VK_RETURN (Enter key: commit)
                    $self_ref->_commit_inplace_edit(1);
                    return 0;
                }
                elsif ( $ewp == 0x1B ) {              # VK_ESCAPE (Escape key: cancel)
                    $self_ref->_commit_inplace_edit(0);
                    return 0;
                }
            }
            elsif ( $emsg == 0x0008 ) {               # WM_KILLFOCUS (clicked outside: commit)
                $self_ref->_commit_inplace_edit(1);
                return 0;
            }
            return DefSubclassProc( $ehwnd, $emsg, $ewp, $elp );
        };
        SetWindowSubclass( $edit_hwnd, $subclass_cb, 1001, 0 );
        $active_inplace_edit = { record => $record, edit_hwnd => $edit_hwnd, row_idx => $row_idx, col_id => $col_id, subclass_cb => $subclass_cb };
    }

    method _commit_inplace_edit ($commit) {
        return unless $active_inplace_edit;
        my $info = $active_inplace_edit;
        $active_inplace_edit = undef;
        my $edit_hwnd   = $info->{edit_hwnd};
        my $record      = $info->{record};
        my $node        = $record->{node};
        my $subclass_cb = $info->{subclass_cb};
        RemoveWindowSubclass( $edit_hwnd, $subclass_cb, 1001 ) if $subclass_cb;

        if ( $commit && $node->on_edit ) {
            my $new_text = $self->_get_text($edit_hwnd);
            my $msg      = $node->on_edit->( $info->{row_idx}, $info->{col_id}, $new_text );
            $channel->put($msg) if $msg;
        }
        DestroyWindow($edit_hwnd);
        SetFocus( $record->{hwnd} );
        RedrawWindow( $record->{hwnd}, undef, undef, 0x0185 );
    }
};
1;
