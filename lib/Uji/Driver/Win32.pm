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
        affix 'user32', 'GetWindowLongW',   [ Pointer [Void], Int ]                                      => Int;
        affix 'user32', 'SetWindowLongW',   [ Pointer [Void], Int, Int ]                                 => Int;
        affix 'user32', 'SendMessageW',     [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;

        # Same entry point, but with a marshalled wide-string lParam (combo/list item text).
        affix 'user32', [ 'SendMessageW', 'SendMessageWStr' ], [ Pointer [Void], UInt, Size_t, WString ] => SSize_t;

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
        affix 'user32', 'GetWindowTextLengthW', [ Pointer [Void] ]                      => Int;
        affix 'user32', 'GetWindowTextW',       [ Pointer [Void], Pointer [Void], Int ] => Int;
        affix 'user32', 'GetClientRect',        [ Pointer [Void], Pointer [Void] ]      => Int;
        affix 'user32', 'GetWindowRect',        [ Pointer [Void], Pointer [Void] ]      => Int;
        affix 'user32', 'AdjustWindowRectEx',   [ Pointer [ RECT() ], UInt, Int, UInt ] => Int;

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
        $icc_s->{dwICC}  = 0x00000004 | 0x00000010 | 0x00000020 | 0x00000100;    # BAR | UPDOWN | PROGRESS | DATE
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
            if ( $msg == 0x0111 ) {    # WM_COMMAND
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
            }
            elsif ( $msg == 0x0002 ) {    # WM_DESTROY -> main window closed; signal application termination
                $self_ref->channel->put( { type => 'QUIT' } );
            }
            elsif ( $msg == 0x0005 ) {    # WM_SIZE -> window was resized; re-layout
                my $cw = $lparam & 0xFFFF;
                my $ch = ( $lparam >> 16 ) & 0xFFFF;
                $self_ref->channel->put( { type => 'RESIZE' } );
                my $cb = $self_ref->_get_resize_handler;
                $cb->( $cw, $ch ) if $cb;
            }
            elsif ( $msg == 0x0024 ) {    # WM_GETMINMAXINFO -> clamp window track sizes
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
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless defined $rec->{hwnd};
            return $rec if $rec->{hwnd} == $hwnd;
            return $rec if defined $rec->{aux_hwnd} && $rec->{aux_hwnd} == $hwnd;
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
            $req_cw = $vtree->w || ( $iw < 320 ? 320 : $iw );
            $req_ch = $vtree->h || ( $ih < 180 ? 180 : $ih );
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
        SetWindowPos( $main_hwnd, $vtree->topmost ? -1 : -2, 0, 0, 0, 0, 0x0003 ) if $vtree->topmost;
        ShowWindow( $main_hwnd, $vtree->maximized ? 3 : $vtree->minimized ? 2 : 5 );
        UpdateWindow($main_hwnd);
    }

    method mount_widget ( $vnode, $parent_hwnd = undef ) {
        $parent_hwnd //= $main_hwnd;
        $self->_mount_node( $vnode, $parent_hwnd );
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
        $self->_mount_node( $vtree->child, $main_hwnd ) if $vtree->child;
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

    method _mount_node ( $vnode, $parent_hwnd ) {
        if ( $vnode->type eq 'spacer' ) {
            return;
        }
        if ( $vnode->type eq 'spin_box' ) {
            $self->_mount_spin_box( $vnode, $parent_hwnd );
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
        else {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
            $registry->{ $vnode->id } = { hwnd => undef, node => $vnode } if $vnode->type eq 'radio_group';
            return;
        }
        my $hwnd = CreateWindowExW( 0, $class, $initial_text, $style, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef,
            undef );
        $registry->{ $vnode->id } = { hwnd => $hwnd, node => $vnode };

        # Apply standard modern GUI font to newly created control
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
            $self->_mount_node( $vnode->child, $parent_hwnd );
        }
    }

    # SpinBox = EDIT + UPDOWN buddy control
    method _mount_spin_box ( $vnode, $parent_hwnd ) {
        my $edit = CreateWindowExW(
            0, 'EDIT',
            '' . ( $vnode->value // 0 ),
            0x50800080 | 0x2000,
            $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef, undef
        );
        my $updown = CreateWindowExW( 0, 'msctls_updown32', undef, 0x500000B2, $vnode->bx + $vnode->bw - 16,
            $vnode->by, 16, $vnode->bh, $parent_hwnd, 0, undef, undef );
        my $record = { hwnd => $edit, aux_hwnd => $updown, node => $vnode };
        $registry->{ $vnode->id } = $record;

        # Set font on both buddy controls
        $self->_apply_font($edit);
        $self->_apply_font($updown);
        SendMessageW( $updown, 0x0469, $edit,    0 );
        SendMessageW( $edit,   0x00D3, 20 << 16, 0 );
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
        if ( $prop_name eq 'title' ) {
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
        elsif ( $prop_name eq 'value' ) {
            if ( $record->{node}->type eq 'progress_bar' ) {
                SendMessageW( $record->{hwnd}, 0x0402, $value, 0 );    # PBM_SETPOS
                return;
            }
            if ( $record->{node}->type eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0405, 1, $value );
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
        elsif ( $prop_name eq 'indeterminate' ) {
            if ( $record->{node}->type eq 'progress_bar' ) {
                my $hwnd  = $record->{hwnd};
                my $style = GetWindowLongW( $hwnd, -16 );    # -16 = GWL_STYLE
                if ($value) {

                    # Add PBS_MARQUEE (0x0008) and start the animation timer
                    SetWindowLongW( $hwnd, -16, $style | 0x0008 );
                    SendMessageW( $hwnd, 0x040A, 1, 30 );    # PBM_SETMARQUEE (1 = start, 30ms)
                }
                else {
                    # Stop animation timer, remove PBS_MARQUEE, and restore the static progress value
                    SendMessageW( $hwnd, 0x040A, 0, 0 );                              # PBM_SETMARQUEE (0 = stop)
                    SetWindowLongW( $hwnd, -16, $style & ~0x0008 );
                    SendMessageW( $hwnd, 0x0402, $record->{node}->value // 0, 0 );    # PBM_SETPOS
                }
                return;
            }
        }
    }

    method move_widget ( $vnode_id, $x, $y, $w, $h ) {
        my $record = $registry->{$vnode_id};
        return unless $record && $record->{hwnd};
        SetWindowPos( $record->{hwnd}, undef, $x, $y, $w, $h, 0x0004 );
        if ( $record->{aux_hwnd} ) {
            SetWindowPos( $record->{aux_hwnd}, undef, $x + $w - 16, $y, 16, $h, 0x0004 );
        }
    }
};
1
