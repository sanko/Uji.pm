use v5.40;
use experimental 'class';
use Uji::Driver;
class Uji::Driver::Win32 v0.0.1 : isa(Uji::Driver) {

    # user32.dll, gdi32.dll
    use Affix  qw[:memory :types :core];
    use Encode qw[decode encode];
    field $channel : reader;
    field $registry;
    field $wndproc_cb;
    field $main_hwnd;
    field $main_vnode      : reader;
    field $tooltip_hwnd    : reader                      = undef;
    field $on_resize       : reader(_get_resize_handler) = undef;
    field $suppress_events : reader(_is_suppressed)      = 0;
    field $item_pins;           # hwnd -> [ malloc'd UTF-16 item strings still referenced by the control ]
    field $brush_cache = {};    # '#RRGGBB' -> HBRUSH
    field $font_cache  = {};    # 'Name|Size' -> HFONT

    # Per-surface registries for the shared-pump multi-window skeleton. Each surface (top-level HWND
    # family) owns a records map so WM_ACTIVATE / WM_CLOSE / tooltips route by surface. Today the only
    # live surface is 'main' (a placeholder _mount_sibling_window can reserve extra surfaces before real
    # sibling top-level HWNDs are wired by the reconciler).
    field $surfaces        : reader = {};    # surface_id => { hwnd, node, records => HASHREF, planned => 0|1 }
    field $surface_by_hwnd : reader = {};    # hwnd -> surface_id
    ADJUST {
        $registry  = {};
        $item_pins = {};

        # WNDPROC: note the HWND first arg is typed Size_t (NOT Pointer [Void]). Affix hands a
        # Pointer arg to the callback as a REF object whose numification is the SV's address, so
        # surface_by_hwnd->{$hwnd} (keyed by the integer returned from CreateWindowExW) would
        # never match. As Size_t we receive the HWND as a plain integer, so WM_DESTROY /
        # WM_SIZE / WM_GETMINMAXINFO can resolve the surface and close routing works.
        typedef WNDPROC => Callback [ [ Size_t, UInt, Size_t, SSize_t ] => SSize_t ];
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
        affix 'user32', 'GetCursorPos',     [ Pointer [Void] ]                                           => Int;
        affix 'user32', 'LoadCursorW',      [ Pointer [Void], Size_t ]                                   => Pointer [Void];
        affix 'user32', 'GetSystemMetrics', [Int]                                                        => Int;
        affix 'user32', 'SendMessageW',     [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;

        # Colour / font support
        affix 'gdi32', 'SetTextColor',        [ Pointer [Void], ULong ] => ULong;
        affix 'gdi32', 'SetBkColor',          [ Pointer [Void], ULong ] => ULong;
        affix 'gdi32', 'CreateSolidBrush',    [ULong]                   => Pointer [Void];
        affix 'gdi32', 'DeleteObject',        [ Pointer [Void] ]        => Int;
        affix 'gdi32', 'CreateFontIndirectW', [ Pointer [Void] ]        => Pointer [Void];
        typedef LOGFONTW => Struct [
            lfHeight         => Int,
            lfWidth          => Int,
            lfEscapement     => Int,
            lfOrientation    => Int,
            lfWeight         => Int,
            lfItalic         => UChar,
            lfUnderline      => UChar,
            lfStrikeOut      => UChar,
            lfCharSet        => UChar,
            lfOutPrecision   => UChar,
            lfClipPrecision  => UChar,
            lfQuality        => UChar,
            lfPitchAndFamily => UChar,
            lfFaceName       => Array [ WChar, 32 ]
        ];

        # Read native control text
        typedef RECT => Struct [ left => Int, top => Int, right => Int, bottom => Int ];
        typedef POINT => Struct [ x => Int, y => Int ];
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

        # Common controls (trackbar/slider, up/down spinner, progress bar, etc.)
        typedef INITCOMMONCONTROLSEX => Struct [ dwSize => ULong, dwICC => ULong ];
        affix 'comctl32', 'InitCommonControlsEx', [ Pointer [ INITCOMMONCONTROLSEX() ] ] => Int;

        # Window enumeration / introspection (used by probes and tests)
        affix 'user32', 'FindWindowW',              [ WString, WString ]                    => Pointer [Void];
        affix 'user32', 'GetWindow',                [ Pointer [Void], UInt ]                => Pointer [Void];
        affix 'user32', 'GetClassNameW',            [ Pointer [Void], Pointer [Void], Int ] => Int;
        affix 'user32', 'GetWindowLongW',           [ Pointer [Void], Int ]                 => Int;
        affix 'user32', 'GetWindowThreadProcessId', [ Pointer [Void], Pointer [UInt] ]      => UInt;
        affix 'user32', 'GetSysColorBrush',         [Int]                                   => Pointer [Void];
        typedef UDACCEL => Struct [ nSec => UInt, nInc => UInt ];
        my $icc   = malloc( sizeof( INITCOMMONCONTROLSEX() ) );
        my $icc_s = cast( $icc, INITCOMMONCONTROLSEX() );
        $icc_s->{dwSize} = sizeof( INITCOMMONCONTROLSEX() );
        $icc_s->{dwICC}  = 0x00000025;                         # ICC_UPDOWN_CLASS (0x1) | ICC_BAR_CLASSES (0x4) | ICC_PROGRESS_CLASS (0x20)
        InitCommonControlsEx($icc);
        free($icc);
    }

    method init ($app_channel) {
        $channel = $app_channel;
        my $self_ref = $self;
        $wndproc_cb = sub ( $hwnd, $msg, $wparam, $lparam ) {

            #printf "hwnd=%s msg=0x%04X wp=%s lp=%s\n", $hwnd, $msg, $wparam, $lparam;
            if ( $msg == 0x0111 ) {    # WM_COMMAND
                my $control_id  = $wparam & 0xFFFF;
                my $notify_code = ( $wparam >> 16 ) & 0xFFFF;
                my $record      = $self_ref->_get_registry_record($control_id);
                if ($record) {
                    my $node = $record->{node};

                    # BN_CLICKED (0) -> Button click. on_click is dispatched: a static message
                    # hashref is put verbatim; a callback is invoked and its return value is put.
                    if ( $notify_code == 0 && $node->can('on_click') && $node->on_click ) {
                        my $on_click = $node->on_click;
                        my $action   = ref $on_click eq ref {} ? $on_click : $on_click->();
                        $self_ref->channel->put($action) if $action;
                    }

                    # BN_CLICKED (0) -> Checkbox toggle: read the actual state back from the control
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

                    # EN_CHANGE (0x0300) -> Text changed by user typing
                    elsif ( $notify_code == 0x0300 && $node->can('on_input') && $node->on_input ) {

                        # Ignore EN_CHANGE if triggered programmatically by SetWindowTextW!
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text       = $self_ref->_get_text( $record->{hwnd} );
                        my $action_msg = $node->on_input->($text);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }

                    # CBN_EDITCHANGE (5) -> user typed in an editable combo box
                    elsif ( $notify_code == 0x0005 && $node->type eq 'combo_box' && $node->on_input ) {

                        # Ignore if triggered programmatically (SetWindowTextW / CB_SETCURSEL)
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text       = $self_ref->_get_text( $record->{hwnd} );
                        my $action_msg = $node->on_input->($text);
                        $self_ref->channel->put($action_msg) if $action_msg;
                    }

                    # CBN_SELCHANGE (1) / LBN_SELCHANGE (1) -> user picked a list item
                    elsif ( $notify_code == 0x0001 && ( $node->type eq 'combo_box' || $node->type eq 'list_box' ) && $node->on_select ) {

                        # Multi-select list: report the set of selected option values as an arrayref.
                        if ( $node->type eq 'list_box' && $node->multiple ) {
                            my $cnt = SendMessageW( $record->{hwnd}, 0x0190, 0, 0 );    # LB_GETSELCOUNT
                            my @values;
                            if ( $cnt > 0 ) {
                                my $buf = malloc( $cnt * 4 );
                                SendMessageW( $record->{hwnd}, 0x0191, $cnt, Affix::address($buf) );    # LB_GETSELITEMS
                                my @idx = unpack( "V$cnt", Affix::raw( $buf, $cnt * 4 ) );
                                free($buf);
                                @values = map { $node->options->[$_]{value} // $node->options->[$_]{label} // '' } @idx;
                            }
                            my $action_msg = $node->on_select->( \@values );
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                        else {
                            my $is_combo = $node->type eq 'combo_box';
                            my $idx      = SendMessageW( $record->{hwnd}, $is_combo ? 0x0147 : 0x0188, 0, 0 );    # CB_GETCURSEL / LB_GETCURSEL
                            my $value;
                            if ( $idx >= 0 ) {
                                $value = $node->options->[$idx]{value} // $node->options->[$idx]{label} // '';
                            }
                            elsif ( $is_combo && $node->editable ) {
                                $value = $self_ref->_get_text( $record->{hwnd} );                                 # typed text not in the list
                            }
                            else {
                                $value = '';
                            }
                            my $action_msg = $node->on_select->($value);
                            $self_ref->channel->put($action_msg) if $action_msg;
                        }
                    }
                }
            }
            elsif ( $msg == 0x0002 ) {    # WM_DESTROY
                my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                if ($surface_id) {
                    delete $self_ref->surfaces->{$surface_id};
                    delete $self_ref->surface_by_hwnd->{$hwnd};
                }

                # If there are no more surfaces, quit.
                if ( scalar( keys %{ $self_ref->surfaces } ) == 0 ) {
                    $self_ref->channel->put( { type => 'QUIT' } );
                }
            }
            elsif ( $msg == 0x0005 ) {    # WM_SIZE -> window was resized; re-layout
                my $cw = $lparam & 0xFFFF;
                my $ch = ( $lparam >> 16 ) & 0xFFFF;
                $self_ref->channel->put( { type => 'RESIZE' } );
                my $cb = $self_ref->_get_resize_handler;
                if ($cb) {
                    my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                    $cb->( $surface_id, $cw, $ch );
                }
            }
            elsif ( $msg == 0x0024 ) {    # WM_GETMINMAXINFO -> clamp window track sizes to min/max
                my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                my $vn         = $surface_id ? $self_ref->surfaces->{$surface_id}{node} : undef;
                if ($vn) {
                    my $mmi = cast( $lparam, MINMAXINFO() );
                    my ( $min_w, $min_h ) = ( $vn->min_w, $vn->min_h );
                    my ( $max_w, $max_h ) = ( $vn->max_w, $vn->max_h );
                    if ( $min_w || $min_h || $max_w || $max_h ) {
                        if ( $min_w || $min_h ) {
                            my ( $ow, $oh ) = $self_ref->_frame_size_for_client( $min_w || 1, $min_h || 1 );
                            $mmi->{ptMinTrackSize}{x} = $ow if $min_w;    # only constrain the axis given
                            $mmi->{ptMinTrackSize}{y} = $oh if $min_h;
                        }
                        if ( $max_w || $max_h ) {
                            my ( $ow, $oh ) = $self_ref->_frame_size_for_client( $max_w || 1, $max_h || 1 );
                            $mmi->{ptMaxTrackSize}{x} = $ow if $max_w;
                            $mmi->{ptMaxTrackSize}{y} = $oh if $max_h;
                        }
                        return 0;    # handled
                    }
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
            }
            elsif ( $msg == 0x020e ) {    # WM_MOVING -> nothing yet
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
            elsif ( $msg == 0x0115 ) {    # WM_VSCROLL -> vertical slider thumb (lParam = trackbar HWND) OR

                # spin box up/down arrow (lParam = buddy HWND)
                my $vscroll_hwnd = $lparam;

                # A vertical TBS_VERT trackbar posts WM_VSCROLL with lParam = its own hwnd.
                my $record = $self_ref->_get_registry_by_hwnd($vscroll_hwnd);
                if ( $record && $record->{node} && $record->{node}->type eq 'slider' ) {
                    my $node = $record->{node};
                    if ( $node->can('on_change') && $node->on_change ) {
                        my $pos = SendMessageW( $vscroll_hwnd, 0x0400, 0, 0 );    # TBM_GETPOS
                        my $msg = $node->on_change->($pos);
                        $self_ref->channel->put($msg) if $msg;
                    }
                    return 0;
                }

                # Otherwise a spin box arrow: lParam = the msctls_updown32 buddy.
                $record = $self_ref->_get_registry_by_aux($vscroll_hwnd);
                if ($record) {
                    my $node = $record->{node};
                    my $pos  = SendMessageW( $vscroll_hwnd, 0x0472, 0, 0 );    # UDM_GETPOS32
                    $self_ref->_spin_sync_text( $record->{hwnd}, $pos );
                    if ( $node->can('on_change') && $node->on_change ) {
                        my $msg = $node->on_change->($pos);
                        $self_ref->channel->put($msg) if $msg;
                    }
                }
            }

            # WM_CTLCOLORSTATIC (0x0138) / WM_CTLCOLOREDIT (0x0133) / WM_CTLCOLORBTN (0x0135):
            # Return a brush + set text/background colours for the child control. We must NOT
            # fall through to DefWindowProc here: DefWindowProc restores the DC's text/background
            # colours to system defaults, silently discarding our SetTextColor/SetBkColor.
            elsif ( $msg == 0x0138 || $msg == 0x0133 || $msg == 0x0135 ) {
                my $child_hwnd = $lparam;
                my $record     = $self_ref->_get_registry_by_hwnd($child_hwnd);
                if ( $record && $record->{node} ) {
                    my $node = $record->{node};
                    my $hdc  = $wparam;
                    if ( $node->color ) {
                        SetTextColor( $hdc, $self_ref->_parse_color( $node->color ) );
                    }
                    if ( $node->background ) {
                        SetBkColor( $hdc, $self_ref->_parse_color( $node->background ) );
                        return $self_ref->_get_brush( $node->background );
                    }
                }

                # No explicit background: return the same system brush DefWindowProc would
                # (COLOR_WINDOW for edits, COLOR_BTNFACE for statics/buttons) without touching
                # the DC, so the SetTextColor above is preserved.
                return GetSysColorBrush( $msg == 0x0133 ? 5 : 15 );    # COLOR_WINDOW / COLOR_BTNFACE
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
        my $buf = malloc( ( $len + 1 ) * sizeof(WChar) );

        # GetWindowTextW returns the EXACT number of characters copied
        my $copied = GetWindowTextW( $hwnd, $buf, $len + 1 );

        # Read the raw UTF-16 bytes directly from C memory
        my $raw_bytes = Affix::raw( $buf, $copied * sizeof(WChar) );
        free($buf);

        # Decode directly to Perl UTF-8 without touching C pointer types
        return $self->_to_lf( Encode::decode( 'UTF-16LE', $raw_bytes ) );
    }

    # Native edit controls / the clipboard use CRLF line endings; the model's canonical form is
    # bare LF. Convert LF -> CRLF before writing so a multi-line value ("one\n two\n") shows real
    # line breaks (a bare LF alone renders as one line), and CRLF -> LF when reading back so the
    # model round-trip and the set_prop comparison stay LF-only.
    method _to_crlf ($string) {
        $string //= '';
        $string =~ s/\r?\n/\r\n/g;
        return $string;
    }

    method _to_lf ($string) {
        $string =~ s/\r\n/\n/g;
        return $string;
    }

    # Native progress bars render fills for the given position with no clipping, so a model value
    # outside the control's range would draw a bar "over 100%". Clamp to the declared range so a
    # progress bar can never visually exceed its max.
    method _clamp_to_range ( $vnode, $value ) {
        my $min = defined $vnode->min ? $vnode->min : 0;
        my $max = defined $vnode->max ? $vnode->max : 100;
        $value = $min if $value < $min;
        $value = $max if $value > $max;
        return $value;
    }

    # Convert '#RRGGBB' to a Win32 COLORREF (0x00BBGGRR  note reversed byte order).
    sub _parse_color ( $self, $hex ) {
        $hex =~ s/^#//;
        my $rgb = hex $hex;
        return ( ( $rgb & 0xFF ) << 16 ) | ( $rgb & 0x00FF00 ) | ( ( $rgb >> 16 ) & 0xFF );
    }

    # Lazily create and cache a solid brush for a '#RRGGBB' colour string.
    method _get_brush ($hex) {
        return undef unless defined $hex;
        return $brush_cache->{$hex} if $brush_cache->{$hex};
        my $brush = CreateSolidBrush( $self->_parse_color($hex) );
        $brush_cache->{$hex} = $brush if $brush;
        return $brush;
    }

    # Lazily create and cache an HFONT for a given face name and point size. Uses the same
    # LOGFONTW struct as CreateFontIndirectW. Height is calculated as -MulDiv(pointsize, dpi, 72).
    # We use a default DPI of 96; a proper DPI-aware version would call GetDeviceCaps.
    method _get_font ( $name, $size ) {
        $name //= 'Segoe UI';
        $size //= 9;
        my $key = "$name|$size";
        return $font_cache->{$key} if $font_cache->{$key};
        my $lf_ptr = malloc( sizeof( LOGFONTW() ) );
        my $lf     = cast( $lf_ptr, LOGFONTW() );
        my $height = -int( $size * 96 / 72 );                                       # negative = character height
        $lf->{lfHeight}         = $height;
        $lf->{lfWeight}         = 400;                                              # FW_NORMAL
        $lf->{lfCharSet}        = 1;                                                # DEFAULT_CHARSET
        $lf->{lfOutPrecision}   = 4;                                                # OUT_TT_PRECIS
        $lf->{lfQuality}        = 5;                                                # CLEARTYPE_QUALITY
        $lf->{lfPitchAndFamily} = 0x12;                                             # FF_SWISS | VARIABLE_PITCH
        my $wide_name = Encode::encode( 'UTF-16LE', $name ) . "\x00\x00";           # face name + NUL terminator
        my $face      = ptr_add( $lf_ptr, offsetof( LOGFONTW(), 'lfFaceName' ) );
        memcpy( $face, $wide_name, CORE::length($wide_name) );
        my $hfont = CreateFontIndirectW($lf_ptr);
        free($lf_ptr);
        $font_cache->{$key} = $hfont if $hfont;
        return $hfont;
    }

    # Destroy the native control (and any auxiliary controls like a spin buddy) and remount the
    # node from scratch. Used when a mount-time-only prop (multiline, orientation, align) changes.
    method recreate_node ( $old_id, $new_node ) {
        my $old    = $registry->{$old_id} or return;
        my $parent = $old->{parent_hwnd} // $main_hwnd;

        # Destroy the auxiliary control first (e.g. spin buddy).
        DestroyWindow( $old->{aux} ) if $old->{aux};

        # Destroy the primary HWND.
        DestroyWindow( $old->{hwnd} ) if $old->{hwnd};

        # Transfer the ID to the fresh node and remount it.
        $new_node->set_id($old_id);
        $self->_mount_node( $new_node, $parent );

        # Apply the computed layout bounds immediately.
        if ( $registry->{$old_id} && $registry->{$old_id}{hwnd} ) {
            SetWindowPos( $registry->{$old_id}{hwnd}, undef, $new_node->bx, $new_node->by, $new_node->bw, $new_node->bh, 0x0004 );
        }
    }

    # Current caret/selection (as character offsets) of an editable combo's edit control.
    # CB_GETEDITSEL returns them packed as (start | end << 16).
    # Find a top-level window of UjiWindowClass by its title (used by probes for introspection).
    method _find_window ($title) {
        return FindWindowW( 'UjiWindowClass', '' . $title );
    }

    # List of child HWNDs of a window (via GW_CHILD + GW_HWNDNEXT).
    method _child_windows ($parent) {
        my $first = GetWindow( $parent, 5 );
        return () unless $first;
        my @kids;
        my $h = $first;
        while ($h) {
            push @kids, $h;
            $h = GetWindow( $h, 2 );
        }
        return @kids;
    }

    # Class name of a window (wide buffer).
    method _get_class ($hwnd) {
        my $buf = malloc( 256 * sizeof(WChar) );
        my $n   = GetClassNameW( $hwnd, $buf, 256 );
        my $raw = Affix::raw( $buf, $n * sizeof(WChar) );
        free($buf);
        return Encode::decode( 'UTF-16LE', $raw );
    }

    # GWL_STYLE of a window.
    method _get_style ($hwnd) {
        return GetWindowLongW( $hwnd, -16 );
    }

    # Process ID that owns a window.
    method _window_pid ($hwnd) {
        my $pid_ptr = malloc( sizeof(UInt) );
        GetWindowThreadProcessId( $hwnd, $pid_ptr );
        my $pid = $self->_peek_u32($pid_ptr);
        free($pid_ptr);
        return $pid;
    }

    method _peek_u32 ($ptr) {
        my $raw = Affix::raw( $ptr, 4 );
        return CORE::unpack( 'V', $raw );
    }

    method _edit_selection ($hwnd) {
        my $packed = SendMessageW( $hwnd, 0x0140, 0, 0 );    # CB_GETEDITSEL
        return ( ( $packed & 0xFFFF ), ( $packed >> 16 ) & 0xFFFF );
    }
    method _get_registry_record ($id) { $registry->{$id} }

    method _get_registry_by_hwnd ($hwnd) {
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless defined $rec->{hwnd};    # containers (radio_group) have no HWND
            return $rec if $rec->{hwnd} == $hwnd;
        }
        return undef;
    }

    # Registry record whose companion "aux" control (spin box's up/down buddy) matches $hwnd.
    method _get_registry_by_aux ($hwnd) {
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless defined $rec->{aux};
            return $rec if $rec->{aux} == $hwnd;
        }
        return undef;
    }
    method _is_mounted ()           { $main_hwnd ? 1 : 0 }
    method set_resize_handler ($cb) { $on_resize = $cb; $self }

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };

        # Keep the live window node (read by WM_GETMINMAXINFO) current across re-renders.
        if ( $node->type eq 'window' ) {
            $main_vnode = $node;
        }
    }

    method mount ($vtree) {
        my $surface_id = $vtree->id;
        $main_vnode //= $vtree;    # keep the first as fallback

        # WS_OVERLAPPEDWINDOW (0x10CF0000); drop WS_THICKFRAME (0x00040000) when not resizable
        my $style = $vtree->resizable ? 0x10CF0000 : 0x10CB0000;
        my $hwnd  = CreateWindowExW( 0, 'UjiWindowClass', $vtree->title, $style, 100, 100, $vtree->w, $vtree->h, undef, 0, undef, undef );
        $registry->{ $vtree->id } = { hwnd => $hwnd, node => $vtree, surface => $surface_id };
        $surfaces->{$surface_id}  = { hwnd => $hwnd, node => $vtree, records => {} };
        $surface_by_hwnd->{$hwnd} = $surface_id;
        $main_hwnd //= $hwnd;      # First window acts as main (e.g. for tooltips)

        # Lay out against the real client area: the outer size includes the title bar and borders,
        # so we re-measure and fix up the window node before children are computed.
        my ( $cw, $ch ) = $self->_get_client_size($hwnd);
        $vtree->set_bounds( 0, 0, $cw, $ch );

        # Centering must happen after the window has its final requested size. We re-apply the
        # driver's own requested size (w/h) so a centered window does not drift from the spec.
        if ( $vtree->centered ) {
            $self->_set_window_outer( $hwnd, $vtree->w, $vtree->h, 'center' );
            my ( $nw, $nh ) = $self->_get_client_size($hwnd);
            $vtree->set_bounds( 0, 0, $nw, $nh );
        }
        SetWindowPos( $hwnd, $vtree->topmost ? -1 : -2, 0, 0, 0, 0, 0x0003 ) if $vtree->topmost;
        ShowWindow( $hwnd, $vtree->maximized ? 3 : $vtree->minimized ? 2 : 5 );
        UpdateWindow($hwnd);
    }

    method unmount ($vtree) {
        my $surface_id = $vtree->id;
        my $surface    = $surfaces->{$surface_id};
        if ( $surface && $surface->{hwnd} ) {
            DestroyWindow( $surface->{hwnd} );

            # Clean up maps
            delete $surface_by_hwnd->{ $surface->{hwnd} };
            delete $surfaces->{$surface_id};
            delete $registry->{$surface_id};
        }
    }

    # Resize/reposition the main window from a NEW client size. Computes the outer size from the
    # client size with AdjustWindowRectEx so the client area ends up exactly x w/h px.
    # Convert a client-area size into the outer window-rect size (frame + borders), so that
    # min/max track sizes in WM_GETMINMAXINFO can be expressed in window coordinates.
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

    # Lazily create the shared tooltip control (created once, owned by the main window).
    method _ensure_tooltip () {
        return $tooltip_hwnd if $tooltip_hwnd;
        $tooltip_hwnd = CreateWindowExW(
            0, 'tooltips_class32',    # TOOLTIPS_CLASS32
            undef,

            # WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX
            0x80000003, 0, 0, 0, 0, $main_hwnd, 0, undef, undef
        );
        return $tooltip_hwnd;
    }

    # Attach/replace/remove a tooltip on a control. uFlags = TTF_IDISHWND | TTF_SUBCLASS.
    # Deletes any existing tool first so repeated calls (live updates) are idempotent.
    method _set_tooltip ( $hwnd, $text ) {
        return unless $hwnd;
        my $tip = $tooltip_hwnd || $self->_ensure_tooltip();
        return unless $tip;
        my $ti_ptr = malloc( sizeof( TOOLINFO() ) );
        my $ti     = cast( $ti_ptr, TOOLINFO() );
        $ti->{cbSize} = sizeof( TOOLINFO() );
        $ti->{uFlags} = 0x0001 | 0x0010;                             # TTF_IDISHWND | TTF_SUBCLASS
        $ti->{hwnd}   = $main_hwnd;
        $ti->{uId}    = $hwnd;
        SendMessageW( $tip, 0x0433, 0, Affix::address($ti_ptr) );    # TTM_DELTOOLW (ignore result)

        if ( defined $text ) {
            $ti->{lpszText} = $text;
            SendMessageW( $tip, 0x0432, 0, Affix::address($ti_ptr) );    # TTM_ADDTOOLW
        }
        free($ti_ptr);
    }

    method sync_window_bounds ($vtree) {
        my $surface = $surfaces->{ $vtree->id };
        my $hwnd    = $surface ? $surface->{hwnd} : undef;
        return unless $hwnd;
        my ( $cw, $ch ) = $self->_get_client_size($hwnd);
        $vtree->set_bounds( 0, 0, $cw, $ch );
    }

    method mount_children ($vtree) {
        my $surface = $surfaces->{ $vtree->id };
        my $hwnd    = $surface ? $surface->{hwnd} : undef;
        $self->_mount_node( $vtree->child, $hwnd ) if $vtree->child && $hwnd;
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

        # DEFAULT_GUI_FONT (17) matches what standard controls render with.
        my $font = GetStockObject(17);
        SelectObject( $dc, $font );
        my $buf = malloc( sizeof( SIZE() ) );
        my $sz  = cast( $buf, SIZE() );
        GetTextExtentPoint32W( $dc, $text, length $text, $buf );
        my ( $w, $h ) = ( $sz->{cx}, $sz->{cy} );
        free($buf);
        ReleaseDC( $font_hwnd, $dc );
        return ( $w, $h );
    }

    # Multi-window skeleton reservation hook (gated: nothing calls this today, no real sibling HWND
    # is ever created here). Registers a *planned* sibling surface so the reconciler has a stable
    # surface_id to wire real sibling top-level HWNDs into later. The records map stays undone and
    # 'planned' is set so the shared-pump skeleton can see reserved-but-not-live surfaces. Returns
    # the planned surface_id (or undef when $vtree has no id worth planning for).
    method _mount_sibling_window ($vtree) {
        my $surface_id = 'main.sibling.' . $vtree->id;
        $surfaces->{$surface_id} = { hwnd => undef, node => undef, records => undef, planned => 1 };
        return $surface_id;
    }

    method poll_events () {
        my $msg_ptr = malloc(48);
        while ( PeekMessageW( $msg_ptr, undef, 0, 0, 1 ) ) {
            TranslateMessage($msg_ptr);
            DispatchMessageW($msg_ptr);
        }
        free($msg_ptr);
        $self->_repaint_active_spin_arrows;
    }

    method _mount_node ( $vnode, $parent_hwnd ) {
        my ( $class, $style, $initial_text );
        if ( $vnode->type eq 'button' ) {
            $class        = 'BUTTON';
            $style        = 0x50000000;            # WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text' ) {
            $class = 'STATIC';
            $style = 0x50000000;                                                                          # WS_CHILD | WS_VISIBLE
            $style |= $vnode->align eq 'center' ? 0x0001 : $vnode->align eq 'right' ? 0x0002 : 0x0000;    # SS_CENTER / SS_RIGHT / SS_LEFT
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text_input' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL for single-line (0x50800080);
            # multiline adds WS_VSCROLL | WS_TABSTOP | ES_MULTILINE (0x0004) | ES_AUTOVSCROLL
            # (0x0040) and drops ES_AUTOHSCROLL (0x50A10044).
            $style        = 0x50800080;
            $style        = 0x50A10044 if $vnode->multiline;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'multiline_text' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | WS_TABSTOP | ES_MULTILINE |
            # ES_AUTOVSCROLL. WS_TABSTOP so Tab moves focus, not inserts '\t'.
            $style        = 0x50A10044;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'password' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_BORDER | ES_PASSWORD | ES_AUTOHSCROLL
            $style        = 0x508000A0;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'slider' ) {
            $class = 'msctls_trackbar32';

            # WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS (0x1) | TBS_HORZ (0x0) or TBS_VERT (0x80)
            $style = 0x50000001 | ( $vnode->orientation eq 'vertical' ? 0x0080 : 0x0000 );
        }
        elsif ( $vnode->type eq 'spin_box' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_BORDER | WS_TABSTOP | ES_READONLY (0x0800) | ES_AUTOHSCROLL.
            # Read-only: the driver owns the text (_spin_sync_text on mount / set_prop / WM_VSCROLL).
            $style        = 0x50800880;
            $initial_text = '' . ( $vnode->value // 0 );
        }
        elsif ( $vnode->type eq 'progress_bar' ) {
            $class = 'msctls_progress32';

            # WS_CHILD | WS_VISIBLE | PBS_SMOOTH (0x1)
            $style = 0x50000001;
        }
        elsif ( $vnode->type eq 'toggle_switch' || $vnode->type eq 'toggle_button' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX (0x3  toggles itself on click) | BS_PUSHLIKE (0x1000  pushed-in look)
            $style        = 0x50001003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'link_button' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | BS_FLAT (0x8000  edge-less "link" look,
            # still a real click target that posts BN_CLICKED)
            $style        = 0x50008000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'checkbox' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX (0x3  the auto variety:
            # the button toggles itself on click; BS_CHECKBOX (0x2) never does).
            $style        = 0x50000003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'radio' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON (0x9  auto: clicking one
            # checks it and clears the group; BS_RADIOBUTTON (0x4) never does).
            # (+ WS_GROUP on the first of a group)
            $style        = $vnode->first ? 0x50020009 : 0x50000009;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'combo_box' ) {
            $class = 'COMBOBOX';

            # WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_TABSTOP | CBS_HASSTRINGS (0x200  the
            # control copies the strings we add, so items render/text-read back correctly)
            # plus CBS_DROPDOWNLIST (0x3) or CBS_DROPDOWN (0x2) for the editable variety.
            # The window height (laid out) becomes field height + dropped list extent.
            $style = 0x50210200 | ( $vnode->editable ? 0x0002 : 0x0003 );
        }
        elsif ( $vnode->type eq 'list_box' ) {
            $class = 'LISTBOX';

            # WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | WS_TABSTOP
            # | LBS_NOTIFY (0x1  post WM_COMMAND on change)
            # | LBS_NOINTEGRALHEIGHT (0x100  exact height)
            # | LBS_HASSTRINGS (0x40  store/copy + render the added strings properly)
            # | LBS_MULTIPLESEL (0x8  toggle multi-selection when requested)
            $style = 0x50A10141 | ( $vnode->multiple ? 0x0008 : 0 );
        }
        else {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };

            # Containers have no HWND but radio_group needs a registry entry so set_prop('value')
            # can route the selection to its radio children.
            $registry->{ $vnode->id } = { hwnd => undef, node => $vnode, surface => 'main' } if $vnode->type eq 'radio_group';
            return;
        }
        my $hwnd = CreateWindowExW( 0, $class, $initial_text, $style, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef,
            undef );
        $registry->{ $vnode->id } = { hwnd => $hwnd, node => $vnode, parent_hwnd => $parent_hwnd, surface => 'main' };
        $surface_by_hwnd->{$hwnd} = 'main';    # reverse map: HWND -> surface_id (each control HWND belongs to the main surface today)

        # Apply initial state for props that aren't baked into styles.
        EnableWindow( $hwnd, $vnode->enabled ? 1 : 0 );
        ShowWindow( $hwnd, $vnode->visible   ? 5 : 0 );
        $self->_set_tooltip( $hwnd, $vnode->tooltip ) if defined $vnode->tooltip;

        # Colours and font (all widgets): the parent wndproc answers WM_CTLCOLOR* from the node's
        # color/background; WM_SETFONT switches the glyph source.
        $self->_set_font( $hwnd, $vnode->font, $vnode->font_size ) if $vnode->font || $vnode->font_size;
        if ( $vnode->type eq 'text_input' || $vnode->type eq 'password' || $vnode->type eq 'multiline_text' ) {
            $self->_set_placeholder( $hwnd, $vnode->placeholder ) if defined $vnode->placeholder;
            SendMessageW( $hwnd, 0x00CF, $vnode->readonly ? 1 : 0, 0 );                  # EM_SETREADONLY
            SendMessageW( $hwnd, 0x00C5, $vnode->maxlength, 0 ) if $vnode->maxlength;    # EM_LIMITTEXT
            SetFocus($hwnd) if $vnode->focused;
        }
        if ( $vnode->type eq 'slider' ) {

            # TBM_SETRANGE (0x0401): (max << 16) | min, wParam = redraw
            SendMessageW( $hwnd, 0x0401, 1, ( $vnode->max << 16 ) | $vnode->min );
            SendMessageW( $hwnd, 0x0405, 1, $vnode->value );                             # TBM_SETPOS
            SendMessageW( $hwnd, 0x041C, 1, $vnode->step );                              # TBM_SETLINESIZE
            SendMessageW( $hwnd, 0x041D, 1, $vnode->step );                              # TBM_SETPAGESIZE
        }
        if ( $vnode->type eq 'checkbox' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->checked ? 1 : 0, 0 );                   # BM_SETCHECK
        }
        if ( $vnode->type eq 'toggle_switch' || $vnode->type eq 'toggle_button' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->checked ? 1 : 0, 0 );                   # BM_SETCHECK
        }
        if ( $vnode->type eq 'spin_box' ) {
            $self->_mount_spin_buddy( $parent_hwnd, $vnode );
        }
        if ( $vnode->type eq 'progress_bar' ) {

            # PBM_SETRANGE32 (0x0406) takes wParam = min and lParam = max as SEPARATE values
            # (NOT packed like the trackbar). Packing them made the range 0..6,553,600 and the
            # bar never filled.
            SendMessageW( $hwnd, 0x0406, $vnode->min,                                     $vnode->max );    # PBM_SETRANGE32
            SendMessageW( $hwnd, 0x0402, $self->_clamp_to_range( $vnode, $vnode->value ), 0 );              # PBM_SETPOS
        }
        if ( $vnode->type eq 'radio' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->selected ? 1 : 0, 0 );                                     # BM_SETCHECK
        }
        if ( $vnode->type eq 'password' && defined $vnode->password_char ) {
            SendMessageW( $hwnd, 0x00CC, CORE::ord( $vnode->password_char ), 0 );                           # EM_SETPASSWORDCHAR
        }
        if ( $vnode->type eq 'combo_box' || $vnode->type eq 'list_box' ) {
            $self->_populate_strings( $hwnd, $vnode );
        }
    }

    # WM_SETFONT(0x0030): switch a control to a cached HFONT built from face name + point size.
    # Non-destructive: controls keep their own HFONT until explicitly replaced.
    method _set_font ( $hwnd, $name, $size ) {
        return unless $hwnd;
        my $hfont = $self->_get_font( $name, $size );
        SendMessageW( $hwnd, 0x0030, $hfont, 1 ) if $hfont;    # WM_SETFONT (redraw = 1)
    }

    # EM_SETCUEBANNER (0x1501): grey placeholder text shown while the edit is empty. The cue is
    # automatic  it appears whenever the control holds no text and hides once the user types.
    method _set_placeholder ( $hwnd, $text ) {
        return unless $hwnd;
        my $wide = Encode::encode( 'UTF-16LE', $text );
        my $buf  = malloc( CORE::length($wide) + 2 );
        memcpy( $buf, $wide, CORE::length($wide) );
        SendMessageW( $hwnd, 0x1501, 1, Affix::address($buf) );    # EM_SETCUEBANNER (show when empty)
        free($buf);
    }

    # Create the up/down buddy control for a spin box: an UPDOWN that overlays the right edge of
    # the box's EDIT (the node's primary HWND) and owns the numeric range/position. The edit text
    # is not auto-synced (UDS_SETBUDDYINT's lazy WM_SETTEXT into a read-only edit is a crash risk
    # and re-entrancy trap), so the driver writes the text whenever it moves the position:
    # mount, set_prop('value'), and the WM_VSCROLL handler after an arrow tap. The buddy HWND is
    # stashed in the registry record as `aux`.
    method _mount_spin_buddy ( $parent_hwnd, $vnode ) {
        my $cxv     = GetSystemMetrics(2);    # SM_CXVSCROLL
        my $edit_bw = $vnode->bw - $cxv;

        # Classic Win32 spin layout: the EDIT must NOT extend under the up/down buttons. When the
        # buddy overlapped the edit, the edit sat over the buddy in the parent's z-order and its
        # caret stayed "in front"  arrow clicks were swallowed by the edit and never reached the
        # buddy (Windows hit-testing). Shrink the edit to width bw-cxv; the buddy owns the right strip.
        SetWindowPos( $registry->{ $vnode->id }{hwnd}, undef, $vnode->bx, $vnode->by, $edit_bw, $vnode->bh, 0x0004 );
        my $up = CreateWindowExW(
            0, 'msctls_updown32', undef,

            # WS_CHILD | WS_VISIBLE | UDS_ARROWKEYS (0x20)
            0x50000020, $vnode->bx + $edit_bw, $vnode->by, $cxv, $vnode->bh, $parent_hwnd, 0, undef, undef
        );
        EnableWindow( $up, $vnode->enabled ? 1 : 0 );
        ShowWindow( $up, $vnode->visible   ? 5 : 0 );
        return unless $up;
        $registry->{ $vnode->id }{aux} = $up;
        SendMessageW( $up, 0x046F, 0, ( $vnode->max << 16 ) | $vnode->min );    # UDM_SETRANGE32
        SendMessageW( $up, 0x0471, 0, $vnode->value );                          # UDM_SETPOS32
        $self->_spin_set_step( $up, $vnode->step ) if $vnode->step != 1;

        # The up-down only paints its arrow glyphs when it reprocesses WM_PAINT, which under a
        # poll-based pump is timing-fragile (mount/hover/click can leave the face blank). Paint
        # it deterministically right here so the arrows are visible from the moment it mounts.
        InvalidateRect( $up, undef, 0 );
        UpdateWindow($up);
    }

    # The up-down's own hot-track / click repaints erase its arrow glyphs under the poll pump
    # (verified in eg/spin_bisect_probe.pl: an explicit InvalidateRect+UpdateWindow always draws
    # the arrows). Repaint any spin-up-down the cursor is currently over on every poll tick, and
    # once more on the cursor-exit transition, so the arrows are always rendered.
    method _repaint_active_spin_arrows () {
        for my $id ( keys %{$registry} ) {
            my $rec = $registry->{$id};
            next unless $rec && $rec->{node} && $rec->{node}->type eq 'spin_box' && $rec->{aux};
            my $up    = $rec->{aux};
            my $wrect = malloc( sizeof( RECT() ) );
            GetWindowRect( $up, $wrect );
            my $r  = cast( $wrect, RECT() );
            my $pt = malloc( sizeof( POINT() ) );
            GetCursorPos($pt);
            my $p    = cast( $pt, POINT() );
            my $over = ( $p->{x} >= $r->{left} && $p->{x} < $r->{right} && $p->{y} >= $r->{top} && $p->{y} < $r->{bottom} );
            free($wrect);
            free($pt);
            my $was_over = $rec->{aux_over} || 0;
            $rec->{aux_over} = $over ? 1 : 0;

            if ( $over || $was_over ) {    # hovered, or just exited: deterministic arrow repaint
                InvalidateRect( $up, undef, 0 );
                UpdateWindow($up);
            }
        }
    }

    # Keep the spin box's edit text in sync with the buddy position. Suppressed so the edit's
    # EN_CHANGE (fired by the SetWindowTextW) is not mistaken for user typing.
    method _spin_sync_text ( $edit_hwnd, $value ) {
        $suppress_events = 1;
        SetWindowTextW( $edit_hwnd, '' . ( $value // 0 ) );
        $suppress_events = 0;

        # SetWindowTextW snaps the caret to 0; park it at the end like a read-only readout.
        my $len = CORE::length( '' . ( $value // 0 ) );
        SendMessageW( $edit_hwnd, 0x00B1, $len, $len );    # EM_SETSEL
    }

    # Make each up/down arrow click change the value by $step. The up-down control copies the
    # accelerator table, so the temp buffer is freed right after the call.
    method _spin_set_step ( $hwnd, $step ) {
        return if $step <= 1;
        my $buf = malloc( sizeof( UDACCEL() ) );
        my $ud  = cast( $buf, UDACCEL() );
        $ud->{nSec} = 0;                                           # apply immediately on the first click
        $ud->{nInc} = $step;
        SendMessageW( $hwnd, 0x046B, 1, Affix::address($buf) );    # UDM_SETACCEL
        free($buf);
    }

    # Fill a combo box or list box with its options and restore the selected value.
    #
    # Each item string is handed to the native control as a UTF-16 buffer address. The control
    # may reference those buffers lazily, so the malloc'd buffers are pinned (kept alive) until
    # the next populate for the same HWND, and freed there (the control must have copied by then,
    # since re-populate begins with RESETCONTENT).
    method _populate_strings ( $hwnd, $vnode ) {
        my $is_combo = $vnode->type eq 'combo_box';
        my $clear    = $is_combo ? 0x014B : 0x0184;    # CB_RESETCONTENT / LB_RESETCONTENT
        my $add      = $is_combo ? 0x0143 : 0x0180;    # CB_ADDSTRING / LB_ADDSTRING
        my $set      = $is_combo ? 0x014E : 0x0186;    # CB_SETCURSEL / LB_SETCURSEL
        free($_) for @{ $item_pins->{$hwnd} // [] };
        my @pins;
        for my $opt ( @{ $vnode->options } ) {
            my $text = '' . ( $opt->{label} // $opt->{value} // '' );
            my $wide = Encode::encode( 'UTF-16LE', $text );             # appends a NUL terminator
            my $buf  = malloc( CORE::length($wide) + 2 );
            memcpy( $buf, $wide, CORE::length($wide) );
            push @pins, $buf;
            SendMessageW( $hwnd, $add, 0, Affix::address($buf) );
        }
        $item_pins->{$hwnd} = \@pins;
        if ( $vnode->type eq 'list_box' && $vnode->multiple ) {
            $self->_set_multiselect( $hwnd, $vnode, $vnode->value );
        }
        else {
            my $sel = $self->_option_index( $vnode, $vnode->value );
            SendMessageW( $hwnd, $set, $sel >= 0 ? $sel : -1, 0 );
        }
    }

    # (Re)apply a (possibly multiple) selection to a multi-select list box. $want is an arrayref
    # of option values (or a scalar); the whole selection is cleared first.
    method _set_multiselect ( $hwnd, $vnode, $want ) {
        $want = [$want] unless ref $want eq 'ARRAY';
        SendMessageW( $hwnd, 0x0185, 0, -1 );    # LB_SETSEL: clear all
        my $i = 0;
        for my $opt ( @{ $vnode->options } ) {
            my $val = $opt->{value} // $opt->{label} // '';
            if ( grep { ( $_ // '' ) eq $val } @$want ) {
                SendMessageW( $hwnd, 0x0185, 1, $i );    # LB_SETSEL: select
            }
            $i++;
        }
    }

    # Index of the option whose value matches $want (or -1 when absent).
    method _option_index ( $node, $want ) {
        my $i = 0;
        for my $opt ( @{ $node->options } ) {
            return $i if ( $opt->{value} // '' ) eq ( $want // '' );
            $i++;
        }
        return -1;
    }

    method set_prop ( $vnode_id, $prop_name, $value ) {
        my $record = $registry->{$vnode_id};
        return unless $record;
        if ( $prop_name eq 'title' ) {    # Window title (root node)
            $main_hwnd = $record->{hwnd};
            SetWindowTextW( $main_hwnd, $value );
        }
        elsif ( $prop_name eq 'topmost' ) {    # window: toggle always-on-top
            SetWindowPos( $record->{hwnd}, $value ? -1 : -2, 0, 0, 0, 0, 0x0013 );
        }
        elsif ( $prop_name eq 'minimized' || $prop_name eq 'maximized' ) {    # window state
            if ($value) {
                ShowWindow( $record->{hwnd}, $prop_name eq 'minimized' ? 2 : 3 );    # SW_MINIMIZE / SW_MAXIMIZE
            }
            else {
                ShowWindow( $record->{hwnd}, 9 );                                    # SW_RESTORE
            }
        }
        elsif ( $prop_name =~ /^(min|max)_[wh]$/ ) {                                 # window min/max -> re-clamp live
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
        elsif ( $prop_name eq 'value' ) {
            if ( $record->{node}->type eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0405, 1, $value );
                return;
            }
            if ( $record->{node}->type eq 'spin_box' ) {

                # UDM_SETPOS32 moves the buddy; the edit text follows (the up/down control is
                # not in UDS_SETBUDDYINT mode  the driver owns the text).
                SendMessageW( $record->{aux}, 0x0471, 0, $value );
                $self->_spin_sync_text( $record->{hwnd}, $value );
                return;
            }
            if ( $record->{node}->type eq 'progress_bar' ) {
                SendMessageW( $record->{hwnd}, 0x0402, $self->_clamp_to_range( $record->{node}, $value ), 0 );    # PBM_SETPOS
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

                    # BM_SETCHECK: 1 = checked, 0 = unchecked
                    SendMessageW( $cr->{hwnd}, 0x00F1, $child->id eq $selected_radio ? 1 : 0, 0 );
                }
                return;
            }
            if ( $record->{node}->type eq 'combo_box' || $record->{node}->type eq 'list_box' ) {
                my $is_combo = $record->{node}->type eq 'combo_box';

                # Multi-select list: apply the whole set, not one cursor.
                return $self->_set_multiselect( $record->{hwnd}, $record->{node}, $value ) if !$is_combo && $record->{node}->multiple;
                my $sel = $is_combo ? 0x014E : 0x0186;                       # CB_SETCURSEL / LB_SETCURSEL
                my $idx = $self->_option_index( $record->{node}, $value );
                if ( $idx >= 0 ) {
                    SendMessageW( $record->{hwnd}, $sel, $idx, 0 );
                }
                elsif ( $is_combo && $record->{node}->editable ) {

                    # Skip the write when the edit already holds the same text so an in-progress
                    # caret position is never disturbed by a re-render.
                    my $cur = $self->_get_text( $record->{hwnd} );
                    if ( $cur ne $value ) {

                        # Remember the caret: SetWindowTextW snaps it to position 0, so restore
                        # the previous caret/selection rather than assuming the end of the string.
                        my ( $old_s, $old_e ) = $self->_edit_selection( $record->{hwnd} );
                        $suppress_events = 1;
                        SetWindowTextW( $record->{hwnd}, $value );
                        $suppress_events = 0;
                        SendMessageW( $record->{hwnd}, 0x0142, 0, ( $old_e << 16 ) | $old_s );
                    }
                }
                else {
                    SendMessageW( $record->{hwnd}, $sel, -1, 0 );
                }
                return;
            }

            # Only update if the native control differs (prevents typing cursor jump).
            # _get_text returns LF-only text; native edits hold CRLF, so the write goes
            # through _to_crlf and the caret parks at the natural end of the native string.
            my $current = $self->_get_text( $record->{hwnd} );
            if ( $current ne $value ) {
                my $native = $self->_to_crlf($value);
                $suppress_events = 1;
                SetWindowTextW( $record->{hwnd}, $native );
                $suppress_events = 0;

                # SetWindowTextW snaps the caret to position 0; move it to the end.
                my $len = CORE::length $native;
                SendMessageW( $record->{hwnd}, 0x00B1, $len, $len );
            }
        }
        elsif ( $prop_name eq 'enabled' ) {    # all widgets
            EnableWindow( $record->{hwnd}, $value ? 1 : 0 );
            EnableWindow( $record->{aux},  $value ? 1 : 0 ) if $record->{node}->type eq 'spin_box';
        }
        elsif ( $prop_name eq 'visible' ) {    # all widgets
            ShowWindow( $record->{hwnd}, $value ? 5 : 0 );
            ShowWindow( $record->{aux},  $value ? 5 : 0 ) if $record->{node}->type eq 'spin_box';
        }
        elsif ( $prop_name eq 'focused' ) {    # text_input / password
            SetFocus( $record->{hwnd} ) if $value;
        }
        elsif ( $prop_name eq 'tooltip' ) {    # all widgets
            $self->_set_tooltip( $record->{hwnd}, $value );
        }
        elsif ( $prop_name eq 'readonly' ) {    # EDIT: EM_SETREADONLY
            return unless $record->{node}->can('value');
            SendMessageW( $record->{hwnd}, 0x00CF, $value ? 1 : 0, 0 );
        }
        elsif ( $prop_name eq 'maxlength' ) {    # EDIT: EM_LIMITTEXT
            return unless $record->{node}->can('value');
            SendMessageW( $record->{hwnd}, 0x00C5, $value, 0 );
        }
        elsif ( $prop_name eq 'placeholder' ) {    # text_input / password / multiline_text: EM_SETCUEBANNER
            return unless $record->{node}->can('value');
            $self->_set_placeholder( $record->{hwnd}, $value );
        }
        elsif ( $prop_name eq 'password_char' ) {    # password: EM_SETPASSWORDCHAR
            return unless $record->{node}->type eq 'password';
            SendMessageW( $record->{hwnd}, 0x00CC, defined $value && length $value ? CORE::ord($value) : 0, 0 );
        }
        elsif ( $prop_name eq 'font' || $prop_name eq 'font_size' ) {    # all widgets: WM_SETFONT
            my $name = $prop_name eq 'font'      ? $value : $record->{node}->font;
            my $size = $prop_name eq 'font_size' ? $value : $record->{node}->font_size;
            $self->_set_font( $record->{hwnd}, $name, $size );
        }
        elsif ( $prop_name eq 'color' || $prop_name eq 'background' ) {    # all widgets: recolor via WM_CTLCOLOR*

            # No action needed -- the parent wndproc reads these prop values directly when the
            # control next paints (WM_CTLCOLORSTATIC/EDIT/BTN), so we force a repaint.
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'step' ) {    # slider / spin_box
            my $t = $record->{node}->type;
            return unless $t eq 'slider' || $t eq 'spin_box';
            if ( $t eq 'spin_box' ) {
                return $self->_spin_set_step( $record->{aux}, $value );
            }
            SendMessageW( $record->{hwnd}, 0x041C, 1, $value );
            SendMessageW( $record->{hwnd}, 0x041D, 1, $value );
        }
        elsif ( $prop_name eq 'checked' ) {    # checkbox / toggle_switch / toggle_button: BM_SETCHECK
            my $t = $record->{node}->type;
            return unless $t eq 'checkbox' || $t eq 'toggle_switch' || $t eq 'toggle_button';
            SendMessageW( $record->{hwnd}, 0x00F1, $value ? 1 : 0, 0 );
        }
        elsif ( $prop_name eq 'options' ) {    # combo_box / list_box: rebuild item strings + reselect
            return unless $record->{node}->type eq 'combo_box' || $record->{node}->type eq 'list_box';
            $self->_populate_strings( $record->{hwnd}, $record->{node} );
        }
        elsif ( $prop_name eq 'min' || $prop_name eq 'max' ) {
            my $t = $record->{node}->type;
            return unless $t eq 'slider' || $t eq 'spin_box' || $t eq 'progress_bar';
            my $min = $prop_name eq 'min' ? $value : $record->{node}->min;
            my $max = $prop_name eq 'max' ? $value : $record->{node}->max;
            if ( $t eq 'progress_bar' ) {
                SendMessageW( $record->{hwnd}, 0x0406, $min, $max );    # PBM_SETRANGE32: wParam=min, lParam=max
            }
            elsif ( $t eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0401, 1, ( $max << 16 ) | $min );    # TBM_SETRANGE
            }
            else {
                SendMessageW( $record->{aux} || $record->{hwnd}, 0x046F, 0, ( $max << 16 ) | $min );    # UDM_SETRANGE32
            }
        }
    }

    method move_widget ( $vnode_id, $x, $y, $w, $h ) {
        my $record = $registry->{$vnode_id};

        #print $lfh "  MOVE id=$vnode_id rec=", ( $record ? sprintf( "hwnd=%s", $record->{hwnd} ) : 'none' ), " xywh=($x,$y,$w,$h)\n";
        return unless $record && $record->{hwnd};    # containers have no HWND
        SetWindowPos( $record->{hwnd}, undef, $x, $y, $w, $h, 0x0004 );

        # A spin box's edit and its up/down buddy sit side by side (EDIT = w-cxv, buddy = right strip),
        # so each follows the move keeping that split.
        if ( $record->{node} && $record->{node}->type eq 'spin_box' && $record->{aux} ) {
            my $sw = GetSystemMetrics(2);    # SM_CXVSCROLL
            SetWindowPos( $record->{hwnd}, undef, $x,            $y, $w - $sw, $h, 0x0004 );
            SetWindowPos( $record->{aux},  undef, $x + $w - $sw, $y, $sw,      $h, 0x0004 );
        }
    }
};
1;
