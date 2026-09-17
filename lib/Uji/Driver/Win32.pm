use v5.40;
use experimental 'class';
use Uji::Driver;
class Uji::Driver::Win32 v0.0.1 : isa(Uji::Driver) {

    # user32.dll, gdi32.dll
    use Affix  qw[:memory :types :core];
    use Encode qw[decode encode];
    field $channel : reader;
    field $registry = {};
    field $wndproc_cb;
    field $main_hwnd;
    field $main_vnode      : reader;
    field $tooltip_hwnd    : reader                      = undef;
    field $on_resize       : reader(_get_resize_handler) = undef;
    field $on_modal_pump   : reader(_get_modal_pump)     = undef;    # synchronous tick/render hook for modal loops
    field $suppress_events : reader(_is_suppressed)      = 0;
    field $item_pins   = {};      # hwnd -> [ malloc'd UTF-16 item strings still referenced by the control ]
    field $brush_cache = {};      # '#RRGGBB' -> HBRUSH
    field $font_cache  = {};      # 'Name|Size' -> HFONT
    field $cmd_counter = 0x4000
        ; # monotonic idCommand allocator for toolbar buttons AND menu items (WM_COMMAND needs idCommand; IDs in the 0x4000+ range avoid control-id collisions)
    field $toolbar_cmds = {};    # idCommand -> toolbar vnode id (WM_COMMAND routing)
    field $menu_cmds    = {};    # idCommand -> { win_id => surface_id } (WM_COMMAND routing for menu items)
    field $modal_timer = 0;      # 1 while a frame-drag modal loop drives the WM_TIMER pump
    field $prompt_hwnd;          # live prompt_dialog window (modal EDIT + OK/Cancel)
    field $prompt_edit;          # the EDIT child of the current prompt_dialog
    field $prompt_done = 0;      # modal loop exit flag (OK / Cancel / WM_CLOSE)
    field $prompt_value;         # captured text (undef until OK)

    # Custom window class names are PER-INSTANCE (a monotonic suffix per driver): RegisterClassExW
    # silently no-ops when a class name already exists, and the wndproc closure captures the FIRST
    # registering driver. Two live drivers (e.g. an app + a shared $drv used for dialogs) would
    # otherwise route every message for the second driver's windows into the first driver's state --
    # a second prompt_dialog would never see its own prompt_done flag. Unique names keep each
    # driver's windows bound to its own closure.
    my $class_seq = 0;
    field $win_class      = '';
    field $viewport_class = '';
    field $divider_class  = '';
    field $prompt_class   = '';

    # Per-surface registries for the shared-pump multi-window skeleton. Each surface (top-level HWND
    # family) owns a records map so WM_ACTIVATE / WM_CLOSE / tooltips route by surface. Today the only
    # live surface is 'main' (a placeholder _mount_sibling_window can reserve extra surfaces before real
    # sibling top-level HWNDs are wired by the reconciler).
    field $surfaces        : reader = {};    # surface_id => { hwnd, node, records => HASHREF, planned => 0|1 }
    field $surface_by_hwnd : reader = {};    # hwnd -> surface_id

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
    affix 'user32', 'SetTimer',         [ Pointer [Void], Size_t, UInt, Pointer [Void] ]             => Size_t;
    affix 'user32', 'KillTimer',        [ Pointer [Void], Size_t ]                                   => Int;
    affix 'user32', 'UpdateWindow',     [ Pointer [Void] ]                                           => Int;
    affix 'user32', 'InvalidateRect',   [ Pointer [Void], Pointer [Void], Int ]                      => Int;
    affix 'user32', 'GetCursorPos',     [ Pointer [Void] ]                                           => Int;
    affix 'user32', 'LoadCursorW',      [ Pointer [Void], Size_t ]                                   => Pointer [Void];
    affix 'user32', 'GetSystemMetrics', [Int]                                                        => Int;
    affix 'user32', 'SendMessageW',     [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;
    affix 'user32', 'SetScrollInfo',    [ Pointer [Void], Int, Pointer [Void], Int ]                 => Int;
    affix 'user32', 'GetScrollInfo',    [ Pointer [Void], Int, Pointer [Void] ]                      => Int;
    affix 'user32', 'SetCursor',        [ Pointer [Void] ]                                           => Pointer [Void];
    affix 'user32', 'SetCapture',       [ Pointer [Void] ]                                           => Pointer [Void];
    affix 'user32', 'ClientToScreen',   [ Pointer [Void], Pointer [Void] ]                           => Int;
    affix 'user32', 'ScreenToClient',   [ Pointer [Void], Pointer [Void] ]                           => Int;

    # Menu bar (CreateMenuW / CreatePopupMenu return HMENU values, Size_t on Win64)
    affix 'user32', 'CreateMenu',      []                                 => Size_t;
    affix 'user32', 'CreatePopupMenu', []                                 => Size_t;
    affix 'user32', 'AppendMenuW',     [ Size_t, ULong, Size_t, WString ] => Int;
    affix 'user32', 'SetMenu',         [ Pointer [Void], Size_t ]         => Int;
    affix 'user32', 'DrawMenuBar',     [ Pointer [Void] ]                 => Int;
    affix 'user32', 'DestroyMenu',     [Size_t]                           => Int;

    # System dialogs (comdlg32: file open/save, colour picker; user32: message box)
    typedef OPENFILENAMEW => Struct [
        lStructSize => ULong,
        ( map { $_ => Pointer [Void] } qw[hwndOwner hInstance lpstrFilter lpstrCustomFilter] ),
        ( map { $_ => ULong } qw[nMaxCustFilter nFilterIndex] ),
        lpstrFile         => Pointer [Void],
        nMaxFile          => ULong,
        lpstrFileTitle    => Pointer [Void],
        nMaxFileTitle     => ULong,
        lpstrInitialDir   => Pointer [Void],
        lpstrTitle        => Pointer [Void],
        Flags             => ULong,
        nFileOffset       => UShort,
        nFileExtension    => UShort,
        lpstrDefExt       => Pointer [Void],
        lCustData         => SSize_t,
        lpfnHook          => Pointer [Void],
        lpstrTemplateName => Pointer [Void],
        pvReserved        => Pointer [Void],
        dwReserved        => ULong,
        FlagsEx           => ULong,
    ];
    typedef CHOOSECOLORW => Struct [
        lStructSize    => ULong,
        hwndOwner      => Pointer [Void],
        hInstance      => Pointer [Void],
        rgbResult      => ULong,
        lpCustColors   => Pointer [Void],
        Flags          => ULong,
        lCustData      => SSize_t,
        lpfnHook       => Pointer [Void],
        lpTemplateName => Pointer [Void],
    ];
    affix 'comdlg32', 'GetOpenFileNameW', [ Pointer [ OPENFILENAMEW() ] ]                => Int;
    affix 'comdlg32', 'GetSaveFileNameW', [ Pointer [ OPENFILENAMEW() ] ]                => Int;
    affix 'comdlg32', 'ChooseColorW',     [ Pointer [ CHOOSECOLORW() ] ]                 => Int;
    affix 'user32',   'MessageBoxW',      [ Pointer [Void], WString, WString, UInt ]     => Int;
    affix 'user32',   'GetMessageW',      [ Pointer [Void], Pointer [Void], UInt, UInt ] => Int;
    affix 'user32',   'IsDialogMessageW', [ Pointer [Void], Pointer [Void] ]             => Int;
    affix 'user32',   'GetFocus',         []                                             => Pointer [Void];
    affix 'user32',   'GetWindowWord',    [ Pointer [Void], Int ]                        => UShort;

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
    typedef NMHDR => Struct [ hwndFrom => Pointer [Void], idFrom => Size_t, code => Int ];
    typedef TCITEMW =>
        Struct [ mask => UInt, dwState => UInt, dwStateMask => UInt, pszText => WString, cchTextMax => Int, iImage => Int, lParam => SSize_t ];
    affix 'user32', 'GetWindowTextLengthW', [ Pointer [Void] ]                      => Int;
    affix 'user32', 'GetWindowTextW',       [ Pointer [Void], Pointer [Void], Int ] => Int;
    affix 'user32', 'GetClientRect',        [ Pointer [Void], Pointer [Void] ]      => Int;
    affix 'user32', 'GetWindowRect',        [ Pointer [Void], Pointer [Void] ]      => Int;
    affix 'user32', 'AdjustWindowRectEx',   [ Pointer [ RECT() ], UInt, Int, UInt ] => Int;
    affix 'user32', 'IsZoomed',             [ Pointer [Void] ]                      => Int;
    affix 'user32', 'IsIconic',             [ Pointer [Void] ]                      => Int;

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
    affix 'user32', 'GetClassLongPtrW',         [ Pointer [Void], Int ]                 => Size_t;
    affix 'user32', 'GetWindowThreadProcessId', [ Pointer [Void], Pointer [UInt] ]      => UInt;
    affix 'user32', 'GetSysColorBrush',         [Int]                                   => Pointer [Void];
    typedef UDACCEL => Struct [ nSec => UInt, nInc => UInt ];
    my $icc   = malloc( sizeof( INITCOMMONCONTROLSEX() ) );
    my $icc_s = cast( $icc, INITCOMMONCONTROLSEX() );
    $icc_s->{dwSize} = sizeof( INITCOMMONCONTROLSEX() );

    # ICC_UPDOWN_CLASS (0x1) | ICC_TREEVIEW_CLASSES (0x2) | ICC_BAR_CLASSES (0x4) | ICC_PROGRESS_CLASS (0x20)
    $icc_s->{dwICC} = 0x00000027;
    InitCommonControlsEx($icc);
    free($icc);
    ADJUST {
    }

    method init ($app_channel) {
        $channel = $app_channel;
        my $self_ref = $self;
        $wndproc_cb = sub ( $hwnd, $msg, $wparam, $lparam ) {

            # Control-level messages are routed through the shared handler so the scroll-view
            # viewport class dispatches WM_COMMAND / WM_HSCROLL / WM_VSCROLL / WM_CTLCOLOR*
            # exactly like the app window does.
            my ( $ctl, $ret ) = $self_ref->_ctrl_msg( $hwnd, $msg, $wparam, $lparam );
            return $ret if $ctl;
            if ( $msg == 0x0002 ) {    # WM_DESTROY
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
            elsif ( $msg == 0x0231 ) {    # WM_ENTERSIZEMOVE -> start the modal redraw/tick pump

                # Dragging the frame drops Windows into its own modal loop, during which the app's
                # fibers are suspended. A WM_TIMER is still dispatched by that loop, so arm one and
                # let it drive the synchronous pump until the drag ends.
                $modal_timer = 1;
                SetTimer( $hwnd, 1, 16, undef );
            }
            elsif ( $msg == 0x0232 ) {    # WM_EXITSIZEMOVE -> stop the modal pump
                $modal_timer = 0;
                KillTimer( $hwnd, 1 );
            }
            elsif ( $msg == 0x0113 ) {    # WM_TIMER -> keep the app alive during the modal loop

                # Gate on the drag flag: KillTimer does not flush a WM_TIMER already in the queue,
                # and this id/flag pair must never run the pump outside a drag.
                if ( $wparam == 1 && $modal_timer ) {
                    my $pump = $self_ref->_get_modal_pump;
                    $pump->() if $pump;
                    return 0;
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
            elsif ( $msg == 0x020A || $msg == 0x020E ) {    # WM_MOUSEWHEEL / WM_MOUSEHWHEEL

                # Route the wheel to the scroll_view under the cursor (DefWindowProc only scrolls
                # windows that have their own WS_VSCROLL style -- our scrollbars are separate
                # SCROLLBAR controls, so the wheel would otherwise be dropped entirely). The wheel
                # arrives at the focused top-level window; the cursor position decides which
                # viewport/scrollbar to move.
                my $axis   = $msg == 0x020E ? 'h' : 'v';
                my $target = $self_ref->_wheel_target( $axis, $lparam );
                if ($target) {
                    my $delta = ( ( $wparam >> 16 ) & 0xFFFF );
                    $delta = $delta >= 0x8000 ? $delta - 0x10000 : $delta;    # WHEEL_DELTA is signed
                    $delta ||= 1;                                             # degenerate 0 -> one notch
                    my $steps = int( abs($delta) / 120 ) || 1;
                    my $code  = $delta > 0 ? 0 : 1;                           # SB_LINEUP / SB_LINEDOWN
                    $self_ref->_scrollbar_event( $target, $axis, ( $code << 16 ) | $code ) for 1 .. $steps;
                    return 0;
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
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
        $wc->{lpszClassName} = $win_class = 'UjiWindowClass' . ++$class_seq;
        RegisterClassExW($wndclass);

        # Clipping viewport window used by scroll_view. It reroutes control messages through the
        # same handler as the app window so content widgets inside a scrolled region still work,
        # then lets DefWindowProcW handle everything else.
        my $viewport_proc = sub ( $hwnd, $msg, $wparam, $lparam ) {
            my ( $ctl, $ret ) = $self_ref->_ctrl_msg( $hwnd, $msg, $wparam, $lparam );
            return $ret if $ctl;
            return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
        };
        my $vclass = malloc( sizeof( WNDCLASSEXW() ) );
        my $cv     = cast( $vclass, WNDCLASSEXW() );
        $cv->{cbSize}        = sizeof( WNDCLASSEXW() );
        $cv->{style}         = 0x0000;
        $cv->{lpfnWndProc}   = $viewport_proc;
        $cv->{hInstance}     = undef;
        $cv->{hbrBackground} = cast( 16, Pointer [Void] );    # COLOR_BTNFACE + 1
        $cv->{lpszClassName} = $viewport_class = 'UjiViewportClass' . ++$class_seq;
        $cv->{hCursor}       = LoadCursorW( undef, 32512 );
        RegisterClassExW($vclass);
        free($vclass);

        # Draggable divider strip for split_view: a plain child window whose class brush paints
        # the face and whose wndproc drives the drag. WM_LBUTTONDOWN begins capture; every
        # WM_MOUSEMOVE while captured recomputes the divider position from the real cursor
        # (screen coords -> app-window client -> split-local main axis), re-positions the strip,
        # and dispatches on_divider for the model to re-render. WM_LBUTTONUP ends it. The sizer
        # cursor is chosen per split orientation through _divider_cursor (WM_SETCURSOR).
        my $divider_proc = sub ( $hwnd, $msg, $wparam, $lparam ) {
            if ( $msg == 0x0201 ) {    # WM_LBUTTONDOWN
                $self_ref->_divider_begin($hwnd);
                SetCapture($hwnd);
                return 0;
            }
            if ( $msg == 0x0202 ) {    # WM_LBUTTONUP
                $self_ref->_divider_end($hwnd);
                SetCapture(undef);
                return 0;
            }
            if ( $msg == 0x0200 ) {    # WM_MOUSEMOVE (capture routes moves here while dragging)
                $self_ref->_divider_drag($hwnd) if $self_ref->_divider_active($hwnd);
                return 0;
            }
            if ( $msg == 0x0020 ) {    # WM_SETCURSOR -> orientation-aware sizing cursor
                if ( my $cur = $self_ref->_divider_cursor($hwnd) ) {
                    SetCursor($cur);
                    return 1;
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
            }
            return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
        };
        my $dclass = malloc( sizeof( WNDCLASSEXW() ) );
        my $cd     = cast( $dclass, WNDCLASSEXW() );
        $cd->{cbSize}        = sizeof( WNDCLASSEXW() );
        $cd->{style}         = 0x0000;
        $cd->{lpfnWndProc}   = $divider_proc;
        $cd->{hInstance}     = undef;
        $cd->{hbrBackground} = cast( 18, Pointer [Void] );    # COLOR_BTNSHADOW + 1: a solid grey that reads as a splitter on a white body
        $cd->{lpszClassName} = $divider_class = 'UjiDividerClass' . ++$class_seq;
        $cd->{hCursor}       = LoadCursorW( undef, 32512 );
        RegisterClassExW($dclass);
        free($dclass);

        # Modal text-input window for prompt_dialog: a popup with an EDIT child plus OK/Cancel.
        # WM_COMMAND button IDs are 1 (OK) / 2 (Cancel); WM_CLOSE counts as cancel.
        my $prompt_proc = sub ( $hwnd, $msg, $wparam, $lparam ) {
            if ( $msg == 0x0111 ) {    # WM_COMMAND
                my $id = $wparam & 0xFFFF;
                if ( $id == 1 ) {      # OK button -> capture the edit text
                    my $edit = $self_ref->_get_prompt_edit;
                    if ($edit) {
                        my $len = GetWindowTextLengthW($edit);
                        my $buf = malloc( ( $len + 1 ) * 2 );
                        GetWindowTextW( $edit, $buf, $len + 1 );
                        $self_ref->_set_prompt_value( decode( 'UTF-16LE', Affix::raw( $buf, $len * 2 ) ) );
                        free($buf);
                    }
                    $self_ref->_prompt_finish;
                    return 0;
                }
                if ( $id == 2 ) {      # Cancel button
                    $self_ref->_set_prompt_value(undef);
                    $self_ref->_prompt_finish;
                    return 0;
                }
            }
            if ( $msg == 0x0010 ) {    # WM_CLOSE -> cancel
                $self_ref->_set_prompt_value(undef);
                $self_ref->_prompt_finish;
                return 0;
            }
            return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
        };
        my $pclass = malloc( sizeof( WNDCLASSEXW() ) );
        my $cp     = cast( $pclass, WNDCLASSEXW() );
        $cp->{cbSize}        = sizeof( WNDCLASSEXW() );
        $cp->{style}         = 0x0000;
        $cp->{lpfnWndProc}   = $prompt_proc;
        $cp->{hInstance}     = undef;
        $cp->{hbrBackground} = cast( 0, Pointer [Void] );     # COLOR_WINDOW: white body
        $cp->{lpszClassName} = $prompt_class = 'UjiPromptClass' . ++$class_seq;
        $cp->{hCursor}       = LoadCursorW( undef, 32512 );
        RegisterClassExW($pclass);
        free($pclass);
    }

    # Shared routing for control-level messages, used by both the app-window wndproc and the
    # scroll-view viewport wndproc. Returns (1, $result) when the message was consumed (caller
    # must return $result) or (0, undef) when the caller should pass it to DefWindowProcW.
    method _ctrl_msg ( $hwnd, $msg, $wparam, $lparam ) {
        if ( $msg == 0x0111 ) {    # WM_COMMAND
            my $control_id  = $wparam & 0xFFFF;
            my $notify_code = ( $wparam >> 16 ) & 0xFFFF;

            # Toolbar button clicks: BN_CLICKED (0) with command id from the button's
            # TBBUTTON.idCommand. These IDs are NOT registered as child window control IDs,
            # so _get_registry_record returns undef; route through the toolbar command table.
            if ( $notify_code == 0 && $toolbar_cmds->{$control_id} ) {
                my $tb_id  = $toolbar_cmds->{$control_id};
                my $tb_rec = $registry->{$tb_id};
                if ($tb_rec) {
                    my $tb_node = $tb_rec->{node};
                    if ( $tb_node->can('on_click') && $tb_node->on_click ) {
                        my $btn_id = $tb_rec->{toolbar}{by_cmd}{$control_id}{id} // $control_id;
                        my $action = $tb_node->on_click->($btn_id);
                        $self->channel->put($action) if $action;
                    }
                }
                return ( 1, 0 );
            }

            # Menu item clicks: WM_COMMAND (BN_CLICKED) with the item's idCommand. Menu
            # items live on a MenuBar node attached to a surface window; the route
            # resolves the win record and reads the CURRENT menu_bar node (kept fresh by
            # update_registry) so a reconciled on_click closure is always used.
            if ( $notify_code == 0 && $menu_cmds->{$control_id} ) {
                my $route   = $menu_cmds->{$control_id};
                my $win_rec = $registry->{ $route->{win_id} };
                if ($win_rec) {
                    my $win_node = $win_rec->{node};
                    my $mb_node  = $win_node && $win_node->can('menu_bar') ? $win_node->menu_bar : undef;
                    if ( $mb_node && $mb_node->can('on_click') && $mb_node->on_click ) {
                        my $item_id = $win_rec->{menu_bar}{by_cmd}{$control_id}{id} // $control_id;
                        my $action  = $mb_node->on_click->($item_id);
                        $self->channel->put($action) if $action;
                    }
                }
                return ( 1, 0 );
            }
            my $record = $self->_get_registry_record($control_id);
            if ($record) {
                my $node = $record->{node};

                # BN_CLICKED (0) -> Button click. on_click is dispatched: a static message
                # hashref is put verbatim; a callback is invoked and its return value is put.
                if ( $notify_code == 0 && $node->can('on_click') && $node->on_click ) {
                    my $on_click = $node->on_click;
                    my $action   = ref $on_click eq ref {} ? $on_click : $on_click->();
                    $self->channel->put($action) if $action;
                }

                # BN_CLICKED (0) -> Checkbox toggle: read the actual state back from the control
                elsif ( $notify_code == 0 && $node->can('on_toggle') && $node->on_toggle ) {
                    my $checked    = SendMessageW( $record->{hwnd}, 0x00F0, 0, 0 );    # BM_GETCHECK
                    my $action_msg = $node->on_toggle->( $checked ? 1 : 0 );
                    $self->channel->put($action_msg) if $action_msg;
                }

                # BN_CLICKED (0) -> Radio select: dispatch the clicked option's value
                elsif ( $notify_code == 0 && $node->can('on_select') && $node->on_select ) {
                    my $action_msg = $node->on_select->( $node->value );
                    $self->channel->put($action_msg) if $action_msg;
                }

                # EN_CHANGE (0x0300) -> Text changed by user typing
                elsif ( $notify_code == 0x0300 && $node->can('on_input') && $node->on_input ) {

                    # Ignore EN_CHANGE if triggered programmatically by SetWindowTextW!
                    return ( 1, DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) ) if $self->_is_suppressed;
                    my $text       = $self->_get_text( $record->{hwnd} );
                    my $action_msg = $node->on_input->($text);
                    $self->channel->put($action_msg) if $action_msg;
                }

                # CBN_EDITCHANGE (5) -> user typed in an editable combo box
                elsif ( $notify_code == 0x0005 && $node->type eq 'combo_box' && $node->on_input ) {

                    # Ignore if triggered programmatically (SetWindowTextW / CB_SETCURSEL)
                    return ( 1, DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) ) if $self->_is_suppressed;
                    my $text       = $self->_get_text( $record->{hwnd} );
                    my $action_msg = $node->on_input->($text);
                    $self->channel->put($action_msg) if $action_msg;
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
                        $self->channel->put($action_msg) if $action_msg;
                    }
                    else {
                        my $is_combo = $node->type eq 'combo_box';
                        my $idx      = SendMessageW( $record->{hwnd}, $is_combo ? 0x0147 : 0x0188, 0, 0 );    # CB_GETCURSEL / LB_GETCURSEL
                        my $value;
                        if ( $idx >= 0 ) {
                            $value = $node->options->[$idx]{value} // $node->options->[$idx]{label} // '';
                        }
                        elsif ( $is_combo && $node->editable ) {
                            $value = $self->_get_text( $record->{hwnd} );                                     # typed text not in the list
                        }
                        else {
                            $value = '';
                        }
                        my $action_msg = $node->on_select->($value);
                        $self->channel->put($action_msg) if $action_msg;
                    }
                }
            }
            return ( 1, 0 );
        }
        elsif ( $msg == 0x0114 || $msg == 0x0115 ) {    # WM_HSCROLL / WM_VSCROLL
            my $axis = $msg == 0x0114 ? 'h' : 'v';
            my $sbid = $self->_registry_id_by_key( $lparam, "aux_$axis" );
            if ($sbid) {                                # a scroll_view's native scrollbar
                $self->_scrollbar_event( $sbid, $axis, $wparam );
                return ( 1, 0 );
            }

            # Slider / trackbar drag (WM_HSCROLL for horizontal; WM_VSCROLL for vertical trackbars).
            my $record = $self->_get_registry_by_hwnd($lparam);
            if ( $record && $record->{node} && $record->{node}->type eq 'slider' ) {
                my $node = $record->{node};
                if ( $node->can('on_change') && $node->on_change ) {
                    my $pos = SendMessageW( $lparam, 0x0400, 0, 0 );    # TBM_GETPOS
                    my $msg = $node->on_change->($pos);
                    $self->channel->put($msg) if $msg;
                }
                return ( 1, 0 );
            }

            # Otherwise a spin box arrow: lParam = the msctls_updown32 buddy.
            $record = $self->_get_registry_by_aux($lparam);
            if ($record) {
                my $node = $record->{node};
                my $pos  = SendMessageW( $lparam, 0x0472, 0, 0 );    # UDM_GETPOS32
                $self->_spin_sync_text( $record->{hwnd}, $pos );
                if ( $node->can('on_change') && $node->on_change ) {
                    my $msg = $node->on_change->($pos);
                    $self->channel->put($msg) if $msg;
                }
                return ( 1, 0 );
            }
            return ( 0, undef );
        }

        # WM_CTLCOLORSTATIC (0x0138) / WM_CTLCOLOREDIT (0x0133) / WM_CTLCOLORBTN (0x0135):
        # Return a brush + set text/background colours for the child control. We must NOT
        # fall through to DefWindowProc here: DefWindowProc restores the DC's text/background
        # colours to system defaults, silently discarding our SetTextColor/SetBkColor.
        elsif ( $msg == 0x0138 || $msg == 0x0133 || $msg == 0x0135 ) {
            my $child_hwnd = $lparam;
            my $record     = $self->_get_registry_by_hwnd($child_hwnd);
            if ( $record && $record->{node} ) {
                my $node = $record->{node};
                my $hdc  = $wparam;
                if ( $node->color ) {
                    SetTextColor( $hdc, $self->_parse_color( $node->color ) );
                }
                if ( $node->background ) {
                    SetBkColor( $hdc, $self->_parse_color( $node->background ) );
                    return ( 1, $self->_get_brush( $node->background ) );
                }
            }

            # No explicit background: return the same system brush DefWindowProc would
            # (COLOR_WINDOW for edits, COLOR_BTNFACE for statics/buttons) without touching
            # the DC, so the SetTextColor above is preserved.
            return ( 1, GetSysColorBrush( $msg == 0x0133 ? 5 : 15 ) );    # COLOR_WINDOW / COLOR_BTNFACE
        }
        elsif ( $msg == 0x004E ) {                                        # WM_NOTIFY (tab control sends TCN_SELCHANGE to its parent)
            return ( 0, undef ) unless $lparam;
            my $nm   = cast( $lparam, NMHDR() );
            my $from = $nm->{hwndFrom} ? Affix::address( $nm->{hwndFrom} ) : 0;
            return ( 0, undef ) unless $from;
            my $id     = $self->_registry_id_by_key( $from, 'hwnd' ) or return ( 0, undef );
            my $record = $registry->{$id}                            or return ( 0, undef );
            my $node   = $record->{node}                             or return ( 0, undef );
            # TCN_SELCHANGE (-551): the user clicked a tab. Sync the record's live index, flip
            # the visible panel subtree, and dispatch on_select with the new index.
            # (TCN_SELCHANGING is -552 and is ignored; only the change matters.)
            if ( $node->type eq 'tab_panel' && $nm->{code} == -551 ) {
                my $idx = SendMessageW( $from, 0x130B, 0, 0 );    # TCM_GETCURSEL
                $record->{index} = $idx;
                $self->_apply_tab($id);
                if ( $node->can('on_select') && $node->on_select ) {
                    my $action = $node->on_select->($idx);
                    $self->channel->put($action) if $action;
                }
                return ( 1, 0 );
            }

            # TVN_SELCHANGED (-451): the user clicked/arrowed to a tree item. The NMTREEVIEWW
            # lParam of the freshly selected item is the insert-time slot index (a hash key over
            # model values), so the notification is routed back to the item's value without any
            # handle arithmetic. (The struct's itemNew.lParam sits at raw offset 136 on Win64:
            # NMHDR 24 + action 4 + pad 4 + itemOld 56 + itemNew.lParam at itemNew+48.)
            if ( $node->type eq 'tree_view' && $nm->{code} == -451 ) {
                my $raw  = Affix::raw( $lparam, 152 );
                my $slot = unpack( 'q<', substr( $raw, 136, 8 ) );
                my $val  = $record->{tree}{slots}[$slot]{value};
                if ( defined $val && $node->can('on_select') && $node->on_select ) {
                    my $action = $node->on_select->($val);
                    $self->channel->put($action) if $action;
                }
                return ( 1, 0 );
            }

            # LVN_COLUMNCLICK (-108, LVN_FIRST-8): the user clicked a column header. When the list is
            # `sortable`, retarget the visible rows by that column (per-column `sort => 'numeric'`,
            # else text), toggling asc/desc on repeated clicks, then dispatch on_sort so the app can
            # reorder its own `rows`. The NMLISTVIEW.iSubItem (offset 28) holds the column index.
            if ( $node->type eq 'list_view' && $nm->{code} == -108 ) {
                my $lv = $record->{listview};
                if ( $lv && $node->sortable ) {
                    my $raw = Affix::raw( $lparam, 40 );
                    # NMLISTVIEW.iSubItem. Post-reorder, the native header reports the column by its
                    # MODEL identity (its index in the column array), not the visual slot it displays
                    # in — so a header drag + click does NOT map back through lv_column_order (that
                    # would double-shift onto the column that happens to sit in the clicked slot).
                    my $col = unpack( 'l<', substr( $raw, 28, 4 ) );
                    my $dir = ( $lv->{sort}{col} // -1 ) == $col && $lv->{sort}{dir} eq 'asc' ? 'desc' : 'asc';
                    $self->_sort_listview( $id, $col, $dir );
                    if ( $node->can('on_sort') && $node->on_sort ) {
                        my $action = $node->on_sort->( $col, $dir );
                        $self->channel->put($action) if $action;
                    }
                }
                return ( 1, 0 );
            }

            # LVN_ITEMCHANGED (-101, LVN_FIRST-1): the user clicked/arrowed a row (or the model
            # re-selected via set_prop('value')). NMLISTVIEW.iItem sits at raw offset 24 and
            # uNewState at 32. The record's slot table maps the row index back to the model value.
            # Ignore focus-only and deselect notifications (uNewState without LVIS_SELECTED) and
            # programmatic selection (silenced by set_prop the same way editable combo text is).
            # NB: the populate-time flood of -104 (LVN_DELETEALLITEMS) / -102 (LVN_INSERTITEM)
            # notifications carries no state and is naturally skipped by the LVIS_SELECTED mask.
            if ( $node->type eq 'list_view' && $nm->{code} == -101 ) {
                return ( 1, 0 ) if $self->_is_suppressed;
                my $raw = Affix::raw( $lparam, 64 );
                my $iit = unpack( 'l<', substr( $raw, 24, 4 ) );
                my $nst = unpack( 'L<', substr( $raw, 32, 4 ) );
                return ( 1, 0 ) unless $nst & 0x0002;    # LVIS_SELECTED
                return ( 1, 0 ) unless $record->{listview};
                my $selected;
                if ( $node->multiple ) {
                    my $count = SendMessageW( $from, 0x1004, 0, 0 );    # LVM_GETITEMCOUNT
                    my @values;
                    for my $i ( 0 .. $count - 1 ) {
                        my $st = SendMessageW( $from, 0x102C, $i, 0x0002 );    # LVM_GETITEMSTATE(i, LVIS_SELECTED)
                        next unless defined $record->{listview}{slots}[$i]{value};
                        push @values, $record->{listview}{slots}[$i]{value} if $st & 0x0002;
                    }
                    $selected = \@values;
                }
                else {
                    $selected = $record->{listview}{slots}[$iit]{value};
                    return ( 1, 0 ) unless defined $selected;
                }
                if ( $node->can('on_select') && $node->on_select ) {
                    my $action = $node->on_select->($selected);
                    $self->channel->put($action) if $action;
                }
                return ( 1, 0 );
            }
            return ( 1, 0 );
        }
        return ( 0, undef );
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

    # Normalize a model string to a FLAGGED character string before any WString marshaling.
    # Affix's WString maps each perl BYTE of an un-flagged scalar straight to a UTF-16 codepoint
    # (Latin-1 semantics), so UTF-8 octets the app supplies verbatim (the default for literals
    # and read data under use v5.40, whose string flag is off) would become "cafÃ©" in the
    # control. Valid UTF-8 octets are decoded to characters; anything else is treated as Latin-1
    # and upgraded in place. Flagged strings (already characters) pass through untouched.
    method _nz ($s) {
        $s //= '';
        return $s if utf8::is_utf8($s);
        if ( eval { utf8::decode($s); 1 } ) {
            return $s;    # UTF-8 octets -> characters
        }
        utf8::upgrade($s);    # Latin-1 octets taken as-is
        return $s;
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
        $name //= '';
        $name = $self->_nz($name);
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
    # Find a top-level window of this driver's window class by its title (used by probes for introspection).
    method _find_window ($title) {
        return FindWindowW( $win_class, $self->_nz($title) );
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

    # Synchronous hook invoked from WM_TIMER while Windows is inside a frame-drag modal loop
    # (and from the dialog modal pump), so timers and rendering keep running there.
    method set_modal_pump ($cb) { $on_modal_pump = $cb; $self }

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };

        # Keep the live window node (read by WM_GETMINMAXINFO) current across re-renders, both in
        # the registry record AND the surface record: WM_GETMINMAXINFO resolves via surfaces so a
        # min_w/max_w/etc. added or changed by the reconciler must be visible there too.
        if ( $node->type eq 'window' ) {
            $main_vnode = $node;
            $surfaces->{ $node->id }{node} = $node if exists $surfaces->{ $node->id };
        }
    }

    method mount ($vtree) {
        my $surface_id = $vtree->id;
        $main_vnode //= $vtree;    # keep the first as fallback

        # WS_OVERLAPPEDWINDOW (0x10CF0000); drop WS_THICKFRAME (0x00040000) when not resizable
        my $style = $vtree->resizable ? 0x10CF0000 : 0x10CB0000;
        my $hwnd
            = CreateWindowExW( 0, $win_class, $self->_nz( $vtree->title ), $style, 100, 100, $vtree->w, $vtree->h, undef, 0, undef, undef );
        $registry->{ $vtree->id } = { hwnd => $hwnd, node => $vtree, surface => $surface_id };
        $surfaces->{$surface_id}  = { hwnd => $hwnd, node => $vtree, records => {} };
        $surface_by_hwnd->{$hwnd} = $surface_id;
        $main_hwnd //= $hwnd;      # First window acts as main (e.g. for tooltips)

        # Menu bar: attach BEFORE measuring the client area, because SetMenu reduces the client
        # rect by the menu bar's height (Layout must see the reduced space when it computes slots).
        $self->_mount_menu_bar( $vtree->id ) if $vtree->menu_bar;

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

        # A fullscreen maximize bypasses WM_GETMINMAXINFO track clamps, so refuse it whenever any
        # min/max constraint is defined (mount-time equivalent of the set_prop('maximized') guard).
        my $show_style = $vtree->maximized && !$self->_has_size_constraints($vtree) ? 3 : $vtree->minimized ? 2 : 5;
        ShowWindow( $hwnd, $show_style );
        UpdateWindow($hwnd);
    }

    method unmount ($vtree) {
        my $surface_id = $vtree->id;
        my $surface    = $surfaces->{$surface_id};

        # Destroy the native menu bar (frees attached popups) and drop its command routes.
        if ( $surface && $surface->{hwnd} ) {
            if ( my $mrec = $registry->{$surface_id}{menu_bar} ) {
                for my $cmd ( keys %{ $mrec->{by_cmd} } ) {
                    delete $menu_cmds->{$cmd};
                }
                DestroyMenu( $mrec->{hmenu} ) if $mrec->{hmenu};
            }
        }
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

    # True when the window node carries any min/max size constraint, so maximization can be
    # refused (a fullscreen window ignores track-size clamps).
    method _has_size_constraints ($node) {
        return $node->can('min_w') && ( $node->min_w || $node->min_h || $node->max_w || $node->max_h );
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
            $ti->{lpszText} = $self->_nz($text);
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
        $text = $self->_nz( $text // '' );
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

            # Dispatching a message re-enters Affix's XS wndproc bridge, which every so often
            # invokes its internal Perl trampoline with an undef argument and trips the
            # 'uninitialized' check under -w. The driver's window procs themselves never receive
            # that undef (all four callback arguments are defined); it is an Affix marshaling
            # quirk, so the spurious warning is scoped out for the dispatch alone.
            no warnings 'uninitialized';
            DispatchMessageW($msg_ptr);
        }
        free($msg_ptr);
        $self->_repaint_active_spin_arrows;
        $self->_sync_column_orders;
    }

    method _mount_node ( $vnode, $parent_hwnd ) {
        my ( $class, $style, $initial_text );
        if ( $vnode->type eq 'button' ) {
            $class        = 'BUTTON';
            $style        = 0x54000000;            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | BS_PUSHBUTTON
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text' || $vnode->type eq 'status_text' ) {
            $class = 'STATIC';
            $style = 0x54000000;                                                                          # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS
            $style |= $vnode->align eq 'center' ? 0x0001 : $vnode->align eq 'right' ? 0x0002 : 0x0000;    # SS_CENTER / SS_RIGHT / SS_LEFT
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text_input' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_BORDER | ES_AUTOHSCROLL for single-line (0x54800080);
            # multiline adds WS_VSCROLL | WS_TABSTOP | ES_MULTILINE (0x0004) | ES_AUTOVSCROLL
            # (0x0040) and drops ES_AUTOHSCROLL (0x54A10044).
            $style        = 0x54800080;
            $style        = 0x54A10044 if $vnode->multiline;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'multiline_text' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_BORDER | WS_VSCROLL | WS_TABSTOP | ES_MULTILINE |
            # ES_AUTOVSCROLL. WS_TABSTOP so Tab moves focus, not inserts '\t'.
            $style        = 0x54A10044;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'password' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_BORDER | ES_PASSWORD | ES_AUTOHSCROLL
            $style        = 0x548000A0;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'slider' ) {
            $class = 'msctls_trackbar32';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | TBS_AUTOTICKS (0x1) | TBS_HORZ (0x0) or TBS_VERT (0x80)
            $style = 0x54000001 | ( $vnode->orientation eq 'vertical' ? 0x0080 : 0x0000 );
        }
        elsif ( $vnode->type eq 'spin_box' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_BORDER | WS_TABSTOP | ES_READONLY (0x0800) | ES_AUTOHSCROLL.
            # Read-only: the driver owns the text (_spin_sync_text on mount / set_prop / WM_VSCROLL).
            $style        = 0x54800880;
            $initial_text = '' . ( $vnode->value // 0 );
        }
        elsif ( $vnode->type eq 'progress_bar' ) {
            $class = 'msctls_progress32';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | PBS_SMOOTH (0x1)
            $style = 0x54000001;
        }
        elsif ( $vnode->type eq 'toggle_switch' || $vnode->type eq 'toggle_button' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | BS_AUTOCHECKBOX (0x3  toggles itself on click) | BS_PUSHLIKE (0x1000  pushed-in look)
            $style        = 0x54001003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'link_button' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | BS_PUSHBUTTON | BS_FLAT (0x8000  edge-less "link" look,
            # still a real click target that posts BN_CLICKED)
            $style        = 0x54008000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'checkbox' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | BS_AUTOCHECKBOX (0x3  the auto variety:
            # the button toggles itself on click; BS_CHECKBOX (0x2) never does).
            $style        = 0x54000003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'radio' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | BS_AUTORADIOBUTTON (0x9  auto: clicking one
            # checks it and clears the group; BS_RADIOBUTTON (0x4) never does).
            # (+ WS_GROUP on the first of a group)
            $style        = $vnode->first ? 0x54020009 : 0x54000009;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'combo_box' ) {
            $class = 'COMBOBOX';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_VSCROLL | WS_TABSTOP | CBS_HASSTRINGS (0x200  the
            # control copies the strings we add, so items render/text-read back correctly)
            # plus CBS_DROPDOWNLIST (0x3) or CBS_DROPDOWN (0x2) for the editable variety.
            # The window height (laid out) becomes field height + dropped list extent.
            $style = 0x54210200 | ( $vnode->editable ? 0x0002 : 0x0003 );
        }
        elsif ( $vnode->type eq 'list_box' ) {
            $class = 'LISTBOX';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_BORDER | WS_VSCROLL | WS_TABSTOP
            # | LBS_NOTIFY (0x1  post WM_COMMAND on change)
            # | LBS_NOINTEGRALHEIGHT (0x100  exact height)
            # | LBS_HASSTRINGS (0x40  store/copy + render the added strings properly)
            # | LBS_MULTIPLESEL (0x8  toggle multi-selection when requested)
            $style = 0x54A10141 | ( $vnode->multiple ? 0x0008 : 0 );
        }
        elsif ( $vnode->type eq 'status_bar' ) {
            $class = 'msctls_statusbar32';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | SBARS_SIZEGRIP (0x100: the grip triangle in the corner)
            $style = 0x54000100;
        }
        elsif ( $vnode->type eq 'group_box' ) {
            $class = 'BUTTON';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | BS_GROUPBOX (0x7: etched frame + title, no click feedback).
            # NOTE Win32 groupboxes cannot usefully parent child controls (the BS_GROUPBOX
            # wndproc swallows WM_COMMAND/Notify from grandchildren), so children mount as
            # siblings of the app window in the title-relative inner rect.
            $style        = 0x54000007;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'tree_view' ) {
            $class = 'SysTreeView32';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_TABSTOP (0x54010000)
            # | TVS_HASBUTTONS (0x1  +/- expand triangles)
            # | TVS_LINESATROOT (0x2  connectors from the first level)
            # | TVS_HASLINES (0x4  parent-child connector lines)
            # | TVS_DISABLEDRAGDROP (0x10  no drag-drop of items)
            # | TVS_SHOWSELALWAYS (0x20  keep the highlight when the tree loses focus)
            $style = 0x54010037;
        }
        elsif ( $vnode->type eq 'list_view' ) {
            $class = 'SysListView32';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_TABSTOP (0x54010000)
            # | WS_HSCROLL (0x100000) | WS_VSCROLL (0x200000) for overflowing columns/rows
            # | LVS_REPORT (0x1  columnar row view; the multi-column "table" mode)
            # | LVS_SHOWSELALWAYS (0x8  keep the highlight when the list loses focus)
            # | LVS_SINGLESEL (0x4  restrict to one selection UNLESS multiple; the control is
            #    multi-select by default) | LVS_NOCOLUMNHEADER (0x4000  when header is disabled)
            $style = 0x54310001 | 0x0008 | ( $vnode->multiple ? 0 : 0x0004 ) | ( $vnode->header ? 0 : 0x4000 );
        }
        elsif ( $vnode->type eq 'toolbar' ) {
            $class = 'ToolbarWindow32';

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS (0x54000000)
            # | CCS_TOP (0x1  toolbar hugs the top edge of its parent)
            # | TBSTYLE_FLAT (0x800  flat look, no raised edges)
            # | TBSTYLE_LIST (0x1000  text sits beside the (absent) icon; text-only buttons render correctly)
            $style = 0x54001801;
        }
        elsif ( $vnode->type eq 'scroll_view' ) {
            $class = $viewport_class;

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN (0x02000000: content children are clipped
            # to the viewport client area, giving the scrolled region its window).
            $style = 0x56000000;
        }
        elsif ( $vnode->type eq 'tab_panel' ) {
            my $hw = CreateWindowExW(
                0, 'SysTabControl32', undef,

                # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_TABSTOP (0x54010000)
                0x54010000, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef, undef
            );
            $registry->{ $vnode->id } = { hwnd => $hw, node => $vnode, parent_hwnd => $parent_hwnd, surface => 'main', index => $vnode->index // 0, };
            $self->_populate_tabs( $vnode->id );

            # Panel CONTENTS mount as SIBLINGS of the host window (group-box style), laid out into
            # the same body rect; the native tab control only draws the strip. Only the active
            # panel's subtree is shown.
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };

            # Push the tab strip below all panel content children immediately after creation;
            # comctl32 raises the tab during TCM_SETCURSEL / repaint, so this must precede the
            # selection message and _apply_tab.
            SetWindowPos( $hw, cast( 1, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );    # HWND_BOTTOM, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            SendMessageW( $hw, 0x130C, $registry->{ $vnode->id }{index}, 0 );      # TCM_SETCURSEL
            $self->_apply_tab( $vnode->id );
            return;
        }
        elsif ( $vnode->type eq 'split_view' ) {

            # No native window of its own: the two panes mount as SIBLINGS of the app window
            # (group-box style, so their notifications route to the app wndproc), and the
            # draggable divider strip is created lazily on the first move_widget (like the
            # scroll_view's native scrollbars). A registry record is still needed so set_prop /
            # move_widget can route divider/divider-drag handling.
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
            $registry->{ $vnode->id }
                = { hwnd => undef, node => $vnode, parent_hwnd => $parent_hwnd, surface => 'main', orientation => $vnode->orientation, };
            return;
        }
        else {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };

            # Containers have no HWND but radio_group needs a registry entry so set_prop('value')
            # can route the selection to its radio children.
            $registry->{ $vnode->id } = { hwnd => undef, node => $vnode, surface => 'main' } if $vnode->type eq 'radio_group';
            return;
        }
        my $hwnd = CreateWindowExW( 0, $class, $self->_nz($initial_text),
            $style, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id, undef, undef );
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
            SendMessageW( $hwnd, 0x00CC, CORE::ord( $self->_nz( $vnode->password_char ) ), 0 );             # EM_SETPASSWORDCHAR
        }
        if ( $vnode->type eq 'combo_box' || $vnode->type eq 'list_box' ) {
            $self->_populate_strings( $hwnd, $vnode );
        }

        # Tree view: the items live in $vnode->nodes (recursive hashrefs), not VDOM children.
        # A per-record slot table maps each inserted item's HTREEITEM -> lParam slot so live
        # selection notifications can be routed back to the model value.
        if ( $vnode->type eq 'tree_view' ) {
            $registry->{ $vnode->id }{tree} = { slots => [], by_value => {}, by_hitem => {} };
            $self->_populate_tree( $vnode->id );
        }

        # Toolbar: TB_BUTTONSTRUCTSIZE is required before any TB_ADDBUTTONSW, then per-button
        # TBBUTTON records. Command ids come from a driver-wide allocator (0x4000+) so the
        # WM_COMMAND routing table stays unambiguous; each button's label is added via TB_ADDSTRING.
        if ( $vnode->type eq 'toolbar' ) {
            $registry->{ $vnode->id }{toolbar} = { by_cmd => {} };
            SendMessageW( $hwnd, 0x041E, 32, 0 );    # TB_BUTTONSTRUCTSIZE
            $self->_populate_toolbar( $vnode->id );
        }

        # List view: set the extended styles, then insert the columns and rows. The record keeps a
        # slot table (row index -> { value }) built during populate so LVN_ITEMCHANGED's iItem can
        # be mapped straight back to the model value (the same trick as the tree's slot table).
        if ( $vnode->type eq 'list_view' ) {
            my $ex = 0x00010000;    # LVS_EX_DOUBLEBUFFER: flicker-free repaints
            $ex |= 0x00000020 if $vnode->full_row_select;    # LVS_EX_FULLROWSELECT
            $ex |= 0x00000001 if $vnode->grid_lines;         # LVS_EX_GRIDLINES
            $ex |= 0x00000010 if $vnode->reorderable;        # LVS_EX_HEADERDRAGDROP: drag header items to reorder columns
            SendMessageW( $hwnd, 0x1036, 0, $ex );           # LVM_SETEXTENDEDLISTVIEWSTYLE
            $registry->{ $vnode->id }{listview} = { slots => [], ncols => 0 };
            $self->_populate_listview( $vnode->id );
        }

        # Status bar: parts + per-pane text are pushed via SB_SETPARTS / SB_SETTEXT (the control
        # copies the buffers, so they can be freed immediately).
        if ( $vnode->type eq 'status_bar' ) {
            $self->_populate_statusbar( $hwnd, $vnode );
        }

        # Group box: content children are SIBLINGS of the app window (see the mount comment about
        # BS_GROUPBOX swallowing grandchildren notifications), positioned in the title-relative
        # inner rect computed by Layout.
        if ( $vnode->type eq 'group_box' ) {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
        }

        # Scroll view: create the shared scroll store, then mount the content subtree INTO the
        # viewport window. Every created content record is tagged with the same store so
        # move_widget/scrollbar events can offset it relative to the viewport.
        if ( $vnode->type eq 'scroll_view' ) {
            my $rec = $registry->{ $vnode->id };
            $rec->{scroll}     = { ox => 0, oy => 0, base_x => $vnode->bx, base_y => $vnode->by, };
            $rec->{scroll}{ox} = $vnode->scroll_x if defined $vnode->scroll_x;
            $rec->{scroll}{oy} = $vnode->scroll_y if defined $vnode->scroll_y;
            for my $kid ( @{ $vnode->children } ) {
                $self->_mount_node( $kid, $hwnd );
                $self->_mark_scrolled( $kid, $rec->{scroll} );
            }
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
        my $wide = Encode::encode( 'UTF-16LE', $self->_nz($text) );
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

            # WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | UDS_ARROWKEYS (0x20)
            0x54000020, $vnode->bx + $edit_bw, $vnode->by, $cxv, $vnode->bh, $parent_hwnd, 0, undef, undef
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
            my $text = $self->_nz( '' . ( $opt->{label} // $opt->{value} // '' ) );
            my $wide = Encode::encode( 'UTF-16LE', $text );                           # appends a NUL terminator
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
            SetWindowTextW( $main_hwnd, $self->_nz($value) );
        }
        elsif ( $prop_name eq 'topmost' ) {    # window: toggle always-on-top
            SetWindowPos( $record->{hwnd}, $value ? -1 : -2, 0, 0, 0, 0, 0x0013 );
        }
        elsif ( $prop_name eq 'minimized' || $prop_name eq 'maximized' ) {    # window state
            if ($value) {

                # A fullscreen maximize bypasses WM_GETMINMAXINFO track clamps, so refuse it
                # whenever any min/max constraint is defined (mirrors the mount guard).
                if ( $prop_name eq 'maximized' && $self->_has_size_constraints( $record->{node} ) ) {
                    return;
                }
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
            if ( $record->{node}->type eq 'status_bar' ) {

                # SetWindowTextW on a statusbar doesn't set panes; route through SB_SETTEXT.
                $self->_populate_statusbar( $record->{hwnd}, $record->{node}, [$value] );
                return;
            }
            SetWindowTextW( $record->{hwnd}, $self->_nz($value) );
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'panels' && $record->{node}->type eq 'status_bar' ) {    # status_bar: SB_SETPARTS + per-pane SB_SETTEXT
            $self->_populate_statusbar( $record->{hwnd}, $record->{node}, $value );
        }
        elsif ( $prop_name eq 'scroll_x' || $prop_name eq 'scroll_y' ) {               # scroll_view
            return unless $record->{node}->type eq 'scroll_view';
            return unless $record->{scroll};
            $record->{scroll}{ $prop_name eq 'scroll_x' ? 'ox' : 'oy' } = $value;
            $self->_apply_scroll($vnode_id);
        }
        elsif ( $prop_name eq 'divider' || $prop_name eq 'orientation' ) {             # split_view
            return unless $record->{node}->type eq 'split_view';
            $record->{orientation} = $value if $prop_name eq 'orientation' && defined $value;
            $record->{divider}     = $value if $prop_name eq 'divider'     && defined $value;
            $self->_place_divider($vnode_id);
        }
        elsif ( $prop_name eq 'index' ) {                                              # tab_panel
            return unless $record->{node}->type eq 'tab_panel';
            $record->{index} = $value if defined $value;
            if ( $record->{hwnd} ) {
                my $cur = SendMessageW( $record->{hwnd}, 0x130B, 0, 0 );                                     # TCM_GETCURSEL
                SendMessageW( $record->{hwnd}, 0x130C, $record->{index}, 0 ) if $cur != $record->{index};    # TCM_SETCURSEL
            }
            $self->_apply_tab($vnode_id);
        }
        elsif ( $prop_name eq 'panels' && $record->{node}->type eq 'tab_panel' ) {                           # tab_panel
            $self->_populate_tabs($vnode_id);
            $self->_apply_tab($vnode_id);
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
            if ( $record->{node}->type eq 'tree_view' ) {
                return $self->_select_tree_value( $vnode_id, $value );
            }
            if ( $record->{node}->type eq 'list_view' ) {
                return $self->_select_listvalue( $vnode_id, $value );
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
                        SetWindowTextW( $record->{hwnd}, $self->_nz($value) );
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
                my $native = $self->_to_crlf( $self->_nz($value) );
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
        elsif ( $prop_name eq 'rows' || $prop_name eq 'columns' ) {    # list_view: rebuild the table + reselect
            return unless $record->{node}->type eq 'list_view';
            # 'rows' reuses the live columns (widths + drag order survive); 'columns' recreates them.
            $self->_populate_listview( $vnode_id, $prop_name eq 'rows' ? 1 : 0 );
        }
        elsif ( $prop_name eq 'nodes' || $prop_name eq 'expanded' ) {    # tree_view: rebuild the item tree + reselect
            return unless $record->{node}->type eq 'tree_view';
            $self->_populate_tree($vnode_id);
        }
        elsif ( $prop_name eq 'buttons' && $record->{node}->type eq 'toolbar' ) {    # toolbar: rebuild the button set
            $self->_populate_toolbar( $vnode_id, $value );
        }
        elsif ( $prop_name eq 'menu_bar' && $record->{node}->type eq 'window' ) {    # menu bar: rebuild the native menu
            $self->_mount_menu_bar($vnode_id);
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
        return unless $record;    # containers have no HWND

        # Scroll view: its viewport window is moved to the layout slot, the shared scroll store
        # is re-based to the new origin, scrollbars are grown/positioned, and every content leaf
        # is re-offset relative to the viewport. Content children are NOT moved by the caller's
        # own recursion (App::_move_all skips them) so offsets are applied exactly once.
        # Viewport sizing is delegated to _place_scrollbars so it can leave gutter space open
        # for the scrollbar controls (the viewport is shrunk by gutter_w/gutter_h).
        if ( $record->{node} && $record->{node}->type eq 'scroll_view' ) {
            my $st = $record->{scroll} ||= { ox => 0, oy => 0, base_x => $x, base_y => $y };
            $st->{base_x} = $x;
            $st->{base_y} = $y;
            $self->_place_scrollbars($vnode_id);
            $self->_apply_scroll($vnode_id);
            return;
        }

        # Split view: the split node has no HWND; laying it out just re-positions the divider
        # strip (the panes themselves are moved by App::_move_all's recursion through the node's
        # children, and content by their own move_widgets).
        if ( $record->{node} && $record->{node}->type eq 'split_view' ) {
            $self->_place_divider($vnode_id);
            return;
        }

        # Tab panel: keep SysTabControl32 at HWND_BOTTOM so sibling page controls stay on top.
        # The move repositions the tab strip; Z-order is enforced in _apply_tab.
        if ( $record->{node} && $record->{node}->type eq 'tab_panel' && $record->{hwnd} ) {
            SetWindowPos( $record->{hwnd}, cast( 1, Pointer [Void] ), $x, $y, $w, $h, 0x0010 );    # HWND_BOTTOM, SWP_NOACTIVATE
            return;
        }
        return unless $record->{hwnd};

        # Content of a scroll view: offset from the viewport origin minus the current scroll.
        my ( $mx, $my ) = ( 0, 0 );
        if ( my $st = $record->{scroll} ) {
            ( $mx, $my ) = ( -( $st->{base_x} + $st->{ox} ), -( $st->{base_y} + $st->{oy} ) );
        }
        SetWindowPos( $record->{hwnd}, undef, $x + $mx, $y + $my, $w, $h, 0x0004 );

        # Status bar: pane edges are proportional to the node width, so re-part on every resize
        # (SB_SETPARTS moves the edges; the per-pane texts are untouched).
        if ( $record->{node} && $record->{node}->type eq 'status_bar' ) {
            $self->_repart_statusbar( $record->{hwnd}, $record->{node}, $record->{parts} );
        }

        # A spin box's edit and its up/down buddy sit side by side (EDIT = w-cxv, buddy = right strip),
        # so each follows the move keeping that split.
        if ( $record->{node} && $record->{node}->type eq 'spin_box' && $record->{aux} ) {
            my $sw = GetSystemMetrics(2);    # SM_CXVSCROLL
            SetWindowPos( $record->{hwnd}, undef, $x + $mx,            $y + $my, $w - $sw, $h, 0x0004 );
            SetWindowPos( $record->{aux},  undef, $x + $mx + $w - $sw, $y + $my, $sw,      $h, 0x0004 );
        }
    }

    # Index the registry for the record whose aux-flag holds $hwnd (used by WM_HSCROLL/WM_VSCROLL
    # to map a generic scrollbar control back to its scroll_view).
    method _registry_id_by_key ( $hwnd, $key ) {
        for my $id ( keys %{$registry} ) {
            my $rec = $registry->{$id};
            next unless $rec && $rec->{$key};
            return $id if $rec->{$key} == $hwnd;
        }
        return undef;
    }

    method _create_scrollbar ( $parent, $vertical ) {
        return CreateWindowExW( 0, 'SCROLLBAR', undef, 0x54000000 | ( $vertical ? 0x0001 : 0x0000 ), 0, 0, 0, 0, $parent, 0, undef, undef );
    }

    # SBM_* window messages are unreliable for the control on modern Windows, so the driver
    # talks position/range through SetScrollInfo/GetScrollInfo (SB_CTL = 2). The SIF_PAGE
    # (viewport extent for the axis) is required for the control to render a grabbable thumb
    # sized to the visible region; without it the thumb is left at its minimum and effectively
    # ungrabbable, and clicking anywhere lands on the track (SB_PAGEDOWN). In the control's
    # track-styled coordinate system nMax must be the full content extent (max + page - 1) so a
    # thumb position range of [0 .. max] scroll offsets remains reachable.
    method _scrollbar_range_pos ( $hwnd, $max, $pos, $page ) {
        my $sysmax = $page ? $max + $page - 1 : $max;
        my $s      = malloc(28);                        # SCROLLINFO is 28 bytes: cbSize fMask nMin nMax nPage nPos nTrackPos
        memcpy( $s, pack( 'l<7', 28, 0x0001 | 0x0002 | 0x0004, 0, $sysmax, $page // 0, $pos, 0 ), 28 );    # SIF_RANGE|SIF_PAGE|SIF_POS
        my $ret = SetScrollInfo( $hwnd, 2, $s, 1 );
        free($s);
        return $ret;
    }

    method _scrollbar_read_pos ($hwnd) {
        my $s = malloc(28);
        memcpy( $s, pack( 'l<7', 28, 0x0004, 0, 0, 0, 0, 0 ), 28 );                                        # SIF_POS
        GetScrollInfo( $hwnd, 2, $s );
        my ( undef, undef, undef, undef, undef, $pos ) = unpack 'l<7', Affix::raw( $s, 28 );
        free($s);
        return $pos;
    }

    # The thumb's position mid-drag, read from SCROLLINFO's SIF_TRACKPOS (the nPos updated live as
    # the thumb moves). Unlike the 16-bit value packed into WM_HSCROLL/VSCROLL's wParam, this is a
    # full 32-bit track position, so it is correct even when the content range exceeds 65535 px.
    method _scrollbar_track_pos ($hwnd) {
        my $s = malloc(28);
        memcpy( $s, pack( 'l<7', 28, 0x0010, 0, 0, 0, 0, 0 ), 28 );    # SIF_TRACKPOS (0x0010)
        GetScrollInfo( $hwnd, 2, $s );
        my ( undef, undef, undef, undef, undef, undef, $trackpos ) = unpack 'l<7', Affix::raw( $s, 28 );
        free($s);
        return $trackpos;
    }

    # Grow the scroll_view's scrollbars to the current viewport and set their ranges from the
    # content size. Destroys bars for axes that no longer overflow; stores ranges for clamping.
    # The viewport window is SIZED to leave the scrollbar gutters open (bars sit in the gutter
    # strips, never under the opaque viewport), and bars are raised to HWND_TOP: Win32 child
    # windows default to the BOTTOM of the sibling z-order, so without an explicit raise any
    # viewport/control would paint over a bar that shares its strip.
    method _place_scrollbars ($id) {
        my $rec  = $registry->{$id} or return;
        my $node = $rec->{node}     or return;
        my $st   = $rec->{scroll}   or return;
        my $sbw  = GetSystemMetrics(2);    # SM_CXVSCROLL
        my $sbh  = GetSystemMetrics(4);    # SM_CYHSCROLL
        my $vh   = $node->bh;
        my $vW   = $node->bw;
        my ( $cw, $ch ) = ( 0, 0 );
        my $kids = $node->children;

        if (@$kids) {
            $cw = $kids->[0]->bw || 0;
            $ch = $kids->[0]->bh || 0;
        }
        my $vert   = $node->orientation ne 'horizontal';
        my $horz   = $node->orientation ne 'vertical';
        my $want_v = $vert && $ch > $vh;
        my $want_h = $horz && $cw > $vW;
        my $gut_w  = $want_v ? $sbw : 0;
        my $gut_h  = $want_h ? $sbh : 0;

        # Cross-overflow correction: the OTHER axis' gutter shrinks the visible viewport, which can
        # itself push the content past it (a vertical bar eating sbw of width can make the content
        # wider than the shrunken view). In that case the secondary bar appears too.
        if ( $want_v && !$want_h && $horz && $cw > ( $vW - $gut_w ) ) {
            $want_h = 1;
            $gut_h  = $sbh;
        }
        elsif ( $want_h && !$want_v && $vert && $ch > ( $vh - $gut_h ) ) {
            $want_v = 1;
            $gut_w  = $sbw;
        }
        my $view_w = $vW - $gut_w;
        my $view_h = $vh - $gut_h;
        $view_w = 0 if $view_w < 0;
        $view_h = 0 if $view_h < 0;

        # Size the viewport window so it leaves the gutter open for the scrollbars.
        if ( $rec->{hwnd} ) {
            SetWindowPos( $rec->{hwnd}, undef, $node->bx, $node->by, $view_w, $view_h, 0x0004 );
        }
        my $range_h = $want_h ? $cw - $view_w : 0;
        my $range_v = $want_v ? $ch - $view_h : 0;
        $rec->{range_h} = $range_h;
        $rec->{range_v} = $range_v;
        $rec->{page_h}  = $want_h ? $view_w : 0;
        $rec->{page_v}  = $want_v ? $view_h : 0;
        if ($want_h) {
            $rec->{aux_h} ||= $self->_create_scrollbar( $rec->{parent_hwnd}, 0 );
            SetWindowPos( $rec->{aux_h}, cast( 0, Pointer [Void] ), $node->bx, $node->by + $view_h, $view_w, $sbh, 0x0010 )
                ;    # HWND_TOP, SWP_NOACTIVATE
            ShowWindow( $rec->{aux_h}, 5 );
            $self->_scrollbar_range_pos( $rec->{aux_h}, $range_h, $st->{ox}, $rec->{page_h} );
        }
        elsif ( $rec->{aux_h} ) {
            DestroyWindow( $rec->{aux_h} );
            delete $rec->{aux_h};
            $st->{ox} = 0;
        }
        if ($want_v) {
            $rec->{aux_v} ||= $self->_create_scrollbar( $rec->{parent_hwnd}, 1 );
            SetWindowPos( $rec->{aux_v}, cast( 0, Pointer [Void] ), $node->bx + $view_w, $node->by, $sbw, $view_h, 0x0010 )
                ;    # HWND_TOP, SWP_NOACTIVATE
            ShowWindow( $rec->{aux_v}, 5 );
            $self->_scrollbar_range_pos( $rec->{aux_v}, $range_v, $st->{oy}, $rec->{page_v} );
        }
        elsif ( $rec->{aux_v} ) {
            DestroyWindow( $rec->{aux_v} );
            delete $rec->{aux_v};
            $st->{oy} = 0;
        }
    }

    # Move every content leaf (any record sharing this scroll_view's store) to its layout slot,
    # rebased to the viewport origin minus the scroll offsets. Also refs thumb + clamps offsets.
    # Children are real windows, so moving them with SetWindowPos leaves the just-vacated strip of
    # the viewport painting stale pixels (the "clipping" that lingers after a wheel/drag scroll):
    # an erase + repaint of the viewport background and the children themselves is forced after
    # every move so freshly exposed regions paint immediately.
    method _apply_scroll ($id) {
        my $rec = $registry->{$id} or return;
        my $st  = $rec->{scroll}   or return;
        $st->{ox} = 0               if $st->{ox} < 0;
        $st->{oy} = 0               if $st->{oy} < 0;
        $st->{ox} = $rec->{range_h} if defined $rec->{range_h} && $st->{ox} > $rec->{range_h};
        $st->{oy} = $rec->{range_v} if defined $rec->{range_v} && $st->{oy} > $rec->{range_v};
        $self->_scrollbar_range_pos( $rec->{aux_h}, $rec->{range_h}, $st->{ox}, $rec->{page_h} ) if $rec->{aux_h};
        $self->_scrollbar_range_pos( $rec->{aux_v}, $rec->{range_v}, $st->{oy}, $rec->{page_v} ) if $rec->{aux_v};

        for my $rid ( keys %$registry ) {
            my $r = $registry->{$rid} or next;
            next if $r == $rec;    # the viewport itself is NOT scrollable content
            next unless $r->{scroll} && $r->{scroll} == $st && $r->{hwnd} && $r->{node};
            SetWindowPos(
                $r->{hwnd}, undef,
                $r->{node}->bx - $st->{base_x} - $st->{ox},
                $r->{node}->by - $st->{base_y} - $st->{oy},
                $r->{node}->bw, $r->{node}->bh, 0x0004
            );
            InvalidateRect( $r->{hwnd}, undef, 1 );    # repaint each scrolled child so stale pixels don't linger
        }
        InvalidateRect( $rec->{hwnd}, undef, 1 );
        UpdateWindow( $rec->{hwnd} );
    }

    # WM_HSCROLL / WM_VSCROLL for a scroll_view's native scrollbar: compute the next offset from
    # the scroll code, apply it, and dispatch on_scroll (y, x).
    method _scrollbar_event ( $id, $axis, $wparam ) {
        my $rec  = $registry->{$id}    or return;
        my $st   = $rec->{scroll}      or return;
        my $sb   = $rec->{"aux_$axis"} or return;
        my $key  = $axis eq 'h' ? 'ox' : 'oy';
        my $code = $wparam & 0xFFFF;
        my $pos  = $st->{$key};
        my $pg   = 8 * 16;
        $pos -= 16  if $code == 0;    # SB_LINEUP
        $pos += 16  if $code == 1;    # SB_LINEDOWN
        $pos -= $pg if $code == 2;    # SB_PAGEUP
        $pos += $pg if $code == 3;    # SB_PAGEDOWN

        if ( $code == 5 ) {           # SB_THUMBTRACK: live drag

            # SIF_TRACKPOS holds the 32-bit track position during a REAL drag
            # (reliable beyond 16-bit ranges). A synthetic SendMessage (tests / API
            # callers) never sets nTrackPos, so fall back to the 16-bit wParam value.
            my $tp = $self->_scrollbar_track_pos($sb);
            $pos = $tp || ( ( $wparam >> 16 ) & 0xFFFF );
        }
        elsif ( $code == 4 ) {    # SB_THUMBPOSITION: drag released
            $pos = ( $wparam >> 16 ) & 0xFFFF;
        }
        $st->{$key} = $pos;
        $self->_apply_scroll($id);
        my $node = $rec->{node};
        if ( $node && $node->can('on_scroll') && $node->on_scroll ) {
            my $action = $node->on_scroll->( $st->{ox}, $st->{oy} );
            $self->channel->put($action) if $action;
        }
    }

    # Resolve the scroll_view to wheel-scroll: the deepest window under the cursor (which may be
    # the viewport itself, a content control inside it, or the native scrollbar control), climbing
    # through parents to find a viewport/scrollbar the driver owns. Returns the scroll_view's
    # registry id or undef. The wheel's lParam holds the cursor's screen coordinates, so no global
    # cursor read is needed; instead of a foreign-window hit test (WindowFromPoint can pick a
    # browser over the app), every registered scroll_view's own viewport/scrollbar rects are
    # checked against the point. A viewport or scrollbar whose rect contains the point wins;
    # deeper (smaller-area) targets beat shallower ones, and an overlay on the requested axis'
    # scrollbar outranks a bare viewport hover.
    method _wheel_target ( $axis, $lparam ) {
        my $px = $lparam & 0xFFFF;
        my $py = ( $lparam >> 16 ) & 0xFFFF;
        my ( $hit, $hit_area, $hit_keyed ) = ( undef, 1 << 30, 0 );
        my $wrect = malloc( sizeof( RECT() ) );
        for my $id ( keys %{$registry} ) {
            my $rec = $registry->{$id};
            next unless $rec && $rec->{node} && $rec->{node}->type eq 'scroll_view' && $rec->{hwnd};
            GetWindowRect( $rec->{hwnd}, $wrect );
            my $r = cast( $wrect, RECT() );    # NB: Affix cast is LAZY - re-reads $wrect on each access,

            # so the viewport-derived values MUST be read before the loop overwrites it
            my $in_view = $px >= $r->{left} && $px <= $r->{right} && $py >= $r->{top} && $py <= $r->{bottom};
            my $area    = ( $r->{right} - $r->{left} ) * ( $r->{bottom} - $r->{top} );
            my $keyed   = 0;
            for my $ax (qw(v h)) {
                next unless $rec->{"aux_$ax"};
                GetWindowRect( $rec->{"aux_$ax"}, $wrect );
                my $r2  = cast( $wrect, RECT() );
                my $inr = $px >= $r2->{left} && $px <= $r2->{right} && $py >= $r2->{top} && $py <= $r2->{bottom};
                $keyed = 1 if $inr;                    # hovering any scrollbar outranks a bare viewport hover
                $keyed = 2 if $inr && $ax eq $axis;    # the requested-axis scrollbar is the best target
            }

            # The point must be over the viewport or one of its scrollbars (the bars live OUTSIDE the
            # viewport rect in the open gutters, so the viewport containment test alone would reject a
            # wheel aimed at the scrollbar strip).
            next unless $in_view || $keyed;
            next if $hit && $keyed < $hit_keyed;
            next if $hit && $keyed == $hit_keyed && $area >= $hit_area;
            ( $hit, $hit_area, $hit_keyed ) = ( $id, $area, $keyed );
        }
        free($wrect);
        return $hit;
    }

    # Status bar parts: SB_SETPARTS with proportional part edges from the node width (the control
    # ignores the widths and splits the edges evenly). $n overrides the pane count for transient
    # texts (set_prop 'panels'); otherwise it is the node's pane count (or a single default pane).
    # Called at mount, on set_prop, AND on every move_widget so the panes track a window resize
    # immediately (re-parting only moves the edges; the per-pane texts are untouched).
    # Resolve a split_view's divider position along its main axis, shared by Layout (pane rects) and
    # the driver's first placement. Returns (divider, vertical?, width). This is NODE-driven (the
    # model's divider / orientation / min/max); it does NOT reflect the live drag state -- the drag
    # pos lives in the registry record and Layout folds it back in once on_divider updates the model.
    # When the track size changes (e.g. window resize) the stored ratio is applied so the divider
    # keeps its relative position rather than drifting.
    method split_position ( $node, $w = undef, $h = undef ) {
        $w //= $node->bw;
        $h //= $node->bh;
        my $vert  = $node->orientation eq 'vertical';
        my $dw    = defined $node->divider_w ? $node->divider_w : 6;
        my $avail = $vert                    ? $h               : $w;
        my $track = $avail - $dw;
        my $div;
        my $rec = $node->id && $registry->{ $node->id };

        if ( $rec && defined $rec->{div_track} && $rec->{div_track} > 0 && defined $rec->{div_ratio} && $track != $rec->{div_track} ) {
            $div = int( $rec->{div_ratio} * $track + 0.5 );
        }
        elsif ( defined $node->divider ) {
            $div = $node->divider;
        }
        else {
            $div = int( $track / 2 );
        }
        $div = $self->_clamp_divider( $node, $div, $vert, $dw, $avail );
        if ( $track > 0 && $rec ) {
            $rec->{div_track} = $track;
            $rec->{div_ratio} = $div / $track;
            $rec->{divider}   = $div;
        }
        return ( $div, $vert, $dw );
    }

    # Clamp a divider position so pane A holds >= min_a and pane B holds >= min_b along the main
    # axis. Shared by split_position, the drag handler and _place_divider (which guards against
    # stale HUGE values from an un-laid-out node: avail 0 -> max < min_a -> degenerate -> min_a).
    method _clamp_divider ( $node, $div, $vert, $dw, $avail ) {
        my $min_a = defined $node->min_a ? $node->min_a : 40;
        my $min_b = defined $node->min_b ? $node->min_b : 40;
        $div = $min_a if $div < $min_a;
        my $max = $avail - $dw - $min_b;
        $div = $max   if $div > $max;
        $div = $min_a if $div > $max;    # degenerate: the split is too small for the mins
        return $div;
    }

    # Position (lazily creating) the split_view's divider strip. The strip tracks the LIVE divider
    # ($rec->{divider}, maintained by the drag and set_prop), only resolving the node's initial
    # position on the first call. Orientation comes from the record too, because set_prop swaps it
    # before the mount-time node's reader is current.
    method _place_divider ($id) {
        my $rec   = $registry->{$id} or return;
        my $node  = $rec->{node}     or return;
        my $vert  = ( $rec->{orientation} // $node->orientation // 'vertical' ) eq 'vertical';
        my $dw    = defined $node->divider_w ? $node->divider_w   : 6;
        my $avail = $vert                    ? ( $node->bh // 0 ) : ( $node->bw // 0 );
        my $track = $avail - $dw;
        my $div   = $rec->{divider};
        if ( !defined $div ) {
            ( $div, undef, undef ) = $self->split_position($node);
            $rec->{divider} = $div;
        }
        else {
            $div = $self->_clamp_divider( $node, $div, $vert, $dw, $avail );
            $rec->{divider} = $div;
        }
        if ( $track > 0 ) {
            $rec->{div_track} = $track;
            $rec->{div_ratio} = $div / $track;
        }
        $rec->{aux} ||= CreateWindowExW( 0, $divider_class, undef, 0x54000000, 0, 0, $dw, $dw, $rec->{parent_hwnd}, 0, undef, undef );
        my $hw = $rec->{aux};
        return unless $hw;
        if ($vert) {
            SetWindowPos( $hw, undef, $node->bx // 0, ( $node->by // 0 ) + $div, $node->bw // 0, $dw, 0x0004 );
        }
        else {
            SetWindowPos( $hw, undef, ( $node->bx // 0 ) + $div, $node->by // 0, $dw, $node->bh // 0, 0x0004 );
        }
        ShowWindow( $hw, $node->visible ? 5 : 0 );
    }

    method _divider_begin ($hwnd) {
        if ( my $id = $self->_registry_id_by_key( $hwnd, 'aux' ) ) {
            $registry->{$id}{dragging} = 1;
        }
    }

    method _divider_end ($hwnd) {
        if ( my $id = $self->_registry_id_by_key( $hwnd, 'aux' ) ) {
            $registry->{$id}{dragging} = 0;
        }
    }

    method _divider_active ($hwnd) {
        my $id = $self->_registry_id_by_key( $hwnd, 'aux' ) or return 0;
        return $registry->{$id}{dragging} ? 1 : 0;
    }

    # The sizing cursor is chosen by the split's orientation: a horizontal split (side-by-side
    # panes) has a VERTICAL divider bar -> IDC_SIZEWE; a vertical split has a horizontal bar
    # -> IDC_SIZENS.
    method _divider_cursor ($hwnd) {
        my $id   = $self->_registry_id_by_key( $hwnd, 'aux' ) or return undef;
        my $node = $registry->{$id}{node}                     or return undef;
        return LoadCursorW( undef, ( $registry->{$id}{orientation} // $node->orientation // 'vertical' ) eq 'horizontal' ? 32644 : 32645 );
    }

    # Drive a split_view's divider drag from the segment's wndproc. The cursor's screen position is
    # converted into app-window client coords (so nested splits work), clamped to the pane min/max,
    # stored on the record, the strip re-positioned immediately, and on_divider dispatched for the
    # model to fold into the next render (which re-lays-out the panes through Layout).
    method _divider_drag ($div_hwnd) {
        my $id   = $self->_registry_id_by_key( $div_hwnd, 'aux' ) or return;
        my $rec  = $registry->{$id}                               or return;
        my $node = $rec->{node}                                   or return;
        my $pt   = malloc( sizeof( POINT() ) );
        GetCursorPos($pt);
        my $scr = cast( $pt, POINT() );
        my $cpy = malloc( sizeof( POINT() ) );
        memcpy( $cpy, pack( 'l<2', $scr->{x}, $scr->{y} ), 8 );
        free($pt);
        ScreenToClient( $rec->{parent_hwnd}, $cpy );
        my $cl   = cast( $cpy, POINT() );
        my $vert = ( $rec->{orientation} // $node->orientation // 'vertical' ) eq 'vertical';
        my $pos  = $vert ? $cl->{y} - ( $node->by // 0 ) : $cl->{x} - ( $node->bx // 0 );
        free($cpy);
        my $dw = defined $node->divider_w ? $node->divider_w : 6;
        $pos = $self->_clamp_divider( $node, $pos, $vert, $dw, $vert ? ( $node->bh // 0 ) : ( $node->bw // 0 ) );
        $rec->{divider} = $pos;
        $self->_place_divider($id);

        if ( $node->can('on_divider') && $node->on_divider ) {
            my $action = $node->on_divider->($pos);
            $self->channel->put($action) if $action;
        }
    }

    method _repart_statusbar ( $hwnd, $vnode, $n = undef ) {
        return unless $hwnd;
        $n //= @{ $vnode->panels };
        $n = 1 unless $n;                                            # a bare label keeps the default single pane (no parts)
        $registry->{ $vnode->id }{parts} = $n;                       # remember the live count for later move_widget re-parts
        return if $n < 2;
        my $widths = pack 'V*', map { int( $vnode->bw * ( $_ + 1 ) / $n ) } 0 .. $n - 1;
        my $buf    = malloc( $n * 4 );
        memcpy( $buf, $widths, $n * 4 );
        SendMessageW( $hwnd, 0x0404, $n, &Affix::address($buf) );    # SB_SETPARTS
        free($buf);
    }

    # Status bar panes: parts (see _repart_statusbar), then the per-pane text via SB_SETTEXT
    # (both copy the buffers, so they free right after). The pane texts come from $texts when
    # given (set_prop 'panels'/'label'); otherwise from the node.
    method _populate_statusbar ( $hwnd, $vnode, $texts = undef ) {
        return unless $hwnd;
        my @texts = defined $texts ? @$texts : @{ $vnode->panels };
        @texts = ( $vnode->label ) unless @texts;
        $self->_repart_statusbar( $hwnd, $vnode, scalar @texts );
        for my $i ( 0 .. $#texts ) {
            my $wide = Encode::encode( 'UTF-16LE', $self->_nz( $texts[$i] ) ) . "\x00\x00";
            my $buf  = malloc( CORE::length($wide) );
            memcpy( $buf, $wide, CORE::length($wide) );
            SendMessageW( $hwnd, 0x040B, $i, &Affix::address($buf) );    # SB_SETTEXT (part i)
            free($buf);
        }
    }

    # Tab panel strip population: drop any existing tabs and insert one TCM_INSERTITEMW (TCIF_TEXT)
    # per panel. The TCITEMW pszText is marshalled by Affix from a _nz() string (TOOLINFO precedent:
    # the control copies the text during the call, so the pointed-to data does not need to outlive
    # the SendMessageW).
    method _populate_tabs ($id) {
        my $rec  = $registry->{$id} or return;
        my $hw   = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $cnt  = SendMessageW( $hw, 0x1304, 0, 0 );       # TCM_GETITEMCOUNT
        SendMessageW( $hw, 0x1308, 0, 0 ) for 1 .. $cnt;    # TCM_DELETEITEM (index 0 each time)
        my $tc = malloc( sizeof( TCITEMW() ) );
        my $tp = cast( $tc, TCITEMW() );
        $tp->{mask} = 0x0001;                               # TCIF_TEXT

        for my $i ( 0 .. $#{ $node->panels } ) {
            my $p     = $node->panels->[$i];
            my $title = ref $p eq 'HASH' ? ( $p->{title} // $p->{label} // '' ) : ( $p->[0] // '' );
            $tp->{pszText} = $self->_nz($title);
            SendMessageW( $hw, 0x1307, $i, Affix::address($tc) );    # TCM_INSERTITEMW
        }
        free($tc);
        if ( $rec->{index} > $#{ $node->panels } ) {
            $rec->{index} = 0;                                       # selection must stay in range after a shrink
        }
        SendMessageW( $hw, 0x130C, $rec->{index} // 0, 0 );          # TCM_SETCURSEL (repopulate resets the native selection)
    }

    # Tree view population: clear any existing items, then recursively insert top-level nodes and
    # their children via TVM_INSERTITEMW. Each item's lParam is a monotonically increasing SLOT
    # INDEX into $rec->{tree}{slots} (a row of { value, label, hitem }), so a TVN_SELCHANGED
    # notification can be mapped straight back to the model value. The TV_INSERTSTRUCTW is packed
    # by hand for the exact Win64 layout (no Affix struct padding ambiguity):
    #   hParent  (q<) at 0, hInsertAfter (q<) at 8, then TVITEMEXW:
    #   mask (L<) at 16, x4 pad, hItem (q<) at 24, state (L<) 32, stateMask (L<) 36,
    #   x4 pad, pszText (q<) at 48, cchTextMax (l<) 56, iImage (l<) 60, iSelectedImage (l<) 64,
    #   cChildren (l<) 68, lParam (q<) at 72 = 80 bytes total.
    # TVI_ROOT (0xFFFF0000) is the sentinel "top of the tree" parent; TVI_LAST (0xFFFF0002)
    # appends in model order. The item text is copied by the control during the insert call, so
    # the UTF-16 buffer is freed immediately after.
    method _populate_tree ($id) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $t    = $rec->{tree}     or return;
        $t->{slots}    = [];
        $t->{by_value} = {};
        $t->{by_hitem} = {};
        SendMessageW( $hwnd, 0x1101, 1, 0 );    # TVM_DELETEITEM(TVI_ROOT): drop the whole tree
        my %want_exp = map { $_ => 1 } @{ $node->expanded // [] };
        my $insert;
        $insert = sub {
            my ( $items, $parent_hitem ) = @_;
            for my $it ( @{ $items // [] } ) {
                my $kids  = $it->{children} ? 1 : 0;
                my $label = $it->{label} // $it->{value} // '';
                my $value = $it->{value} // $label;
                my $slot  = @{ $t->{slots} };
                push @{ $t->{slots} }, { value => $value, label => $label };
                $t->{by_value}{$value} = $slot;
                my $wide = Encode::encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00";
                my $abuf = malloc( CORE::length($wide) );
                memcpy( $abuf, $wide, CORE::length($wide) );
                my $bytes = pack 'q<q< L< x4 q< L< L< q< l< l< l< l< q<',
                    $parent_hitem // 0,              # hParent (0 = TVI_ROOT: top-level slots here; 0xFFFF0000 fails on this comctl32)
                    0xFFFF0002,                      # hInsertAfter (TVI_LAST: append in model order)
                    ( 0x0001 | 0x0004 | 0x0040 ),    # mask = TVIF_TEXT | TVIF_PARAM | TVIF_CHILDREN
                    0,                               # hItem (ignored on insert)
                    0,                               # state
                    0,                               # stateMask
                    Affix::address($abuf),           # pszText
                    0,                               # cchTextMax
                    0,                               # iImage
                    0,                               # iSelectedImage
                    $kids,                           # cChildren (drives the +/- button when there are children)
                    $slot;                           # lParam
                my $struct = malloc( length $bytes );
                memcpy( $struct, $bytes, length $bytes );
                my $hitem = SendMessageW( $hwnd, 0x1132, 0, Affix::address($struct) );    # TVM_INSERTITEMW
                free($struct);
                free($abuf);
                $t->{slots}[$slot]{hitem} = $hitem;
                $t->{by_hitem}{$hitem} = $slot;

                if ($kids) {
                    $insert->( $it->{children}, $hitem );
                    $self->_tree_expand_value( $hwnd, $hitem, $value, \%want_exp );
                }
            }
        };
        $insert->( $node->nodes, undef );

        # Repopulate resets the native selection; restore the model's.
        $self->_select_tree_value( $id, $node->value );
    }

    # TVM_EXPAND an item when its value appears in the model's `expanded` list. Collapsed by default.
    method _tree_expand_value ( $hwnd, $hitem, $value, $want_exp ) {
        return unless $want_exp->{$value};
        SendMessageW( $hwnd, 0x1102, 0x0002, $hitem );    # TVM_EXPAND(TVE_EXPAND)
    }

    # List view population: drop every column and row, then insert the model's columns (via
    # LVM_INSERTCOLUMNW 0x1061) and rows (LVM_INSERTITEMW 0x104D for column 0, LVM_SETITEMW
    # 0x104C for later cells). Rows are arrayrefs of cell strings or { value =>, columns => [...] }
    # hashrefs; a driver-side slot table maps each row index to its model value so LVN_ITEMCHANGED
    # can route straight back. The LVCOLUMNW (72 bytes) / LVITEMW (88 bytes) structs are packed by
    # hand with explicit alignment for the exact Win64 layout (mask/iItem/iSubItem at 0/4/8, state
    # at 12, stateMask at 16, pszText at 24, lParam at 40), and each UTF-16 text buffer is copied
    # by the control during the call, so it is freed immediately after.
    my $LVITEM = 'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4';    # 88 bytes on x64

    method _populate_listview ( $id, $reuse_columns = 0 ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $lv   = $rec->{listview} ||= { slots => [], ncols => 0 };

        # Repopulate resets the native selection; drop all rows. Columns are only re-inserted when
        # the definitions actually changed (set_prop('columns') or first mount): a rows-only reconcile
        # (set_prop('rows')) reuses the live columns so user-resized widths and any drag-reordered
        # column order survive a sort.
        SendMessageW( $hwnd, 0x1009, 0, 0 );                                       # LVM_DELETEALLITEMS
        $lv->{slots} = [];
        $reuse_columns = 0 if ( $lv->{ncols} // 0 ) != scalar @{ $node->columns // [] };
        if ( !$reuse_columns ) {
            my $old_n = $lv->{ncols} // 0;
            SendMessageW( $hwnd, 0x101C, 0, 0 ) while $old_n-- > 0;                # LVM_DELETECOLUMN(0)
            $lv->{ncols} = 0;
        }

        my $cols = $node->columns;
        $cols = [ { label => 'Items' } ] unless @$cols;                            # bare list safety net
        if ( !$reuse_columns ) {
            for my $i ( 0 .. $#$cols ) {
                my $sort  = $lv->{sort} && $lv->{sort}{col} == $i;
                my $label = $cols->[$i]{label} // '';
                $label .= $sort ? ( $lv->{sort}{dir} eq 'asc' ? ' ▲' : ' ▼' ) : '';    # sort indicator
                my $width = $cols->[$i]{width};
                if ( !$width ) {
                    my ($tw) = $self->measure_text($label);
                    $width = ( $tw + 24 ) < 60 ? 60 : $tw + 24;                    # glyph padding + cushion
                }
                my $fmt  = ( { left => 0, center => 2, right => 1 }->{ $cols->[$i]{align} // 'left' } // 0 );
                my $wide  = Encode::encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00";
                my $abuf  = malloc( CORE::length($wide) );
                memcpy( $abuf, $wide, CORE::length($wide) );
                my $bytes = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4',
                    0x000F,                       # mask = LVCF_FMT | LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM
                    $fmt,                         # LVCFMT_LEFT/RIGHT/CENTER from `align`
                    $width,                       # cx
                    Affix::address($abuf),        # pszText
                    0,                            # cchTextMax
                    $i,                           # iSubItem
                    0, 0, 0, 0, 0, 0,             # iImage/iOrder/cxMin/cxDefault/cxIdeal/iTitle
                    0,                            # pszTitle
                    0;                            # cbTitle
                my $struct = malloc( length $bytes );
                memcpy( $struct, $bytes, length $bytes );
                SendMessageW( $hwnd, 0x1061, $i, Affix::address($struct) );        # LVM_INSERTCOLUMNW
                free($struct);
                free($abuf);
            }
            $lv->{ncols}  = scalar @$cols;
            $lv->{colorder} = [ 0 .. ( scalar @$cols ) - 1 ];
        }

        my $i = 0;
        for my $row ( @{ $node->rows // [] } ) {
            my $cells = ref $row eq 'HASH' ? $row->{columns} : $row;
            my $value = ref $row eq 'HASH' ? $row->{value} : ( $cells->[0] // '' );
            push @{ $lv->{slots} }, {
                value   => $value,
                columns => [ map { '' . ( $_ // '' ) } @{ $cells || [] } ],
            };
            $self->_lv_write_row( $hwnd, $i, $lv->{slots}[-1]{columns}, $node->columns );
            $i++;
        }

        # Repopulate reset the native selection; restore the model's. An active user sort (LVN_COLUMNCLICK
        # or re-applied from the reconciler) is kept leading: the sorted slots are rebuilt and selection is
        # re-applied against the OPTICAL order.
        if ( $lv->{sort} ) {
            $self->_sort_listview( $id, $lv->{sort}{col}, $lv->{sort}{dir}, $node->value );
        }
        else {
            $self->_select_listvalue( $id, $node->value );
        }
    }

    # Insert (column 0) / set (later columns) one row's text cells in the native control. When the
    # column definition carries a `format` (e.g. '$%0.2f') the DISPLAY text is sprintf'd from the
    # (numeric) cell, but the slot keeps the RAW cell so `_sort_listview` never sorts formatted
    # strings. Cell text is copied by the control during the call, so each UTF-16 buffer is freed
    # immediately after.
    method _lv_write_row ( $hwnd, $row, $cells, $columns = undef ) {
        for my $c ( 0 .. $#$cells ) {
            my $cell = '' . ( $cells->[$c] // '' );
            my $colh = $columns->[$c] // {};
            my $fmt  = $colh->{format} || '';
            if ( $fmt ne '' && $cell =~ /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/ ) {
                $cell = sprintf $fmt, 0 + $cell;
            }
            my $wide = Encode::encode( 'UTF-16LE', $self->_nz($cell) ) . "\x00\x00";
            my $abuf = malloc( CORE::length($wide) );
            memcpy( $abuf, $wide, CORE::length($wide) );
            my $bytes = pack $LVITEM,
                0x0001,                       # mask = LVIF_TEXT
                $row,                         # iItem
                $c,                           # iSubItem
                0, 0,                         # state / stateMask
                Affix::address($abuf),        # pszText
                0,                            # cchTextMax
                0,                            # iImage
                0,                            # lParam
                0, 0, 0,                      # iIndent / iGroupId / cColumns
                0, 0, 0;                      # puColumns / piColFmt / iGroup
            my $struct = malloc( length $bytes );
            memcpy( $struct, $bytes, length $bytes );
            if ( $c == 0 ) {
                SendMessageW( $hwnd, 0x104D, $row, Affix::address($struct) );    # LVM_INSERTITEMW
            }
            else {
                # LVM_SETITEMW (not LVM_SETITEMTEXTW, which implicitly no-ops for
                # subitems > 0) writes the cell into the existing item.
                SendMessageW( $hwnd, 0x104C, 0, Affix::address($struct) );    # LVM_SETITEMW
            }
            free($struct);
            free($abuf);
        }
    }

    # Rebuild the native rows in sorted order. Sorting stays a display concern: the slot table (row
    # index -> model value) is re-permuted from the RAW cells (the model columns are untouched), the
    # currently-selected VALUES are re-selected (suppressed) against the new optical order, and an
    # on_sort action lets the app reorder its own `rows` for the model truth. Per-column `sort =>`
    # 'numeric' (default 'text') picks the comparator; cell text is stored on the slot at populate.
    # $want selects which values stay selected: a list of values (repopulate path - the native
    # selection has been reset by LVM_DELETEALLITEMS), or 'snapshot' (user click - preserved from
    # the native control before the rebuild).
    method _sort_listview ( $id, $col, $dir, $want = 'snapshot' ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $lv   = $rec->{listview} or return;
        my $ncols = $lv->{ncols} // 0;
        return if $col < 0 || $col >= $ncols;
        my $numeric = ( ( $node->columns->[$col] // {} )->{sort} // 'text' ) eq 'numeric';

        # Which VALUES remain selected after the rebuild.
        my %sel;
        if ( ref $want eq 'ARRAY' ) {
            $sel{$_} = 1 for map { ( $_ // '' ) } @$want;
        }
        elsif ( defined $want && $want ne 'snapshot' ) {
            $sel{ '' . $want } = 1;
        }
        else {
            for my $i ( 0 .. $#{ $lv->{slots} } ) {
                my $st = SendMessageW( $hwnd, 0x102C, $i, 0x0002 );    # LVM_GETITEMSTATE(i, LVIS_SELECTED)
                $sel{ ( $lv->{slots}[$i]{value} // '' ) } = 1 if $st & 0x0002;
            }
        }

        my $cell = sub ($i) {
            my $cs = $lv->{slots}[$i]{columns};
            return $cs ? ( '' . ( $cs->[$col] // '' ) ) : '';
        };
        my @order = 0 .. $#{ $lv->{slots} };
        @order = sort {
            my $cmp = $numeric
                ? ( ( $cell->($a) + 0 ) <=> ( $cell->($b) + 0 ) )
                : ( lc( $cell->($a) ) cmp lc( $cell->($b) ) );
            return $cmp if $cmp;
            ( ( $lv->{slots}[$a]{value} // '' ) cmp ( $lv->{slots}[$b]{value} // '' ) );    # stable tiebreak
        } @order;
        @order = reverse @order if $dir eq 'desc';

        # Rebuild the native rows in the sorted order.
        SendMessageW( $hwnd, 0x1009, 0, 0 );    # LVM_DELETEALLITEMS
        my $i = 0;
        for my $oi (@order) {
            $self->_lv_write_row( $hwnd, $i, $lv->{slots}[$oi]{columns}, $node->columns );
            $i++;
        }
        my $old_col = $lv->{sort} ? $lv->{sort}{col} : undef;
        $lv->{slots} = [ map { $lv->{slots}[$_] } @order ];
        $lv->{sort}  = { col => $col, dir => $dir };
        $self->_apply_sort_indicator( $id, $old_col, $col, $dir );

        # Re-select the same VALUES in the new order (suppressed: model-driven, not a user click).
        $suppress_events = 1;
        for my $i ( 0 .. $#{ $lv->{slots} } ) {
            next unless $sel{ $lv->{slots}[$i]{value} // '' };
            my $selb = pack $LVITEM,
                0x0008, $i, 0, 0x0002, 0x0002, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVIF_STATE, state=LVIS_SELECTED
            my $sbuf = malloc( length $selb );
            memcpy( $sbuf, $selb, length $selb );
            SendMessageW( $hwnd, 0x102B, $i, Affix::address($sbuf) );    # LVM_SETITEMSTATE
            free($sbuf);
        }
        $suppress_events = 0;
        for my $i ( 0 .. $#{ $lv->{slots} } ) {
            next unless $sel{ $lv->{slots}[$i]{value} // '' };
            SendMessageW( $hwnd, 0x1013, 1, $i );    # LVM_ENSUREVISIBLE
            last unless $node->multiple;
        }
    }

    # Read the listview's current left-to-right column order (LVM_GETCOLUMNORDERARRAY).
    method lv_column_order ( $hwnd, $n ) {
        return [] unless $hwnd && $n > 0;
        my $buf = malloc( $n * 4 );
        SendMessageW( $hwnd, 0x103B, $n, Affix::address($buf) );    # LVM_GETCOLUMNORDERARRAY
        my $raw = Affix::raw( $buf, $n * 4 );
        free($buf);
        return [ unpack( ( 'l<' ) x $n, $raw ) ];
    }

    # Portable header-click seam (contract in Uji::Driver): simulate the user clicking the header of
    # MODEL column @model_col on list_view @$node. Win32 implements it as the REAL user path does --
    # the list-view control sends its parent window an LVN_COLUMNCLICK WM_NOTIFY whose NMLISTVIEW
    # hwndFrom is the list-view control, code is LVN_COLUMNCLICK (-108) and iSubItem is the MODEL
    # identity of the clicked column (native .iSubItem is MODEL-indexed; see LVN_COLUMNCLICK in the
    # poll loop). We build that notification and route it to the parent window exactly as the native
    # header control does, so _dispatch -> _sort_listview -> on_sort + glyph/order handling all fire
    # on the identical path a real pointer click takes. The driver tracks the MODEL column wherever a
    # header drag has placed it, so no visual-slot remap is applied (that is what the model-4 test
    # pins down).
    method list_view_click_column ( $node, $model_col ) {
        my $id  = $node->id              or return;
        my $rec = $self->_get_registry_record($id) or return;
        my $hwnd   = $rec->{hwnd}  or return;
        my $parent = $rec->{parent_hwnd} or return;
        my $nmhdr  = "\0" x 64;
        substr( $nmhdr, 0, 8 )  = pack( 'q<', $hwnd );            # hwndFrom = the list-view control
        substr( $nmhdr, 16, 4 ) = pack( 'l<', -108 );              # code = LVN_COLUMNCLICK
        substr( $nmhdr, 24, 4 ) = pack( 'l<', -1 );                # iItem (unused)
        substr( $nmhdr, 28, 4 ) = pack( 'l<', $model_col );        # iSubItem = MODEL identity
        my $buf = malloc(64);
        memcpy( $buf, $nmhdr, 64 );
        SendMessageW( $parent, 0x004E, 0, Affix::address($buf) );  # WM_NOTIFY to the PARENT window
        free($buf);
        for ( 1 .. 20 ) { $self->poll_events }
        return;
    }

    # Move the header's sort indicator (a ▲/▼ glyph beside the sorted column's label). The previous
    # sort column's header is restored to its plain label; the clicked model column gets the glyph for
    # the new direction. LVM_SETCOLUMNW(/GETCOLUMNW) address columns by their MODEL index, which
    # follows the item wherever a header drag has placed it, so no visual-index mapping is needed and
    # neither the user-resized widths nor a drag-reordered column order are disturbed.
    method _apply_sort_indicator ( $id, $from_col, $to_col, $dir ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $lv   = $rec->{listview} or return;
        my $ncols = $lv->{ncols} // 0;
        if ( defined $from_col && $from_col < $ncols ) {
            my $label = ( $node->columns->[$from_col] // {} )->{label} // '';
            $self->_set_header_label( $hwnd, $from_col, $label );
        }
        if ( defined $to_col && $to_col < $ncols ) {
            my $label = ( $node->columns->[$to_col] // {} )->{label} // '';
            $label .= $dir eq 'asc' ? ' ▲' : ' ▼';
            $self->_set_header_label( $hwnd, $to_col, $label );
        }
    }

    # In-place header label replacement for one column (LVM_SETCOLUMNW with LVCF_TEXT only). The text
    # buffer is copied by the control during the call, so it is freed immediately after.
    method _set_header_label ( $hwnd, $vis, $label ) {
        my $wide  = Encode::encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00";
        my $abuf  = malloc( CORE::length($wide) );
        memcpy( $abuf, $wide, CORE::length($wide) );
        my $bytes = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4',
            0x0004, 0, 0, Affix::address($abuf), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVCF_TEXT
        my $struct = malloc( length $bytes );
        memcpy( $struct, $bytes, length $bytes );
        SendMessageW( $hwnd, 0x1060, $vis, Affix::address($struct) );    # LVM_SETCOLUMNW
        free($struct);
        free($abuf);
    }

    # Poll-time sync for reorderable list_view columns: after the user drags a header item, the native
    # control reorders columns + data itself (LVS_EX_HEADERDRAGDROP); we only need to learn the new order
    # (LVM_GETCOLUMNORDERARRAY) so the driver keeps `colorder` current and can tell the app. Compared per
    # poll - a single small query per reorderable list - and on_change dispatches on_reorder.
    method _sync_column_orders () {
        return unless %$registry;
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id} or next;
            next unless $rec->{node} && $rec->{node}->type eq 'list_view' && $rec->{node}->reorderable;
            my $lv    = $rec->{listview} or next;
            my $hwnd  = $rec->{hwnd}     or next;
            my $n     = $lv->{ncols} // 0;
            next unless $n;
            my $order = $self->lv_column_order( $hwnd, $n );
            my $have  = $lv->{colorder} ||= [ 0 .. $n - 1 ];
            my $same  = 1;
            for my $i ( 0 .. $n - 1 ) { $same = 0 if ( $order->[$i] // -1 ) != ( $have->[$i] // -1 ); }
            next if $same;
            $lv->{colorder} = $order;
            if ( $rec->{node}->can('on_reorder') && $rec->{node}->on_reorder ) {
                my $action = $rec->{node}->on_reorder->( [ @$order ] );
                $self->channel->put($action) if $action;
            }
        }
    }

    # Apply the model's selection to the native list (used at mount, after a repopulate, and from
    # set_prop('value')). With `multiple` $value is an arrayref; the whole selection is cleared
    # first via LVM_SETITEMSTATE(iItem=-1, stateMask=LVIS_SELECTED), then each matching row is
    # selected and scrolled into view (LVM_ENSUREVISIBLE). Selection is suppressed while it runs so
    # the native LVN_ITEMCHANGED echo never dispatches a bogus on_select.
    method _select_listvalue ( $id, $value ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $lv   = $rec->{listview} or return;
        my $want = ref $value eq 'ARRAY' ? $value : [ defined $value ? $value : () ];

        my $clear = pack $LVITEM,
            0x0008, 0, 0, 0, 0x0002, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVIF_STATE, iItem=0, state=0, stateMask=LVIS_SELECTED
        my $cbuf = malloc( length $clear );
        memcpy( $cbuf, $clear, length $clear );
        $suppress_events = 1;
        SendMessageW( $hwnd, 0x102B, -1, Affix::address($cbuf) );    # LVM_SETITEMSTATE(-1): deselect all
        free($cbuf);
        for my $i ( 0 .. $#{ $lv->{slots} } ) {
            next unless grep { ( $_ // '' ) eq ( $lv->{slots}[$i]{value} // '' ) } @$want;
            my $sel = pack $LVITEM,
                0x0008, $i, 0, 0x0002, 0x0002, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVIF_STATE, iItem=$i, state=LVIS_SELECTED
            my $sbuf = malloc( length $sel );
            memcpy( $sbuf, $sel, length $sel );
            SendMessageW( $hwnd, 0x102B, $i, Affix::address($sbuf) );    # LVM_SETITEMSTATE
            free($sbuf);
            SendMessageW( $hwnd, 0x1013, 1, $i );                        # LVM_ENSUREVISIBLE
        }
        $suppress_events = 0;
    }

    # Toolbar population: delete every existing button, then build an array of 32-byte TBBUTTON
    # structs and push them in one TB_ADDBUTTONSW. Text-only buttons use I_IMAGENONE (-2) with
    # a TB_ADDSTRINGW string table entry per label; separator buttons set fsStyle=BTNS_SEP (0x01)
    # with the width in iBitmap. Each button gets a unique idCommand from $cmd_counter (0x4000+)
    # so WM_COMMAND routing never collides with control IDs in the registry.
    method _populate_toolbar ( $id, $buttons = undef ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        $buttons //= $node->buttons;

        # Wipe every existing button (TB_BUTTONCOUNT returns the count; TB_DELETEBUTTON(0)
        # removes index 0 each time).
        my $old_cnt = SendMessageW( $hwnd, 0x0418, 0, 0 );           # TB_BUTTONCOUNT
        SendMessageW( $hwnd, 0x0416, 0, 0 ) while $old_cnt-- > 0;    # TB_DELETEBUTTON

        # Drop stale WM_COMMAND routing entries for this toolbar.
        my $tb = $rec->{toolbar} ||= { by_cmd => {} };
        for my $cmd ( keys %{ $tb->{by_cmd} } ) {
            delete $toolbar_cmds->{$cmd};
        }
        $tb->{by_cmd} = {};
        return unless @$buttons;
        my @structs;
        for my $b (@$buttons) {
            if ( $b->{separator} ) {

                # iBitmap = separator width in pixels; idCommand = 0; fsStyle = BTNS_SEP
                push @structs, pack 'l< l< C C x6 q< q<', ( $b->{width} // 6 ), 0, 0, 0x01, 0, 0;
                next;
            }

            # Allocate a string table index for the label via TB_ADDSTRINGW (the control
            # stores a copy; our UTF-16 buffer is freed immediately after the call).
            my $label = $b->{label} // '';
            my $wide  = Encode::encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00";
            my $str   = malloc( CORE::length($wide) );
            memcpy( $str, $wide, CORE::length($wide) );
            my $str_idx = SendMessageW( $hwnd, 0x044D, 1, Affix::address($str) );    # TB_ADDSTRINGW
            free($str);
            my $cmd  = $cmd_counter++;
            my $fsSt = 0x04;                                                         # TBSTATE_ENABLED
            $fsSt |= 0x01  if $b->{checked};                                         # TBSTATE_CHECKED
            $fsSt &= ~0x04 if defined $b->{enabled} && !$b->{enabled};               # drop ENABLED when explicitly false
            push @structs, pack 'l< l< C C x6 q< q<', -2,                            # iBitmap (I_IMAGENONE = -2: no image, text-only layout)
                $cmd,                                                                # idCommand
                $fsSt,                                                               # fsState
                0x00,                                                                # fsStyle (BTNS_BUTTON)
                0,                                                                   # dwData
                $str_idx;                                                            # iString (index into toolbar string table)
            my $bid = $b->{id} // $label;
            $tb->{by_cmd}{$cmd} = { id => $bid };
            $toolbar_cmds->{$cmd} = $id;
        }

        # Pack all TBBUTTON structs (each 32 bytes on x64) into a contiguous buffer.
        my $body = join '', @structs;
        my $arr  = malloc( CORE::length($body) );
        memcpy( $arr, $body, CORE::length($body) );
        SendMessageW( $hwnd, 0x0444, scalar @structs, Affix::address($arr) );    # TB_ADDBUTTONSW
        free($arr);
    }

    # Menu bar population: build a native menu tree from a window node's menu_bar property and
    # attach it with SetMenu. Top-level items become popup submenus (MF_POPUP); leaf items get a
    # driver-wide idCommand from $cmd_counter (0x4000+) routed to the owning surface window's
    # MenuBar.on_click via $menu_cmds. Separators use MF_SEPARATOR. Rebuilding destroys the
    # previous menu tree (DestroyMenu on the bar handle frees attached popups) and re-registers.
    method _mount_menu_bar ($id) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $mb   = $node->menu_bar;
        if ( my $old = $rec->{menu_bar} ) {
            for my $cmd ( keys %{ $old->{by_cmd} } ) {
                delete $menu_cmds->{$cmd};
            }
            DestroyMenu( $old->{hmenu} ) if $old->{hmenu};
        }
        $rec->{menu_bar} = undef;
        return unless $mb && @{ $mb->items // [] };
        my $bar  = CreateMenu();
        my $mrec = { hmenu => $bar, by_cmd => {} };
        $rec->{menu_bar} = $mrec;
        $self->_append_menu_items( $bar, $mb->items, $rec->{surface}, $mrec );
        SetMenu( $hwnd, $bar );
        DrawMenuBar($hwnd);
    }

    # Recursive menu item builder. An item is a hashref: leaf = { label =>, id =>, [enabled]>,
    # [checked]> }; submenu = { label =>, children => [...] }; separator = { separator => 1 }.
    method _append_menu_items ( $hmenu, $items, $win_id, $mrec ) {
        for my $it ( @{ $items // [] } ) {
            if ( $it->{separator} ) {
                AppendMenuW( $hmenu, 0x0800, 0, '' );    # MF_SEPARATOR (id + label ignored)
                next;
            }
            my $label = $self->_nz( $it->{label} // '' );
            if ( $it->{children} && @{ $it->{children} } ) {
                my $sub = CreatePopupMenu();
                $self->_append_menu_items( $sub, $it->{children}, $win_id, $mrec );
                AppendMenuW( $hmenu, 0x0010, $sub, $label );    # MF_POPUP (uIDNewItem = submenu HMENU)
                next;
            }
            my $cmd   = $cmd_counter++;
            my $flags = 0x0000;                             # MF_STRING | MF_ENABLED
            $flags |= 0x0001 unless $it->{enabled} // 1;    # MF_GRAYED
            $flags |= 0x0008 if $it->{checked};             # MF_CHECKED
            AppendMenuW( $hmenu, $flags, $cmd, $label );    # MF_STRING leaf
            $mrec->{by_cmd}{$cmd} = { id => $it->{id} // $label };
            $menu_cmds->{$cmd} = { win_id => $win_id };
        }
    }

    # Select the model's current value in the native tree (used at mount, after a repopulate, and
    # from set_prop('value')). Walks the slot table -> HTREEITEM, then TVM_SELECTITEM(TVGN_CARET)
    # and TVM_ENSUREVISIBLE so a deep selection is scrolled into view.
    method _select_tree_value ( $id, $value ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $t    = $rec->{tree}     or return;
        return unless defined $value;
        my $slot = $t->{by_value}{$value};
        return unless defined $slot;
        my $hitem = $t->{slots}[$slot]{hitem};
        return unless $hitem;
        SendMessageW( $hwnd, 0x110B, 0x0009, $hitem );    # TVM_SELECTITEM(TVGN_CARET)
        SendMessageW( $hwnd, 0x1114, 0,      $hitem );    # TVM_ENSUREVISIBLE
    }

    # Toggle which panel's content subtree is visible (all panels share the same body rect; only
    # the active one is shown).  The sequence matters: (1) hide inactive subtrees so they stop
    # painting, (2) push SysTabControl32 to HWND_BOTTOM so its opaque body does not cover
    # sibling widgets, (3) show the active subtree and bring each widget to HWND_TOP so they
    # paint above the tab body.
    method _apply_tab ($id) {
        my $rec  = $registry->{$id} or return;
        my $node = $rec->{node}     or return;
        my $idx  = $rec->{index} // 0;

        # 1. Hide inactive panel subtrees first
        my $i = 0;
        for my $child ( @{ $node->children } ) {
            $self->_set_branch_visible( $child, 0 ) if $i != $idx;
            $i++;
        }

        # 2. Place the tab control at the bottom of the Z-order and update its strip
        if ( my $tab_hw = $rec->{hwnd} ) {
            SetWindowPos( $tab_hw, cast( 1, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );    # HWND_BOTTOM, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            UpdateWindow($tab_hw);
        }

        # 3. Show active panel subtree, bring controls to HWND_TOP, and repaint
        if ( my $active = $node->children->[$idx] ) {
            $self->_set_branch_visible( $active, 1 );
        }
    }

    # ShowWindow a subtree recursively including its auxiliary native windows (viewport scrollbars,
    # spin up-down buddy, split divider strip), so an inactive tab hides its whole content stack.
    # When showing, each control is brought to HWND_TOP and invalidated so freshly exposed
    # panels paint immediately instead of staying blank until the mouse happens to move over them.
    method _set_branch_visible ( $node, $vis ) {
        if ( my $rec = $registry->{ $node->id } ) {
            if ( my $hwnd = $rec->{hwnd} ) {
                if ($vis) {
                    ShowWindow( $hwnd, 5 );                                                  # SW_SHOW
                    SetWindowPos( $hwnd, cast( 0, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );    # HWND_TOP, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
                    InvalidateRect( $hwnd, undef, 1 );                                       # erase + whole client
                    UpdateWindow($hwnd);                                                     # synchronous WM_PAINT
                }
                else {
                    ShowWindow( $hwnd, 0 );                                                  # SW_HIDE
                }
            }
            for my $auxkey (qw[ aux aux_h aux_v ]) {
                my $aux = $rec->{$auxkey} or next;
                if ($vis) {
                    ShowWindow( $aux, 5 );
                    SetWindowPos( $aux, cast( 0, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );     # HWND_TOP
                    InvalidateRect( $aux, undef, 1 );
                    UpdateWindow($aux);
                }
                else {
                    ShowWindow( $aux, 0 );
                }
            }
        }
        $self->_set_branch_visible( $_, $vis ) for @{ $node->children };
    }

    # Tag every registry record in a content subtree with the scroll_view's shared store so
    # move_widget offsets it relative to the viewport. A nested scroll_view keeps its OWN store
    # (set by _mount_node) and takes its subtree with it, so tagging stops at such nodes.
    method _mark_scrolled ( $node, $store ) {
        return if $node->type eq 'scroll_view';
        if ( my $rec = $registry->{ $node->id } ) {
            $rec->{scroll} = $store;
        }
        $self->_mark_scrolled( $_, $store ) for @{ $node->children };
    }

    # Mount a runtime-ADDED node (from the reconciler) under an explicit HWND, tagging every
    # created record with a scroll store when the node sits inside a ScrollView content column.
    # Mirrors the scroll_view mount branch so new content behaves like the initial content.
    # $ctx is the reconciler's anchor context (the nearest window / scroll_view / group_box node):
    # it supplies parent HWND + scroll store structurally, which is what makes the FIRST child of
    # a previously-empty ScrollView content column land inside the viewport instead of under the
    # $main_hwnd (sibling records don't exist yet).
    method mount_subtree ( $vnode, $ctx = undef, $parent_hwnd = undef, $store = undef ) {
        if ($ctx) {
            my $cr = $registry->{ $ctx->id };
            if ( $ctx->type eq 'scroll_view' && $cr ) {
                $parent_hwnd = $cr->{hwnd};
                $store       = $cr->{scroll};
            }
            elsif ( $ctx->type eq 'window' && $cr ) {
                $parent_hwnd = $cr->{hwnd};
            }
            elsif ( $ctx->type eq 'group_box' && $cr ) {
                $parent_hwnd = $cr->{parent_hwnd};
            }
            elsif ( $ctx->type eq 'tab_panel' && $cr ) {
                $parent_hwnd = $cr->{parent_hwnd};
            }
        }
        $parent_hwnd //= $main_hwnd;
        $self->_mount_node( $vnode, $parent_hwnd );
        $self->_mark_scrolled( $vnode, $store ) if $store && $registry->{ $vnode->id };
    }

    # Destroy the native controls of a REMOVED node (subtree) and drop all registry maps for it.
    method unmount_subtree ($node) {
        if ( my $rec = $registry->{ $node->id } ) {
            my $hw = $rec->{hwnd};
            DestroyWindow( $rec->{aux} ) if $rec->{aux};
            if ($hw) {
                DestroyWindow($hw);
                delete $surface_by_hwnd->{$hw};
            }
            delete $registry->{ $node->id };
        }
        $self->unmount_subtree($_) for @{ $node->children };
    }

    # ─── System dialogs (COMCTL-native, blocking) ─────────────────────────────
    # Convert a filter spec into the double-NUL-terminated UTF-16 blob that
    # lpstrFilter expects: "label\0pattern\0label2\0pattern2\0\0".
    # Accepts an arrayref of [ label, pattern ] pairs or a "Label|*.ext|All|*.*" string.
    method _ofn_filter_string ($filter) {
        my @pairs;
        if ( ref $filter eq 'ARRAY' ) {
            @pairs = @$filter;
        }
        elsif ( defined $filter && length $filter ) {
            my @parts = split qr/\|/, $filter;
            for ( my $i = 0; $i + 1 < @parts; $i += 2 ) {
                push @pairs, [ $parts[$i], $parts[ $i + 1 ] ];
            }
        }
        @pairs = ( [ 'All files', '*.*' ] ) unless @pairs;
        return encode( 'UTF-16LE', join( "\0", map {@$_} @pairs ) . "\0\0" );
    }

    # Parse the lpstrFile buffer AFTER a successful GetOpenFileNameW/GetSaveFileNameW
    # call. Single-select buffer is "path\0". With OFN_ALLOWMULTISELECT | OFN_EXPLORER
    # it is "dir\0file1\0file2\0\0" (nFileOffset points at the first filename char).
    # The zero-padded tail of the malloc'd buffer must not leak into the result, so we
    # use the FIRST double-NUL (or single-NUL) terminator as the effective end.
    method _ofn_parse_result ( $ptr, $bytes, $multi ) {
        my $s = decode( 'UTF-16LE', Affix::raw( $ptr, $bytes ) );
        if ( my $i = index( $s, "\0\0" ) ) { $s = substr( $s, 0, $i ) if $i > 0 }
        else {
            my $j = index( $s, "\0" );
            $s = substr( $s, 0, $j ) if $j > 0;
        }
        my @parts = split /\0/, $s;
        if ( $multi && @parts > 1 ) {
            my $dir = shift @parts;
            return [ map {"$dir\\$_"} @parts ];
        }
        return $parts[0];
    }

    # Shared OPENFILENAMEW builder. Returns ($struct_ptr, [ $ofn, $filebuf, $filterbuf, $titlebuf ])
    # so the caller can free every allocation after the (blocking) call. Pointer fields are
    # set from INTEGER addresses (Affix::address) -- assigning a pointer OBJECT would store the
    # SV's own address instead of the buffer it wraps (same quirk as SendMessageW lParam).
    method _ofn_build ( $mode, %o ) {
        my $owner   = $o{owner} // $main_hwnd // 0;
        my $nmax    = 32768;
        my $struct  = malloc( sizeof( OPENFILENAMEW() ) );
        my $ofn     = cast( $struct, OPENFILENAMEW() );
        my $filebuf = calloc( $nmax, 2 );
        my ( $filterbuf, $titlebuf, $initbuf );
        my $filter = $self->_ofn_filter_string( $o{filter} );
        if ( length $filter ) {
            $filterbuf = malloc( length $filter );
            memcpy( $filterbuf, $filter, length $filter );
        }
        if ( defined $o{title} && length $o{title} ) {
            my $t = encode( 'UTF-16LE', $o{title} . "\0" );
            $titlebuf = malloc( length $t );
            memcpy( $titlebuf, $t, length $t );
        }
        if ( defined $o{default_dir} && length $o{default_dir} ) {
            my $d = encode( 'UTF-16LE', $o{default_dir} . "\0" );
            $initbuf = malloc( length $d );
            memcpy( $initbuf, $d, length $d );
        }
        if ( defined $o{default_name} && length $o{default_name} ) {
            my $n = encode( 'UTF-16LE', $o{default_name} );
            memcpy( $filebuf, $n, length $n );
        }
        $ofn->{lStructSize}     = sizeof( OPENFILENAMEW() );
        $ofn->{hwndOwner}       = $owner;
        $ofn->{lpstrFilter}     = $filterbuf ? Affix::address($filterbuf) : 0;
        $ofn->{nFilterIndex}    = 1;
        $ofn->{lpstrFile}       = Affix::address($filebuf);
        $ofn->{nMaxFile}        = $nmax;
        $ofn->{lpstrInitialDir} = $initbuf  ? Affix::address($initbuf)  : 0;
        $ofn->{lpstrTitle}      = $titlebuf ? Affix::address($titlebuf) : 0;
        my $flags = 0x4 | 0x8 | 0x800 | 0x80000;    # OFN_HIDEREADONLY | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | OFN_EXPLORER

        if ( $mode eq 'save' ) {
            my $op = defined $o{overwrite_prompt} ? $o{overwrite_prompt} : 1;
            $flags |= 0x2 if $op;                   # OFN_OVERWRITEPROMPT
        }
        else {
            $flags |= 0x1000 unless $o{no_file_must_exist};    # OFN_FILEMUSTEXIST
            $flags |= 0x200 if $o{multi};                      # OFN_ALLOWMULTISELECT
        }
        $ofn->{Flags} = $flags;
        return ( $struct, [ $ofn, $filebuf, $filterbuf, $titlebuf, $initbuf ] );
    }

    method _ofn_free ( $struct, $parts ) {
        for my $i ( 1 .. $#$parts ) { free( $parts->[$i] ) if $parts->[$i]; }
        free($struct);
    }

    # prompt_dialog internals: the modal wndproc is the ONLY writer (writes happen on its
    # thread, inside DispatchMessageW during our pump), so these tiny accessors keep the field
    # hand-off explicit and stay out of the way of the main event loop.
    method _get_prompt_edit ()    {$prompt_edit}
    method _set_prompt_value ($v) { $prompt_value = $v }
    method _prompt_finish ()      { $prompt_done  = 1 }

    # Blocking modal text-input dialog. Returns the entered string, or undef when cancelled.
    # Options: title, message, default, owner, hook.
    # $hook is a TEST-ONLY seam: called as $hook->($dlg, $edit) right after the dialog is shown
    # but BEFORE the modal pump starts, allowing a test to set the edit text and SendMessageW a
    # WM_COMMAND (id 1 = OK, id 2 = Cancel) synchronously on this same thread -- the pump then
    # exits with the captured value. Open production calls simply omit it.
    method prompt_dialog (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        my $hook  = $o{hook};
        $prompt_done  = 0;
        $prompt_value = undef;

        # WS_POPUP | WS_CAPTION | WS_SYSMENU; parent must be a numeric HWND (an undef Perl
        # variable passed to a Pointer[Void] param hands Affix the SV's own address -> create fails)
        my $dlg = CreateWindowExW( 0, $prompt_class, $self->_nz( $o{title} // 'Prompt' ), 0x80C00000, 200, 200, 380, 160, $owner, 0, 0, 0 );
        return undef unless $dlg;
        $prompt_hwnd = $dlg;
        CreateWindowExW( 0, 'STATIC', $self->_nz( $o{message} // '' ), 0x50000000, 14, 10, 340, 40, $dlg, 0, 0, 0 );
        my $yes = CreateWindowExW( 0, 'EDIT', $self->_nz( $o{default} // '' ), 0x50810080, 14, 60, 340, 24, $dlg, 0, 0, 0 );
        CreateWindowExW( 0, 'BUTTON', 'OK',     0x50000000, 240, 100, 60, 26, $dlg, 1, 0, 0 );
        CreateWindowExW( 0, 'BUTTON', 'Cancel', 0x50000000, 306, 100, 60, 26, $dlg, 2, 0, 0 );
        $prompt_edit = $yes;
        ShowWindow( $dlg, 5 );    # SW_SHOW
        SetFocus($prompt_edit);
        $hook->( $dlg, $prompt_edit ) if $hook;
        my $msg_ptr = malloc(48);

        while ( !$prompt_done ) {
            my $gm = GetMessageW( $msg_ptr, undef, 0, 0 );
            last if $gm <= 0;
            TranslateMessage($msg_ptr);
            no warnings 'uninitialized';
            DispatchMessageW($msg_ptr);

            # Keep interval subscriptions and re-renders alive while this modal pump owns the thread.
            $on_modal_pump->() if $on_modal_pump;
        }
        free($msg_ptr);
        DestroyWindow($dlg);
        return defined $prompt_value ? $prompt_value : undef;
    }

    # Blocking "Open file" dialog. Returns a path string (single), an arrayref of paths
    # (multi => 1), or undef when cancelled. Options: title, filter, default_dir,
    # default_name, multi, owner, no_file_must_exist, overwrite_prompt.
    method file_open_dialog (%o) {
        my ( $struct, $parts ) = $self->_ofn_build( 'open', %o );
        my $ok  = GetOpenFileNameW($struct);
        my $res = $ok ? $self->_ofn_parse_result( $parts->[1], 32768 * 2, $o{multi} ) : undef;
        $self->_ofn_free( $struct, $parts );
        return $res;
    }

    # Blocking "Save file" dialog. Returns the chosen path string or undef on cancel.
    # Options: title, filter, default_dir, default_name, owner, overwrite_prompt.
    method file_save_dialog (%o) {
        my ( $struct, $parts ) = $self->_ofn_build( 'save', %o );
        my $ok  = GetSaveFileNameW($struct);
        my $res = $ok ? $self->_ofn_parse_result( $parts->[1], 32768 * 2, 0 ) : undef;
        $self->_ofn_free( $struct, $parts );
        return $res;
    }

    # Map a MessageBox button/icon selection to the MB_* flag word. Pure, so tests can
    # pin the mapping without opening a real dialog.
    method _mb_flags (%o) {
        my %btn   = ( ok    => 0x0,  okcancel => 0x1,  abortretryignore => 0x2, yesnocancel => 0x3, yesno => 0x4, retrycancel => 0x5, );
        my %ico   = ( error => 0x10, question => 0x20, warning => 0x30, info => 0x40, );
        my $flags = ( $btn{ $o{buttons} // 'ok' } // 0x0 );
        $flags |= $ico{ $o{icon} }                if $o{icon};
        $flags |= ( 0x100 * ( $o{default} - 1 ) ) if $o{default} && $o{default} >= 2 && $o{default} <= 3;
        return $flags;
    }
    my %MB_RESULT
        = ( 1 => 'ok', 2 => 'cancel', 3 => 'abort', 4 => 'retry', 5 => 'ignore', 6 => 'yes', 7 => 'no', 10 => 'tryagain', 11 => 'continue', );

    # Blocking MessageBoxW. Options: title, message, buttons (ok|okcancel|yesno|yesnocancel|
    # abortretryignore|retrycancel), icon (error|question|warning|info), default (1-3), owner.
    # Returns the pressed button name or undef if the call failed.
    method message_box (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        my $rc    = MessageBoxW( $owner, $self->_nz( $o{message} ), $self->_nz( $o{title} // 'Uji' ), $self->_mb_flags(%o) );
        return $MB_RESULT{$rc};
    }

    # Blocking ChooseColorW. Options: title, initial ('#RRGGBB' or undef), full_open, owner.
    # Returns the picked '#RRGGBB' string or undef on cancel.
    method color_picker (%o) {
        my $owner  = $o{owner} // $main_hwnd // 0;
        my $struct = malloc( sizeof( CHOOSECOLORW() ) );
        my $cc     = cast( $struct, CHOOSECOLORW() );
        my $custom = calloc( 16, 4 );                      # 16 initial custom colours, 0x00bbggrr
        my $flags  = 0x1 | 0x100;                          # CC_RGBINIT | CC_ANYCOLOR
        $flags |= 0x2 if $o{full_open};                    # CC_FULLOPEN
        my $initial = 0;
        if ( $o{initial} && $o{initial} =~ /^#([0-9a-fA-F]{6})$/ ) {
            my $hex = $1;
            my ( $r, $g, $b ) = map { hex($_) } ( substr( $hex, 0, 2 ), substr( $hex, 2, 2 ), substr( $hex, 4, 2 ) );
            $initial = ( $b << 16 ) | ( $g << 8 ) | $r;
        }
        $cc->{lStructSize}  = sizeof( CHOOSECOLORW() );
        $cc->{hwndOwner}    = $owner;
        $cc->{rgbResult}    = $initial;
        $cc->{lpCustColors} = Affix::address($custom);
        $cc->{Flags}        = $flags;
        my $ok  = ChooseColorW($struct);
        my $res = undef;

        if ($ok) {
            my $v = $cc->{rgbResult};
            $res = sprintf '#%02X%02X%02X', ( $v & 0xFF ), ( ( $v >> 8 ) & 0xFF ), ( ( $v >> 16 ) & 0xFF );
        }
        free($custom);
        free($struct);
        return $res;
    }
};
1;
