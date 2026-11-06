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
    field $tooltip_hwnd    : reader                      = undef;
    field $on_resize       : reader(_get_resize_handler) = undef;
    field $suppress_events : reader(_is_suppressed)      = 0;
    field $gui_font;
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
        affix 'user32', 'CreateMenu',      []                                        => Pointer [Void];
        affix 'user32', 'CreatePopupMenu', []                                        => Pointer [Void];
        affix 'user32', 'AppendMenuW',     [ Pointer [Void], UInt, Size_t, WString ] => Int;
        affix 'user32', 'SetMenu',         [ Pointer [Void], Pointer [Void] ]        => Int;
        affix 'user32', 'DrawMenuBar',     [ Pointer [Void] ]                        => Int;

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

        # DEFAULT_GUI_FONT (17) matches standard controls and font metrics
        $gui_font = GetStockObject(17);

        # Common controls (trackbar/slider, etc.)
        typedef INITCOMMONCONTROLSEX => Struct [ dwSize => ULong, dwICC => ULong ];
        affix 'comctl32', 'InitCommonControlsEx', [ Pointer [ INITCOMMONCONTROLSEX() ] ] => Int;
        my $icc   = malloc( sizeof( INITCOMMONCONTROLSEX() ) );
        my $icc_s = cast( $icc, INITCOMMONCONTROLSEX() );
        $icc_s->{dwSize} = sizeof( INITCOMMONCONTROLSEX() );
        $icc_s->{dwICC}  = 0x00000004 | 0x000000008 | 0x00000010 | 0x00000020 | 0x00000100;    # BAR | ICC_TAB | UPDOWN | PROGRESS | DATE
        InitCommonControlsEx($icc);
        free($icc);
    }

    # Apply the standard GUI font to child controls via WM_SETFONT (0x0030)
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

                    # BN_CLICKED (0) -> Button click
                    if ( $notify_code == 0 && $node->can('on_click') && $node->on_click ) {
                        $self_ref->channel->put( $node->on_click );
                    }

                    # BN_CLICKED (0) -> Checkbox toggle: read actual state back from the control
                    elsif ( $notify_code == 0 && $node->can('on_toggle') && $node->on_toggle ) {
                        my $checked    = SendMessageW( $record->{hwnd}, 0x00F0, 0, 0 );    # BM_GETCHECK
                        my $action_msg = $node->on_toggle->( $checked ? 1 : 0 );
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }

                    # BN_CLICKED (0) -> Radio select: dispatch the clicked option's value
                    elsif ( $notify_code == 0 && $node->can('on_select') && $node->on_select ) {
                        my $action_msg = $node->on_select->( $node->value );
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }

                    # CBN_SELCHANGE (1) -> ComboBox selection: map native index back to value
                    elsif ( $notify_code == 1 && $node->type eq 'combo_box' && $node->on_select ) {
                        my $idx = SendMessageW( $record->{hwnd}, 0x0147, 0, 0 );    # CB_GETCURSEL
                        if ( $idx >= 0 && $idx <= $#{ $node->options } ) {
                            my $action_msg = $node->on_select->( $node->options->[$idx]{value} );
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                    }

                    # CBN_EDITCHANGE (5) -> ComboBox edit text changed by user
                    elsif ( $notify_code == 5 && $node->type eq 'combo_box' && $node->can('on_input') && $node->on_input ) {
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text       = $self_ref->_get_text( $record->{hwnd} );
                        my $action_msg = $node->on_input->($text);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }

                    # LBN_SELCHANGE (1) -> ListBox selection
                    elsif ( $notify_code == 1 && $node->type eq 'list_box' && $node->on_select ) {
                        my $idx = SendMessageW( $record->{hwnd}, 0x0188, 0, 0 );    # LB_GETCURSEL
                        if ( $idx >= 0 && $idx <= $#{ $node->options } ) {
                            my $action_msg = $node->on_select->( $node->options->[$idx]{value} );
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                    }

                    # EN_CHANGE (0x0300) -> SpinBox text changed
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
            elsif ( $msg == 0x004E ) {    # WM_NOTIFY -> date picker
                my $hdr    = cast( $lparam, NMHDR() );
                my $record = $self_ref->_get_registry_record( $hdr->{idFrom} );
                if ( $record && $record->{node}->type eq 'date_picker' && $hdr->{code} == -759 ) {    # DTN_DATETIMECHANGE
                    my $change = cast( $lparam, NMDATETIMECHANGE() );
                    my $node   = $record->{node};
                    if ( $node->on_change ) {
                        my $value = $change->{dwFlags} == 1 ? '' :
                            sprintf( '%04d-%02d-%02d', $change->{st}{wYear}, $change->{st}{wMonth}, $change->{st}{wDay} );
                        my $action_msg = $node->on_change->($value);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }
                }
                if ( $record && $record->{node}->type eq 'tab_panel' && $hdr->{code} == -551 ) {      # TCN_SELCHANGE
                    my $idx  = SendMessageW( $record->{hwnd}, 0x130B, 0, 0 );                         # TCM_GETCURSEL
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
    method _is_mounted ()           { $main_hwnd ? 1 : 0 }
    method set_resize_handler ($cb) { $on_resize = $cb; $self }

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

    method destroy_widget ($id) {
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
        $si->{fMask}  = 0x0017;                                                    # SIF_ALL
        GetScrollInfo( $scroll_hwnd, 1, $sptr );
        my $cur_pos = $si->{nPos};
        my $new_pos = $cur_pos;
        my $page    = $si->{nPage};
        my $max_pos = $si->{nMax} - $page + 1;
        $max_pos = 0 if $max_pos < 0;
        if    ( $action == 0 )                 { $new_pos -= 26; }                 # SB_LINEUP
        elsif ( $action == 1 )                 { $new_pos += 26; }                 # SB_LINEDOWN
        elsif ( $action == 2 )                 { $new_pos -= $page; }              # SB_PAGEUP
        elsif ( $action == 3 )                 { $new_pos += $page; }              # SB_PAGEDOWN
        elsif ( $action == 4 || $action == 5 ) { $new_pos = $si->{nTrackPos}; }    # SB_THUMBPOSITION / SB_THUMBTRACK
        elsif ( $action == 6 )                 { $new_pos = $si->{nMin}; }         # SB_TOP
        elsif ( $action == 7 )                 { $new_pos = $max_pos; }            # SB_BOTTOM
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
};
1;
