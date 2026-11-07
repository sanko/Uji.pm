use v5.40;
use experimental 'class';
use Uji::Driver;
class Uji::Driver::Win32 v0.0.1 : isa(Uji::Driver) {
    use Affix qw[:memory :types :core];
    use Encode qw[decode encode];
    use Uji::Draw::Win32;
    use Uji::Sub ();
    field $channel : reader;
    field $registry = {};
    field $wndproc_cb;
    field $main_hwnd;
    field $main_vnode       : reader;
    field $tooltip_hwnd     : reader                             = undef;
    field $on_resize        : reader(_get_resize_handler)        = undef;
    field $on_modal_pump    : reader(_get_modal_pump)            = undef;
    field $on_close_request : reader(_get_close_request_handler) = undef;
    field $focus_last                               = 0;
    field $suppress_events : reader(_is_suppressed) = 0;
    field $item_pins                                = {};
    field $brush_cache                              = {};
    field $font_cache                               = {};
    field $cmd_counter                              = 0x4000;
    field $cid_counter                              = 0x6000;
    field $cid_to_id                                = {};
    field $toolbar_cmds                             = {};
    field $menu_cmds                                = {};
    field $modal_timer                              = 0;
    field $prompt_hwnd;
    field $prompt_edit;
    field $prompt_done = 0;
    field $prompt_value;
    field $gdi_started  = 0;
    field $gdi_token    = 0;
    field $icon_cache   = {};
    field $spin_cache   = {};
    field $bitmap_cache = {};
    field $img_dims     = {};
    my $class_seq   = 0;
    my $dpi_aware   = 0;
    my $dpi_detect  = undef;
    my $dark_detect = undef;
    my $dark_theme  = 0;
    my ( $set_pref, $allow_dark, $flush_menu );
    field $win_class      = '';
    field $viewport_class = '';
    field $divider_class  = '';
    field $prompt_class   = '';
    field $canvas_class   = '';
    field $dpi             : param  = undef;
    field $dark_mode       : param  = undef;
    field $surfaces        : reader = {};
    field $surface_by_hwnd : reader = {};
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
    affix 'user32',   'DestroyWindow',                 [ Pointer [Void] ]                                           => Int;
    affix 'user32',   'ShowWindow',                    [ Pointer [Void], Int ]                                      => Int;
    affix 'user32',   'SetWindowTextW',                [ Pointer [Void], WString ]                                  => Int;
    affix 'user32',   'EnableWindow',                  [ Pointer [Void], Int ]                                      => Int;
    affix 'user32',   'SetFocus',                      [ Pointer [Void] ]                                           => Pointer [Void];
    affix 'user32',   'SetWindowPos',                  [ Pointer [Void], Pointer [Void], Int, Int, Int, Int, UInt ] => Int;
    affix 'user32',   'DefWindowProcW',                [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;
    affix 'user32',   'PeekMessageW',                  [ Pointer [Void], Pointer [Void], UInt, UInt, UInt ]         => Int;
    affix 'user32',   'TranslateMessage',              [ Pointer [Void] ]                                           => Int;
    affix 'user32',   'DispatchMessageW',              [ Pointer [Void] ]                                           => SSize_t;
    affix 'user32',   'SetProcessDPIAware',            []                                                           => Int;
    affix 'user32',   'SetProcessDpiAwarenessContext', [Size_t]                                                     => Int;
    affix 'kernel32', 'LoadLibraryW',                  [WString]                                                    => Pointer [Void];
    affix 'kernel32', 'GetProcAddress',                [ Pointer [Void], Size_t ]                                   => Size_t;
    affix 'uxtheme',  'SetWindowTheme',                [ Pointer [Void], String, String ]                           => Int;
    affix 'user32',   'SetTimer',                      [ Pointer [Void], Size_t, UInt, Pointer [Void] ]             => Size_t;
    affix 'user32',   'KillTimer',                     [ Pointer [Void], Size_t ]                                   => Int;
    affix 'user32',   'UpdateWindow',                  [ Pointer [Void] ]                                           => Int;
    affix 'user32',   'InvalidateRect',                [ Pointer [Void], Pointer [Void], Int ]                      => Int;
    affix 'user32',   'GetCursorPos',                  [ Pointer [Void] ]                                           => Int;
    affix 'user32',   'LoadCursorW',                   [ Pointer [Void], Size_t ]                                   => Pointer [Void];
    affix 'user32',   'GetSystemMetrics',              [Int]                                                        => Int;
    affix 'user32',   'SendMessageW',                  [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;
    affix 'user32',   'SetScrollInfo',                 [ Pointer [Void], Int, Pointer [Void], Int ]                 => Int;
    affix 'user32',   'GetScrollInfo',                 [ Pointer [Void], Int, Pointer [Void] ]                      => Int;
    affix 'user32',   'SetCursor',                     [ Pointer [Void] ]                                           => Pointer [Void];
    affix 'user32',   'SetCapture',                    [ Pointer [Void] ]                                           => Pointer [Void];
    affix 'user32',   'ClientToScreen',                [ Pointer [Void], Pointer [Void] ]                           => Int;
    affix 'user32',   'ScreenToClient',                [ Pointer [Void], Pointer [Void] ]                           => Int;
    affix 'user32',   'CreateMenu',                    []                                                           => Size_t;
    affix 'user32',   'CreatePopupMenu',               []                                                           => Size_t;
    affix 'user32',   'AppendMenuW',                   [ Size_t, ULong, Size_t, WString ]                           => Int;
    affix 'user32',   'SetMenu',                       [ Pointer [Void], Size_t ]                                   => Int;
    affix 'user32',   'DrawMenuBar',                   [ Pointer [Void] ]                                           => Int;
    affix 'user32',   'DestroyMenu',                   [Size_t]                                                     => Int;
    affix 'user32',   'TrackPopupMenuEx',              [ Size_t, UInt, Int, Int, Pointer [Void], Pointer [Void] ]   => Int;
    typedef OPENFILENAMEW => Struct [
        lStructSize => ULong,
        ( map { $_ => Pointer [Void] } qw[hwndOwner hInstance lpstrFilter lpstrCustomFilter] ),
        ( map { $_ => ULong } qw[nMaxCustFilter nFilterIndex] ),
        lpstrFile       => Pointer [Void],
        nMaxFile        => ULong,
        lpstrFileTitle  => Pointer [Void],
        nMaxFileTitle   => ULong,
        lpstrInitialDir => Pointer [Void],
        lpstrTitle      => Pointer [Void],
        Flags           => ULong,
        nFileOffset     => UShort,
        nFileExtension  => UShort,
        lpstrDefExt     => Pointer [Void],
        lCustData       => SSize_t,
        lpfnHook        => Pointer [Void],
        lpTemplateName  => Pointer [Void],
        pvReserved      => Pointer [Void],
        dwReserved      => ULong,
        FlagsEx         => ULong
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
        lpTemplateName => Pointer [Void]
    ];
    affix 'comdlg32', 'GetOpenFileNameW',      [ Pointer [ OPENFILENAMEW() ] ]                                                     => Int;
    affix 'comdlg32', 'GetSaveFileNameW',      [ Pointer [ OPENFILENAMEW() ] ]                                                     => Int;
    affix 'comdlg32', 'ChooseColorW',          [ Pointer [ CHOOSECOLORW() ] ]                                                      => Int;
    affix 'user32',   'MessageBoxW',           [ Pointer [Void], WString, WString, UInt ]                                          => Int;
    affix 'user32',   'GetMessageW',           [ Pointer [Void], Pointer [Void], UInt, UInt ]                                      => Int;
    affix 'user32',   'IsDialogMessageW',      [ Pointer [Void], Pointer [Void] ]                                                  => Int;
    affix 'user32',   'GetFocus',              []                                                                                  => Pointer [Void];
    affix 'user32',   'GetKeyState',           [Int]                                                                               => Short;
    affix 'user32',   'GetWindowWord',         [ Pointer [Void], Int ]                                                             => UShort;
    affix 'dwmapi',   'DwmSetWindowAttribute', [ Pointer [Void], UInt, Pointer [Void], UInt ]                                      => Int;
    affix 'dwmapi',   'DwmGetWindowAttribute', [ Pointer [Void], UInt, Pointer [Void], UInt ]                                      => Int;
    affix 'advapi32', 'RegOpenKeyExW',         [ Size_t, WString, ULong, ULong, Pointer [Void] ]                                   => Long;
    affix 'advapi32', 'RegQueryValueExW',      [ Size_t, WString, Pointer [Void], Pointer [Void], Pointer [Void], Pointer [Void] ] => Long;
    affix 'advapi32', 'RegCloseKey',           [Size_t]                                                                            => Long;
    typedef DWORDV => Struct [ v => ULong ];
    affix 'gdi32', 'SetTextColor',        [ Pointer [Void], ULong ] => ULong;
    affix 'gdi32', 'SetBkColor',          [ Pointer [Void], ULong ] => ULong;
    affix 'gdi32', 'CreateFontIndirectW', [ Pointer [Void] ] => Pointer [Void];
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
    typedef RECT          => Struct [ left => Int, top => Int, right => Int, bottom => Int ];
    typedef POINT         => Struct [ x    => Int, y   => Int ];
    typedef LVHITTESTINFO => Struct [ pt   => POINT(), flags => UInt, iItem => Int, iSubItem => Int ];
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
    affix 'user32', 'GetWindowTextLengthW',  [ Pointer [Void] ]                               => Int;
    affix 'user32', 'GetWindowTextW',        [ Pointer [Void], Pointer [Void], Int ]          => Int;
    affix 'user32', 'GetClientRect',         [ Pointer [Void], Pointer [Void] ]               => Int;
    affix 'user32', 'GetWindowRect',         [ Pointer [Void], Pointer [Void] ]               => Int;
    affix 'user32', 'AdjustWindowRectEx',    [ Pointer [ RECT() ], UInt, Int, UInt ]          => Int;
    affix 'user32', 'IsZoomed',              [ Pointer [Void] ]                               => Int;
    affix 'user32', 'IsIconic',              [ Pointer [Void] ]                               => Int;
    affix 'user32', 'GetDC',                 [ Pointer [Void] ]                               => Pointer [Void];
    affix 'user32', 'ReleaseDC',             [ Pointer [Void], Pointer [Void] ]               => Int;
    affix 'gdi32',  'GetStockObject',        [Int]                                            => Pointer [Void];
    affix 'gdi32',  'SelectObject',          [ Pointer [Void], Pointer [Void] ]               => Pointer [Void];
    affix 'gdi32',  'GetTextExtentPoint32W', [ Pointer [Void], WString, Int, Pointer [Void] ] => Int;
    affix 'gdi32',  'GetDeviceCaps',         [ Pointer [Void], Int ]                          => Int;
    affix 'gdi32',  'GetPixel',              [ Pointer [Void], Int, Int ]                     => ULong;
    typedef SIZE => Struct [ cx => Int, cy => Int ];
    typedef PAINTSTRUCT =>
        Struct [ hdc => Pointer [Void], fErase => Int, rcPaint => RECT(), fRestore => Int, fIncUpdate => Int, rgbReserved => Array [ UChar, 32 ] ];
    affix 'user32', 'BeginPaint',         [ Pointer [Void], Pointer [Void] ]                                      => Pointer [Void];
    affix 'user32', 'EndPaint',           [ Pointer [Void], Pointer [Void] ]                                      => Int;
    affix 'gdi32',  'CreateCompatibleDC', [ Pointer [Void] ]                                                      => Pointer [Void];
    affix 'gdi32',  'DeleteDC',           [ Pointer [Void] ]                                                      => Int;
    affix 'gdi32',  'BitBlt',             [ Pointer [Void], Int, Int, Int, Int, Pointer [Void], Int, Int, ULong ] => Int;
    typedef DRAWITEMSTRUCT => Struct [
        ctlType    => UInt,
        ctlID      => UInt,
        itemID     => UInt,
        itemAction => UInt,
        itemState  => UInt,
        hwndItem   => Size_t,
        hDC        => Pointer [Void],
        rcItem     => RECT(),
        itemData   => SSize_t
    ];
    affix 'user32', 'FillRect',         [ Pointer [Void], Pointer [Void], Pointer [Void] ]     => Int;
    affix 'user32', 'FrameRect',        [ Pointer [Void], Pointer [Void], Pointer [Void] ]     => Int;
    affix 'gdi32',  'CreateSolidBrush', [Size_t]                                               => Pointer [Void];
    affix 'gdi32',  'DeleteObject',     [ Pointer [Void] ]                                     => Int;
    affix 'gdi32',  'SetBkMode',        [ Pointer [Void], Int ]                                => Int;
    affix 'user32', 'DrawTextW',        [ Pointer [Void], WString, Int, Pointer [Void], UInt ] => Int;
    affix 'user32', 'DrawFocusRect',    [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'gdi32',  'CreatePen',        [ Int, Int, ULong ]                                    => Pointer [Void];
    affix 'gdi32',  'MoveToEx',         [ Pointer [Void], Int, Int, Pointer [Void] ]           => Int;
    affix 'gdi32',  'LineTo',           [ Pointer [Void], Int, Int ]                           => Int;
    affix 'gdi32',  'Ellipse',          [ Pointer [Void], Int, Int, Int, Int ]                 => Int;
    typedef INITCOMMONCONTROLSEX => Struct [ dwSize => ULong, dwICC => ULong ];
    affix 'comctl32', 'InitCommonControlsEx',        [ Pointer [ INITCOMMONCONTROLSEX() ] ]                 => Int;
    affix 'comctl32', 'ImageList_Create',            [ Int, Int, UInt, Int, Int ]                           => Pointer [Void];
    affix 'comctl32', 'ImageList_AddIcon',           [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'comctl32', 'ImageList_GetImageCount',     [ Pointer [Void] ]                                     => Int;
    affix 'comctl32', 'ImageList_Destroy',           [ Pointer [Void] ]                                     => Int;
    affix 'user32',   'DestroyIcon',                 [ Pointer [Void] ]                                     => Int;
    affix 'gdiplus',  'GdiplusStartup',              [ Pointer [Void], Pointer [Void], Pointer [Void] ]     => Int;
    affix 'gdiplus',  'GdipLoadImageFromFile',       [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'gdiplus',  'GdipGetImageWidth',           [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'gdiplus',  'GdipGetImageHeight',          [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'gdiplus',  'GdipCreateBitmapFromScan0',   [ Int, Int, Int, Int, Pointer [Void], Pointer [Void] ] => Int;
    affix 'gdiplus',  'GdipGetImageGraphicsContext', [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'gdiplus', 'GdipDrawImageRectRectI',
    [ Pointer [Void], Pointer [Void], Int, Int, Int, Int, Int, Int, Int, Int, Int, Pointer [Void], Pointer [Void], Pointer [Void] ] => Int;
    affix 'gdiplus', 'GdipCreateHICONFromBitmap',   [ Pointer [Void], Pointer [Void] ]                     => Int;
    affix 'gdiplus', 'GdipCreateHBITMAPFromBitmap', [ Pointer [Void], Pointer [Void], Size_t ]             => Int;
    affix 'gdiplus', 'GdipSetInterpolationMode',    [ Pointer [Void], Int ]                                => Int;
    affix 'gdiplus', 'GdipDisposeImage',            [ Pointer [Void] ]                                     => Int;
    affix 'gdiplus', 'GdipDeleteGraphics',          [ Pointer [Void] ]                                     => Int;
    affix 'gdiplus', 'GdipCreatePen1',              [ Size_t, Float, Int, Pointer [Void] ]                 => Int;
    affix 'gdiplus', 'GdipDeletePen',               [ Pointer [Void] ]                                     => Int;
    affix 'gdiplus', 'GdipSetSmoothingMode',        [ Pointer [Void], Int ]                                => Int;
    affix 'gdiplus', 'GdipDrawLineI',               [ Pointer [Void], Pointer [Void], Int, Int, Int, Int ] => Int;
    affix 'user32',  'FindWindowW',                 [ WString, WString ]                                   => Pointer [Void];
    affix 'user32',  'GetWindow',                   [ Pointer [Void], UInt ]                               => Pointer [Void];
    affix 'user32',  'GetClassNameW',               [ Pointer [Void], Pointer [Void], Int ]                => Int;
    affix 'user32',  'GetWindowLongW',              [ Pointer [Void], Int ]                                => Int;
    affix 'user32',  'GetClassLongPtrW',            [ Pointer [Void], Int ]                                => Size_t;
    affix 'user32',  'GetWindowThreadProcessId',    [ Pointer [Void], Pointer [UInt] ]                     => UInt;
    affix 'user32',  'GetSysColorBrush',            [Int]                                                  => Pointer [Void];
    typedef UDACCEL => Struct [ nSec => UInt, nInc => UInt ];
    my $icc   = malloc( sizeof( INITCOMMONCONTROLSEX() ) );
    my $icc_s = cast( $icc, INITCOMMONCONTROLSEX() );
    $icc_s->{dwSize} = sizeof( INITCOMMONCONTROLSEX() );
    $icc_s->{dwICC}  = 0x00000127;
    InitCommonControlsEx($icc);
    free($icc);
    #
    field $gui_font = GetStockObject(17);    # DEFAULT_GUI_FONT (17)
    ADJUST { }

    method init ($app_channel) {
        $self->_enable_dpi_awareness;
        $self->_enable_dark_theme;
        $channel = $app_channel;
        my $self_ref = $self;
        $wndproc_cb = sub ( $hwnd, $msg, $wparam, $lparam ) {
            my ( $ctl, $ret ) = $self_ref->_ctrl_msg( $hwnd, $msg, $wparam, $lparam );
            return $ret if $ctl;
            if ( $msg == 0x0081 ) {    # WM_NCCREATE
                if ( $allow_dark && $self_ref->uses_dark_mode ) {
                    $allow_dark->( $hwnd, 1 );
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
            }
            elsif ( $msg == 0x0002 ) {    # WM_DESTROY
                my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                if ($surface_id) {
                    delete $self_ref->surfaces->{$surface_id};
                    delete $self_ref->surface_by_hwnd->{$hwnd};
                }
                if ( scalar( keys %{ $self_ref->surfaces } ) == 0 ) {
                    $self_ref->channel->put( { type => 'QUIT' } );
                }
            }
            elsif ( $msg == 0x0010 ) {    # WM_CLOSE
                if ( my $cb = $self_ref->_get_close_request_handler ) {
                    return $cb->( $self_ref->surface_by_hwnd->{$hwnd} ) ? DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) : 0;
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
            }
            elsif ( $msg == 0x0100 ) {    # WM_KEYDOWN
                my $chord = $self_ref->_build_chord( $hwnd, $msg, $wparam, $lparam );
                if ( defined $chord ) {
                    my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                    $self_ref->channel->put( { type => 'KEY_CHORD', chord => $chord, surface => $surface_id } );
                }
                return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
            }
            elsif ( $msg == 0x0005 ) {    # WM_SIZE
                my $cw = $self_ref->_ux( $lparam & 0xFFFF );
                my $ch = $self_ref->_uy( ( $lparam >> 16 ) & 0xFFFF );
                $self_ref->channel->put( { type => 'RESIZE' } );
                my $cb = $self_ref->_get_resize_handler;
                if ($cb) {
                    my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                    $cb->( $surface_id, $cw, $ch );
                }
            }
            elsif ( $msg == 0x0231 ) {    # WM_ENTERSIZEMOVE
                $modal_timer = 1;
                SetTimer( $hwnd, 1, 16, undef );
            }
            elsif ( $msg == 0x0232 ) {    # WM_EXITSIZEMOVE
                $modal_timer = 0;
                KillTimer( $hwnd, 1 );
            }
            elsif ( $msg == 0x0113 ) {    # WM_TIMER
                if ( $wparam == 1 && $modal_timer ) {
                    my $pump = $self_ref->_get_modal_pump;
                    $pump->() if $pump;
                    return 0;
                }
            }
            elsif ( $msg == 0x0024 ) {    # WM_GETMINMAXINFO
                my $surface_id = $self_ref->surface_by_hwnd->{$hwnd};
                my $vn         = $surface_id ? $self_ref->surfaces->{$surface_id}{node} : undef;
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
            elsif ( $msg == 0x020A || $msg == 0x020E ) {    # WM_MOUSEWHEEL / WM_MOUSEHWHEEL
                my $axis   = $msg == 0x020E ? 'h' : 'v';
                my $target = $self_ref->_wheel_target( $axis, $lparam );
                if ($target) {
                    my $delta = ( ( $wparam >> 16 ) & 0xFFFF );
                    $delta = $delta >= 0x8000 ? $delta - 0x10000 : $delta;
                    $delta ||= 1;
                    my $steps = int( abs($delta) / 120 ) || 1;
                    my $code  = $delta > 0 ? 0 : 1;
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
        $wc->{hbrBackground} = $self->_scheme_brush( 6, '#202020' );
        $wc->{lpszClassName} = $win_class = 'UjiWindowClass' . ++$class_seq;
        RegisterClassExW($wndclass);
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
        $cv->{hbrBackground} = $self->_scheme_brush( 16, '#2D2D30' );
        $cv->{lpszClassName} = $viewport_class = 'UjiViewportClass' . ++$class_seq;
        $cv->{hCursor}       = LoadCursorW( undef, 32512 );
        RegisterClassExW($vclass);
        free($vclass);
        my $divider_proc = sub ( $hwnd, $msg, $wparam, $lparam ) {
            if ( $msg == 0x0201 ) {
                $self_ref->_divider_begin($hwnd);
                SetCapture($hwnd);
                return 0;
            }
            if ( $msg == 0x0202 ) {
                $self_ref->_divider_end($hwnd);
                SetCapture(undef);
                return 0;
            }
            if ( $msg == 0x0200 ) {
                $self_ref->_divider_drag($hwnd) if $self_ref->_divider_active($hwnd);
                return 0;
            }
            if ( $msg == 0x0020 ) {
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
        $cd->{hbrBackground} = $self->_scheme_brush( 18, '#3A3A3A' );
        $cd->{lpszClassName} = $divider_class = 'UjiDividerClass' . ++$class_seq;
        $cd->{hCursor}       = LoadCursorW( undef, 32512 );
        RegisterClassExW($dclass);
        free($dclass);
        my $prompt_proc = sub ( $hwnd, $msg, $wparam, $lparam ) {
            if ( $msg == 0x0111 ) {
                my $id = $wparam & 0xFFFF;
                if ( $id == 1 ) {
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
                if ( $id == 2 ) {
                    $self_ref->_set_prompt_value(undef);
                    $self_ref->_prompt_finish;
                    return 0;
                }
            }
            if ( $msg == 0x0010 ) {
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
        $cp->{hbrBackground} = $self->_scheme_brush( 0, '#202020' );
        $cp->{lpszClassName} = $prompt_class = 'UjiPromptClass' . ++$class_seq;
        $cp->{hCursor}       = LoadCursorW( undef, 32512 );
        RegisterClassExW($pclass);
        free($pclass);
        my $canvas_proc = sub ( $hwnd, $msg, $wparam, $lparam ) {
            if ( $msg == 0x000F ) {
                $self_ref->_paint_canvas($hwnd);
                return 0;
            }
            if ( $msg == 0x0014 ) {
                return 1;
            }
            return DefWindowProcW( $hwnd, $msg, $wparam, $lparam );
        };
        my $cclass = malloc( sizeof( WNDCLASSEXW() ) );
        my $cc     = cast( $cclass, WNDCLASSEXW() );
        $cc->{cbSize}        = sizeof( WNDCLASSEXW() );
        $cc->{style}         = 0x0003;
        $cc->{lpfnWndProc}   = $canvas_proc;
        $cc->{hInstance}     = undef;
        $cc->{hCursor}       = LoadCursorW( undef, 32512 );
        $cc->{hbrBackground} = $self->_scheme_brush( 16, '#2D2D30' );
        $cc->{lpszClassName} = $canvas_class = 'UjiCanvasClass' . ++$class_seq;
        RegisterClassExW($cclass);
        free($cclass);
    }

    method _build_chord ( $hwnd, $msg, $wparam, $lparam ) {
        my $vk = $wparam;
        my %mod;
        $mod{ctrl}  = 1 if GetKeyState(0x11) & 0x8000;
        $mod{shift} = 1 if GetKeyState(0x10) & 0x8000;
        $mod{alt}   = 1 if GetKeyState(0x12) & 0x8000;
        my $key;
        if ( $vk >= 0x41 && $vk <= 0x5A ) {
            $key = lc chr($vk);
        }
        elsif ( $vk >= 0x30 && $vk <= 0x39 ) {
            $key = chr($vk);
        }
        elsif ( $vk >= 0x70 && $vk <= 0x87 ) {
            $key = 'f' . ( $vk - 0x70 + 1 );
        }
        else {
            my %spec = (
                0x1B => 'esc',
                0x0D => 'enter',
                0x20 => 'space',
                0x09 => 'tab',
                0x08 => 'backspace',
                0x2E => 'delete',
                0x2D => 'insert',
                0x24 => 'home',
                0x23 => 'end',
                0x21 => 'pgup',
                0x22 => 'pgdn',
                0x25 => 'left',
                0x26 => 'up',
                0x27 => 'right',
                0x28 => 'down'
            );
            $key = $spec{$vk};
        }
        return undef unless defined $key;
        my $mods = join '+', map { $mod{$_} ? $_ : () } qw[ctrl alt shift];
        return $mods ? "$mods+$key" : $key;
    }

    method _ctrl_msg ( $hwnd, $msg, $wparam, $lparam ) {
        if ( $msg == 0x0113 ) {
            my $record = $self->_get_registry_record($wparam);
            if ( $record && $record->{node} && $record->{node}->type eq 'spinner' ) {
                my $frames = $record->{spin_frames};
                if ( ref $frames eq 'ARRAY' && @$frames && $record->{spin_armed} ) {
                    $record->{spin_idx} = ( ( $record->{spin_idx} // 0 ) + 1 ) % @$frames;
                    SendMessageW( $record->{hwnd}, 0x0170, $frames->[ $record->{spin_idx} ], 0 );
                }
                return ( 1, 0 );
            }
        }
        if ( $msg == 0x002B ) {
            my $dis = cast( $lparam, DRAWITEMSTRUCT() );
            if ($dis) {
                my $record = $self->_get_registry_by_hwnd( $dis->{hwndItem} );
                if ( $record && $record->{node} ) {
                    my $t = $record->{node}->type;
                    if ( $t eq 'color_button' ) {
                        $self->_draw_color_button( $record->{node}, $dis, $record );
                        return ( 1, 1 );
                    }
                    if ( $t eq 'button' ) {
                        $self->_draw_push_button( $record->{node}, $dis, $record );
                        return ( 1, 1 );
                    }
                    if ( $t eq 'checkbox' || $t eq 'radio' || $t eq 'toggle_switch' || $t eq 'toggle_button' ) {
                        $self->_draw_check_button( $record->{node}, $dis, $record );
                        return ( 1, 1 );
                    }
                }
            }
        }
        if ( $msg == 0x0111 ) {
            my $control_id  = $wparam & 0xFFFF;
            my $notify_code = ( $wparam >> 16 ) & 0xFFFF;
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
            if ( $notify_code == 0 && $menu_cmds->{$control_id} ) {
                my $route = $menu_cmds->{$control_id};
                my $item  = $route->{item};

                # Item-level on_click action (hashref or callback)
                if ( $item && $item->{on_click} ) {
                    my $cb     = $item->{on_click};
                    my $action = ref $cb eq 'HASH' ? $cb : $cb->( $item->{id} );
                    $self->channel->put($action) if $action;
                    return ( 1, 0 );
                }

                # Fallback to window/menu_bar level on_click
                if ( $route->{win_id} ) {
                    my $win_rec = $registry->{ $route->{win_id} };
                    if ($win_rec) {
                        my $win_node = $win_rec->{node};
                        my $mb_node  = $win_node && $win_node->can('menu_bar') ? $win_node->menu_bar : undef;
                        if ( $mb_node && $mb_node->can('on_click') && $mb_node->on_click ) {
                            my $item_id = $item ? $item->{id} : ( $win_rec->{menu_bar}{by_cmd}{$control_id}{id} // $control_id );
                            my $action  = $mb_node->on_click->($item_id);
                            $self->channel->put($action) if $action;
                        }
                    }
                }
                return ( 1, 0 );
            }
            my $record = $self->_get_registry_record($control_id);
            if ($record) {
                my $node = $record->{node};
                if ( $notify_code == 0 && $record->{search_clear} ) {
                    my $srec = $registry->{ $record->{search_id} };
                    if ($srec) {
                        my $snode = $srec->{node};
                        $suppress_events = 1;
                        SetWindowTextW( $srec->{hwnd}, '' );
                        $suppress_events = 0;
                        ShowWindow( $srec->{aux}, 0 );
                        SetFocus( $srec->{hwnd} );
                        if ( $snode && $snode->can('on_search') && $snode->on_search ) {
                            my $action = $snode->on_search->('');
                            $self->channel->put($action) if $action;
                        }
                    }
                    return ( 1, 0 );
                }
                if ( $notify_code == 0 && $node->type eq 'color_button' ) {
                    my $picked
                        = $self->color_picker( initial => defined $record->{hex} ? $record->{hex} : ( $node->color // '#000000' ), owner => $hwnd );
                    if ( defined $picked && $node->can('on_change') && $node->on_change ) {
                        $record->{hex} = $picked;
                        $self->channel->put( $node->on_change->($picked) );
                    }
                    return ( 1, 0 );
                }
                if ( $notify_code == 0 && $node->type eq 'radio' && $self->uses_dark_mode ) {
                    if ( my $grp = $self->_radio_group_for($record) ) {
                        $self->_apply_radio_group( $grp, $node->value );
                    }
                    else {
                        $record->{check} = 1;
                        InvalidateRect( $record->{hwnd}, undef, 1 );
                    }
                }
                if ( $notify_code == 0 && $node->can('on_click') && $node->on_click ) {
                    my $on_click = $node->on_click;
                    my $action   = ref $on_click eq 'HASH' ? $on_click : $on_click->();
                    $self->channel->put($action) if $action;
                }
                elsif ( $notify_code == 0 && ( $node->type eq 'checkbox' || $node->type eq 'toggle_switch' || $node->type eq 'toggle_button' ) ) {
                    my $checked;
                    if ( defined $record->{check} ) {
                        $record->{check} = $record->{check} ? 0 : 1;
                        $checked = $record->{check};
                        InvalidateRect( $record->{hwnd}, undef, 1 ) if $self->uses_dark_mode;
                    }
                    else {
                        $checked = ( SendMessageW( $record->{hwnd}, 0x00F0, 0, 0 ) // 0 ) ? 1 : 0;
                    }
                    if ( $node->on_toggle ) {
                        my $action_msg = $node->on_toggle->( $checked ? 1 : 0 );
                        $self->channel->put($action_msg) if $action_msg;
                    }
                }
                elsif ( $notify_code == 0 && $node->can('on_select') && $node->on_select ) {
                    my $action_msg = $node->on_select->( $node->value );
                    $self->channel->put($action_msg) if $action_msg;
                }
                elsif ( $notify_code == 0x0300 && $node->can('on_input') && $node->on_input ) {
                    return ( 1, DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) ) if $self->_is_suppressed;
                    my $text       = $self->_get_text( $record->{hwnd} );
                    my $action_msg = $node->on_input->($text);
                    $self->channel->put($action_msg) if $action_msg;
                }
                elsif ( $notify_code == 0x0005 && $node->type eq 'combo_box' && $node->on_input ) {
                    return ( 1, DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) ) if $self->_is_suppressed;
                    my $text       = $self->_get_text( $record->{hwnd} );
                    my $action_msg = $node->on_input->($text);
                    $self->channel->put($action_msg) if $action_msg;
                }
                elsif ( $notify_code == 0x0001 && ( $node->type eq 'combo_box' || $node->type eq 'list_box' ) && $node->on_select ) {
                    if ( $node->type eq 'list_box' && $node->multiple ) {
                        my $cnt = SendMessageW( $record->{hwnd}, 0x0190, 0, 0 );
                        my @values;
                        if ( $cnt > 0 ) {
                            my $buf = malloc( $cnt * 4 );
                            SendMessageW( $record->{hwnd}, 0x0191, $cnt, Affix::address($buf) );
                            my @idx = unpack( "V$cnt", Affix::raw( $buf, $cnt * 4 ) );
                            free($buf);
                            @values = map { $node->options->[$_]{value} // $node->options->[$_]{label} // '' } @idx;
                        }
                        my $action_msg = $node->on_select->( \@values );
                        $self->channel->put($action_msg) if $action_msg;
                    }
                    else {
                        my $is_combo = $node->type eq 'combo_box';
                        my $idx      = SendMessageW( $record->{hwnd}, $is_combo ? 0x0147 : 0x0188, 0, 0 );
                        my $value;
                        if ( $idx >= 0 ) {
                            $value = $node->options->[$idx]{value} // $node->options->[$idx]{label} // '';
                        }
                        elsif ( $is_combo && $node->editable ) {
                            $value = $self->_get_text( $record->{hwnd} );
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
        elsif ( $msg == 0x0114 || $msg == 0x0115 ) {
            my $axis = $msg == 0x0114 ? 'h' : 'v';
            my $sbid = $self->_registry_id_by_key( $lparam, "aux_$axis" );
            if ($sbid) {
                $self->_scrollbar_event( $sbid, $axis, $wparam );
                return ( 1, 0 );
            }
            my $record = $self->_get_registry_by_hwnd($lparam);
            if ( $record && $record->{node} && $record->{node}->type eq 'slider' ) {
                my $node = $record->{node};
                if ( $node->can('on_change') && $node->on_change ) {
                    my $pos     = SendMessageW( $lparam, 0x0400, 0, 0 );
                    my $sub_msg = $node->on_change->($pos);
                    $self->channel->put($sub_msg) if $sub_msg;
                }
                return ( 1, 0 );
            }
            $record = $self->_get_registry_by_aux($lparam);
            if ($record) {
                my $node = $record->{node};
                my $pos  = SendMessageW( $lparam, 0x0472, 0, 0 );
                $self->_spin_sync_text( $record->{hwnd}, $pos );
                if ( $node->can('on_change') && $node->on_change ) {
                    my $sub_msg = $node->on_change->($pos);
                    $self->channel->put($sub_msg) if $sub_msg;
                }
                return ( 1, 0 );
            }
            return ( 0, undef );
        }
        elsif ( $msg == 0x0138 || $msg == 0x0133 || $msg == 0x0135 || $msg == 0x0134 ) {
            my $child_hwnd = $lparam;
            my $record     = $self->_get_registry_by_hwnd($child_hwnd);
            my $node       = $record ? $record->{node} : undef;
            my $hdc        = $wparam;
            if ( $self->uses_dark_mode ) {
                my $fg   = ( $node && $node->color ) ? $self->_parse_color( $node->color ) : 0x00E6E6E6;
                my $fill = ( $node && $node->background ) ? $node->background : ( $msg == 0x0133 || $msg == 0x0134 ) ? '#2D2D30' : '#202020';
                SetTextColor( $hdc, $fg );
                SetBkColor( $hdc, $self->_parse_color($fill) );
                my $brush = $self->_ctl_brush($fill);
                return ( 1, $brush ? Affix::address($brush) : 0 );
            }
            if ($node) {
                SetTextColor( $hdc, $self->_parse_color( $node->color ) ) if $node->color;
                if ( $node->background ) {
                    SetBkColor( $hdc, $self->_parse_color( $node->background ) );
                    my $brush = $self->_ctl_brush( $node->background );
                    return ( 1, $brush ? Affix::address($brush) : 0 );
                }
            }
            my $sys_brush = GetSysColorBrush( $msg == 0x0133 || $msg == 0x0134 ? 5 : 15 );
            return ( 1, $sys_brush ? Affix::address($sys_brush) : 0 );
        }
        elsif ( $msg == 0x004E ) {
            return ( 0, undef ) unless $lparam;
            my $nm   = cast( $lparam, NMHDR() );
            my $from = $nm->{hwndFrom} ? Affix::address( $nm->{hwndFrom} ) : 0;
            return ( 0, undef ) unless $from;
            my $id     = $self->_registry_id_by_key( $from, 'hwnd' ) or return ( 0, undef );
            my $record = $registry->{$id}                            or return ( 0, undef );
            my $node   = $record->{node}                             or return ( 0, undef );
            if ( $node->type eq 'tab_panel' && $nm->{code} == -551 ) {
                my $idx = SendMessageW( $from, 0x130B, 0, 0 );
                $record->{index} = $idx;
                $self->_apply_tab($id);
                if ( $node->can('on_select') && $node->on_select ) {
                    my $action = $node->on_select->($idx);
                    $self->channel->put($action) if $action;
                }
                return ( 1, 0 );
            }
            if ( $node->type eq 'date_picker' && $nm->{code} == -759 ) {
                my $raw   = Affix::raw( $lparam, 44 );
                my $flags = unpack( 'L<', substr( $raw, 24, 4 ) );
                my ( $y, $m, undef, $d ) = unpack( 'v4', substr( $raw, 28, 8 ) );
                my $iso    = ( $flags == 1 || !$d )                      ? ''                       : sprintf( '%04d-%02d-%02d', $y, $m, $d );
                my $action = $node->can('on_change') && $node->on_change ? $node->on_change->($iso) : undef;
                $self->channel->put($action) if $action;
                return ( 1, 0 );
            }
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
            if ( $node->type eq 'list_view' && $nm->{code} == -108 ) {
                my $lv = $record->{listview};
                if ( $lv && $node->sortable ) {
                    my $raw = Affix::raw( $lparam, 40 );
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
            if ( $node->type eq 'list_view' && $nm->{code} == -101 ) {
                return ( 1, 0 ) if $self->_is_suppressed;
                my $raw = Affix::raw( $lparam, 64 );
                my $iit = unpack( 'l<', substr( $raw, 24, 4 ) );
                my $nst = unpack( 'L<', substr( $raw, 32, 4 ) );
                return ( 1, 0 ) unless $nst & 0x0002;
                return ( 1, 0 ) unless $record->{listview};
                my $selected;
                if ( $node->multiple ) {
                    my $count = SendMessageW( $from, 0x1004, 0, 0 );
                    my @values;
                    for my $i ( 0 .. $count - 1 ) {
                        my $st = SendMessageW( $from, 0x102C, $i, 0x0002 );
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

            # Custom draw for ListView (subtle dark gridlines & cell borders)
            if ( $node->type eq 'list_view' && $nm->{code} == -12 ) {
                return $self->_handle_list_view_custom_draw( $record, $lparam );
            }
            return ( 1, 0 );
        }
        if ( $msg == 0x007B ) {    # WM_CONTEXTMENU
            my $target_hwnd = $wparam;
            my $record      = $self->_get_registry_by_hwnd($target_hwnd);
            if ( $record && $record->{node} && $record->{node}->can('context_menu') && $record->{node}->context_menu ) {
                $self->_show_context_menu( $record, $lparam );
                return ( 1, 0 );
            }
        }
        return ( 0, undef );
    }

    method _get_text ($hwnd) {
        my $len = GetWindowTextLengthW($hwnd);
        return '' if $len <= 0;
        my $buf       = malloc( ( $len + 1 ) * sizeof(WChar) );
        my $copied    = GetWindowTextW( $hwnd, $buf, $len + 1 );
        my $raw_bytes = Affix::raw( $buf, $copied * sizeof(WChar) );
        free($buf);
        return $self->_to_lf( Encode::decode( 'UTF-16LE', $raw_bytes ) );
    }

    method _to_crlf ($string) {
        $string //= '';
        $string =~ s/\r?\n/\r\n/g;
        return $string;
    }

    method _to_lf ($string) {
        $string =~ s/\r\n/\n/g;
        return $string;
    }

    method _nz ($s) {
        $s //= '';
        return $s if utf8::is_utf8($s);
        if ( eval { utf8::decode($s); 1 } ) {
            return $s;
        }
        utf8::upgrade($s);
        return $s;
    }

    method _clamp_to_range ( $vnode, $value ) {
        my $min = defined $vnode->min ? $vnode->min : 0;
        my $max = defined $vnode->max ? $vnode->max : 100;
        $value = $min if $value < $min;
        $value = $max if $value > $max;
        return $value;
    }

    sub _parse_color ( $self, $hex ) {
        $hex =~ s/^#//;
        my $rgb = hex $hex;
        return ( ( $rgb & 0xFF ) << 16 ) | ( $rgb & 0x00FF00 ) | ( ( $rgb >> 16 ) & 0xFF );
    }

    method _scheme_brush ( $sys_index, $dark_hex ) {
        return cast( $sys_index, Pointer [Void] ) unless $self->uses_dark_mode;
        return $self->_get_brush($dark_hex);
    }

    method _get_brush ($hex) {
        return undef unless defined $hex;
        return $brush_cache->{$hex} if $brush_cache->{$hex};
        my $brush = CreateSolidBrush( $self->_parse_color($hex) );
        $brush_cache->{$hex} = $brush if $brush;
        return $brush;
    }

    method _ctl_brush ($hex) {
        return $self->_get_brush($hex);
    }

    method _get_font ( $name = undef, $size = undef ) {
        $name //= 'Segoe UI';
        $size //= 9;
        my $key = "$name|$size";
        return $font_cache->{$key} if $font_cache->{$key};

        # MUST use calloc to zero-initialize the 92-byte LOGFONTW struct
        my $lf_ptr = calloc( 1, sizeof( LOGFONTW() ) );
        my $lf     = cast( $lf_ptr, LOGFONTW() );
        my $height = -int( $size * $self->_dpi / 72 );
        $lf->{lfHeight}         = $height;
        $lf->{lfWeight}         = 400;       # FW_NORMAL
        $lf->{lfCharSet}        = 1;         # DEFAULT_CHARSET
        $lf->{lfOutPrecision}   = 4;         # OUT_TT_PRECIS
        $lf->{lfQuality}        = 5;         # CLEARTYPE_QUALITY
        $lf->{lfPitchAndFamily} = 0x12;      # FF_SWISS | VARIABLE_PITCH
        my $wide_name = Encode::encode( 'UTF-16LE', $self->_nz($name) ) . "\x00\x00";
        my $face      = ptr_add( $lf_ptr, offsetof( LOGFONTW(), 'lfFaceName' ) );
        memcpy( $face, $wide_name, CORE::length($wide_name) );
        my $hfont = CreateFontIndirectW($lf_ptr);
        free($lf_ptr);
        $font_cache->{$key} = $hfont if $hfont;
        return $hfont;
    }

    method _gdi_colorref ($hex) {
        $hex //= '#000000';
        return 0 unless $hex =~ /#?([0-9a-fA-F]{6})/;
        my $r = hex( substr( $1, 0, 2 ) );
        my $g = hex( substr( $1, 2, 2 ) );
        my $b = hex( substr( $1, 4, 2 ) );
        return ( $b << 16 ) | ( $g << 8 ) | $r;
    }

    method _draw_color_button ( $node, $di, $record ) {
        my $hdc = $di->{hDC} or return;
        my $hex = defined $record->{hex} ? $record->{hex} : ( $node->color // '#000000' );
        $record->{hex} = $hex;
        my $r        = $di->{rcItem};
        my $sel      = ( $di->{itemState} & 0x0001 ) ? 1 : 0;
        my $disabled = ( $di->{itemState} & 0x0004 ) ? 1 : 0;
        my $focus    = ( $di->{itemState} & 0x0010 ) ? 1 : 0;
        my $sw       = 16;
        my $sh       = $r->{bottom} - $r->{top} - ( $sel ? 2 : 0 );
        $sh = 16 if $sh > 16;
        $sh = 4  if $sh < 4;
        my $sx    = $r->{left} + 3 + $sel;
        my $sy    = $r->{top} + ( ( $r->{bottom} - $r->{top} - $sh ) / 2 ) + $sel;
        my $brush = CreateSolidBrush( $disabled ? $self->_gdi_colorref('#B8B8B8') : $self->_gdi_colorref($hex) );
        my $rp1   = malloc( sizeof( RECT() ) );
        my $r1    = cast( $rp1, RECT() );
        ( $r1->{left}, $r1->{top}, $r1->{right}, $r1->{bottom} ) = ( $sx, $sy, $sx + $sw, $sy + $sh );
        FillRect( $hdc, $rp1, $brush );
        DeleteObject($brush);

        unless ($disabled) {
            my $rp2 = malloc( sizeof( RECT() ) );
            my $r2  = cast( $rp2, RECT() );
            ( $r2->{left}, $r2->{top}, $r2->{right}, $r2->{bottom} ) = ( $sx, $sy, $sx + $sw, $sy + $sh );
            FrameRect( $hdc, $rp2, GetStockObject(4) );
            free($rp2);
        }
        if ( $node->show_hex ) {
            my $hfont = $self->_get_font( $node->font, $node->font_size );
            my $old   = SelectObject( $hdc, $hfont );
            SetBkMode( $hdc, 1 );
            SetTextColor( $hdc, $disabled ? 0x00808080 : 0x00000000 );
            my $tx = $sx + $sw + 6 + $sel;
            my $tp = malloc( sizeof( RECT() ) );
            my $tr = cast( $tp, RECT() );
            ( $tr->{left}, $tr->{top}, $tr->{right}, $tr->{bottom} ) = ( $tx, $r->{top} + $sel, $r->{right} - 3, $r->{bottom} + $sel );
            DrawTextW( $hdc, $self->_nz($hex), -1, $tp, 0x0824 );
            free($tp);
            SelectObject( $hdc, $old ) if $old;
        }
        free($rp1);
        if ($focus) {
            my $fp = malloc( sizeof( RECT() ) );
            my $fr = cast( $fp, RECT() );
            ( $fr->{left}, $fr->{top}, $fr->{right}, $fr->{bottom} ) = ( $r->{left}, $r->{top}, $r->{right}, $r->{bottom} );
            DrawFocusRect( $hdc, $fp );
            free($fp);
        }
    }

    method _draw_check_button ( $node, $di, $record ) {
        my $hdc      = $di->{hDC} or return;
        my $r        = $di->{rcItem};
        my $sel      = ( $di->{itemState} & 0x0001 ) ? 1                : 0;
        my $disabled = ( $di->{itemState} & 0x0004 ) ? 1                : 0;
        my $focus    = ( $di->{itemState} & 0x0010 ) ? 1                : 0;
        my $checked  = defined $record->{check}      ? $record->{check} : ( ( SendMessageW( $di->{hwndItem}, 0x00F0, 0, 0 ) // 0 ) ? 1 : 0 );
        my $box      = 13;
        my $bx       = $r->{left} + 3 + $sel;
        my $by       = $r->{top} + int( ( ( $r->{bottom} - $r->{top} ) - $box ) / 2 ) + $sel;
        my $is_radio = $node->type eq 'radio';
        my $glyph    = $disabled ? '#6A6A6A' : defined $node->color ? $node->color : '#5CA8FF';
        my $face     = CreateSolidBrush( $self->_gdi_colorref( $disabled ? '#1F1F24' : ( $node->background // '#2D2D30' ) ) );
        my $border   = CreateSolidBrush( $self->_gdi_colorref( $disabled ? '#3A3A3A' : '#5A5A5A' ) );
        my $rp       = malloc( sizeof( RECT() ) );
        my $rr       = cast( $rp, RECT() );
        ( $rr->{left}, $rr->{top}, $rr->{right}, $rr->{bottom} ) = ( $bx, $by, $bx + $box, $by + $box );

        if ($is_radio) {
            my $old = SelectObject( $hdc, GetStockObject(8) );
            SelectObject( $hdc, $border );
            Ellipse( $hdc, $bx, $by, $bx + $box, $by + $box );
            SelectObject( $hdc, $face );
            Ellipse( $hdc, $bx + 2, $by + 2, $bx + $box - 2, $by + $box - 2 );
            if ($checked) {
                my $g = CreateSolidBrush( $self->_gdi_colorref($glyph) );
                SelectObject( $hdc, $g );
                Ellipse( $hdc, $bx + 4, $by + 4, $bx + $box - 3, $by + $box - 3 );
                DeleteObject($g);
            }
            SelectObject( $hdc, $old );
        }
        else {
            FillRect( $hdc, $rp, $face );
            FrameRect( $hdc, $rp, $border );
            if ($checked) {
                my $pen = CreatePen( 0, 2, $self->_gdi_colorref($glyph) );
                my $old = SelectObject( $hdc, $pen );
                MoveToEx( $hdc, $bx + 2, $by + 7, undef );
                LineTo( $hdc, $bx + 5,  $by + 10 );
                LineTo( $hdc, $bx + 11, $by + 3 );
                SelectObject( $hdc, $old );
                DeleteObject($pen);
            }
        }
        free($rp);
        DeleteObject($face);
        DeleteObject($border);
        my $label = $node->label // '';
        if ( CORE::length($label) ) {
            my $hfont = $self->_get_font( $node->font, $node->font_size );
            my $old   = SelectObject( $hdc, $hfont ) if $hfont;
            SetBkMode( $hdc, 1 );
            SetTextColor( $hdc, $self->_gdi_colorref( $disabled ? '#9E9E9E' : ( defined $node->color ? $node->color : '#E6E6E6' ) ) );
            my $tp = malloc( sizeof( RECT() ) );
            my $tr = cast( $tp, RECT() );
            ( $tr->{left}, $tr->{top}, $tr->{right}, $tr->{bottom} ) = ( $bx + $box + 5, $r->{top} + $sel, $r->{right} - 3, $r->{bottom} + $sel );
            DrawTextW( $hdc, $self->_nz($label), -1, $tp, 0x0824 );
            free($tp);
            SelectObject( $hdc, $old ) if $old;
        }
        if ($focus) {
            my $fp = malloc( sizeof( RECT() ) );
            my $fr = cast( $fp, RECT() );
            ( $fr->{left}, $fr->{top}, $fr->{right}, $fr->{bottom} ) = ( $r->{left}, $r->{top}, $r->{right}, $r->{bottom} );
            DrawFocusRect( $hdc, $fp );
            free($fp);
        }
    }

    method _radio_group_for ($record) {
        my $node = $record->{node} or return;
        for my $id ( keys %$registry ) {
            my $g = $registry->{$id} or next;
            next unless $g->{node} && $g->{node}->type eq 'radio_group';
            for my $kid ( @{ $g->{node}->children } ) {
                return $g if $kid->id eq $node->id;
            }
        }
        return;
    }

    method _apply_radio_group ( $grp, $value ) {
        for my $child ( @{ $grp->{node}->children } ) {
            my $cr = $registry->{ $child->id } or next;
            my $on = ( $child->value eq $value ) ? 1 : 0;
            $cr->{check} = $on;
            SendMessageW( $cr->{hwnd}, 0x00F1, $on, 0 );
            if ( $self->uses_dark_mode ) {
                InvalidateRect( $cr->{hwnd}, undef, 1 );
            }
        }
    }

    method recreate_node ( $old_id, $new_node ) {
        my $old    = $registry->{$old_id} or return;
        my $parent = $old->{parent_hwnd} // $main_hwnd;
        if ( my $cmd = $old->{search_clear_id} ) {
            delete $registry->{$cmd};
        }
        DestroyWindow( $old->{aux} )       if $old->{aux};
        DestroyWindow( $old->{icon_hwnd} ) if $old->{icon_hwnd};
        DestroyWindow( $old->{hwnd} )      if $old->{hwnd};
        $new_node->set_id($old_id);
        $self->_mount_node( $new_node, $parent );
        if ( $registry->{$old_id} && $registry->{$old_id}{hwnd} ) {
            SetWindowPos( $registry->{$old_id}{hwnd}, undef, $new_node->bx, $new_node->by, $new_node->bw, $new_node->bh, 0x0004 );
        }
    }

    method _find_window ($title) {
        return FindWindowW( $win_class, $self->_nz($title) );
    }

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

    method _apply_overlay ($node) {
        return unless $node && $node->can('children');
        $self->_raise_layer($_) for @{ $node->children };
    }

    method _raise_layer ($node) {
        return unless $node;
        my $r = $self->_get_registry_record( $node->id );
        if ( $r && $r->{hwnd} ) {
            SetWindowPos( $r->{hwnd}, cast( 0, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );
            return;
        }
        $self->_raise_layer($_) for @{ $node->children // [] };
    }

    method _get_class ($hwnd) {
        my $buf = malloc( 256 * sizeof(WChar) );
        my $n   = GetClassNameW( $hwnd, $buf, 256 );
        my $raw = Affix::raw( $buf, $n * sizeof(WChar) );
        free($buf);
        return Encode::decode( 'UTF-16LE', $raw );
    }

    method _get_style ($hwnd) {
        return GetWindowLongW( $hwnd, -16 );
    }

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
        my $packed = SendMessageW( $hwnd, 0x0140, 0, 0 );
        return ( ( $packed & 0xFFFF ), ( $packed >> 16 ) & 0xFFFF );
    }

    method _get_registry_record ($id) {
        return $registry->{$id} // $registry->{ $cid_to_id->{$id} // '' };
    }

    method _get_registry_by_hwnd ($hwnd) {
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless defined $rec->{hwnd};
            return $rec if $rec->{hwnd} == $hwnd;
        }
        return undef;
    }

    method _get_registry_by_aux ($hwnd) {
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id};
            next unless defined $rec->{aux};
            return $rec if $rec->{aux} == $hwnd;
        }
        return undef;
    }
    method _is_mounted () { $main_hwnd ? 1 : 0 }
    method set_resize_handler ($cb) { $on_resize     = $cb; $self }
    method set_modal_pump     ($cb) { $on_modal_pump = $cb; $self }

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };
        if ( $node->type eq 'window' ) {
            $main_vnode = $node;
            $surfaces->{ $node->id }{node} = $node if exists $surfaces->{ $node->id };
        }
    }

    method mount ($vtree) {
        my $surface_id = $vtree->id;
        $main_vnode //= $vtree;
        my $style = $vtree->resizable ? 0x10CF0000 : 0x10CB0000;
        my $hwnd  = CreateWindowExW(
            0,      $win_class,      $self->_nz( $vtree->title ),
            $style, $self->_sx(100), $self->_sy(100),
            $self->_sx( $vtree->w ),
            $self->_sy( $vtree->h ),
            undef, 0, undef, undef
        );
        $self->_frame_dark($hwnd) if $self->uses_dark_mode;
        $self->_theme_control($hwnd);
        $registry->{ $vtree->id } = { hwnd => $hwnd, node => $vtree, surface => $surface_id };
        $surfaces->{$surface_id}  = { hwnd => $hwnd, node => $vtree, records => {} };
        $surface_by_hwnd->{$hwnd} = $surface_id;
        $main_hwnd //= $hwnd;
        $self->_mount_menu_bar( $vtree->id ) if $vtree->menu_bar;
        my ( $cw, $ch ) = $self->_get_client_size($hwnd);
        $vtree->set_bounds( 0, 0, $cw, $ch );

        if ( $vtree->centered ) {
            $self->_set_window_outer( $hwnd, $vtree->w, $vtree->h, 'center' );
            my ( $nw, $nh ) = $self->_get_client_size($hwnd);
            $vtree->set_bounds( 0, 0, $nw, $nh );
        }
        SetWindowPos( $hwnd, $vtree->topmost ? -1 : -2, 0, 0, 0, 0, 0x0003 ) if $vtree->topmost;
        my $show_style = $vtree->maximized && !$self->_has_size_constraints($vtree) ? 3 : $vtree->minimized ? 2 : 5;
        ShowWindow( $hwnd, $show_style );
        UpdateWindow($hwnd);
    }

    method unmount ($vtree) {
        my $surface_id = $vtree->id;
        my $surface    = $surfaces->{$surface_id};
        if ( $surface && $surface->{hwnd} ) {
            if ( my $mrec = $registry->{$surface_id}{menu_bar} ) {
                for my $cmd ( keys %{ $mrec->{by_cmd} } ) {
                    delete $menu_cmds->{$cmd};
                }
                DestroyMenu( $mrec->{hmenu} ) if $mrec->{hmenu};
            }
            DestroyWindow( $surface->{hwnd} );
            delete $surface_by_hwnd->{ $surface->{hwnd} };
            delete $surfaces->{$surface_id};
            delete $registry->{$surface_id};
        }
    }

    method _frame_size_for_client ( $cw, $ch ) {
        ( $cw, $ch ) = ( $self->_sx($cw), $self->_sy($ch) );
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

    method _has_size_constraints ($node) {
        return $node->can('min_w') && ( $node->min_w || $node->min_h || $node->max_w || $node->max_h );
    }

    method _set_window_outer ( $hwnd, $cw, $ch, $mode = 'none' ) {
        ( $cw, $ch ) = ( $self->_sx($cw), $self->_sy($ch) );
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

    method _enable_dpi_awareness () {
        return if $dpi_aware;
        $dpi_aware = 1;
        if ( defined &SetProcessDpiAwarenessContext ) {
            return if SetProcessDpiAwarenessContext(-4) != 0;
        }
        SetProcessDPIAware();
    }
    my @theme_classes = qw[
        SCROLLBAR SysTabControl32 COMBOBOX BUTTON EDIT
        msctls_trackbar32 msctls_updown32 msctls_progress32
        ToolbarWindow32 msctls_statusbar32 tooltips_class32
    ];

    method _theme_control ($hwnd) {
        return unless $hwnd && $self->uses_dark_mode;
        my $buf = malloc( 128 * 2 );
        my $n   = GetClassNameW( $hwnd, $buf, 128 );
        my $cls = $n > 0 ? decode( 'UTF-16LE', Affix::raw( $buf, $n * 2 ) ) : '';
        free($buf);
        return unless grep { $_ eq $cls } @theme_classes;
        SetWindowTheme( $hwnd, 'DarkMode_Explorer', undef );
    }

    method _enable_dark_theme () {
        return unless $self->uses_dark_mode;
        return if $dark_theme;
        $dark_theme = 1;
        my $theme_dll = LoadLibraryW('uxtheme');
        return unless $theme_dll;
        my $pref  = GetProcAddress( $theme_dll, 135 );
        my $allow = GetProcAddress( $theme_dll, 133 );
        my $flush = GetProcAddress( $theme_dll, 136 );

        if ($pref) {
            affix undef, [ $pref => 'ujidark_set_pref' ], [Int] => Int;
            $set_pref = \&ujidark_set_pref;
        }
        if ($allow) {
            affix undef, [ $allow => 'ujidark_allow_win' ], [ Int, Int ] => Int;
            $allow_dark = \&ujidark_allow_win;
        }
        if ($flush) {
            affix undef, [ $flush => 'ujidark_flush_menu' ], [] => Void;
            $flush_menu = \&ujidark_flush_menu;
        }
        $set_pref->(1)  if $set_pref;
        $flush_menu->() if $flush_menu;
    }

    method _dpi () {
        return $dpi        if defined $dpi;
        return $dpi_detect if defined $dpi_detect;
        my $dc   = GetDC(0);
        my $logp = $dc ? GetDeviceCaps( $dc, 88 ) : 96;
        ReleaseDC( 0, $dc ) if $dc;
        return $dpi_detect = $logp || 96;
    }
    method _sx ($v) { return int( $v * $self->_dpi / 96 + 0.5 ) }
    method _sy ($v) { return int( $v * $self->_dpi / 96 + 0.5 ) }
    method _ux ($v) { return int( $v * 96 / $self->_dpi + 0.5 ) }
    method _uy ($v) { return int( $v * 96 / $self->_dpi + 0.5 ) }

    method uses_dark_mode () {
        return $dark_mode   if defined $dark_mode;
        return $dark_detect if defined $dark_detect;
        my $kptr = malloc(8);
        my $ret  = RegOpenKeyExW( 0x80000001, 'Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize', 0, 0x20019, $kptr );
        return $dark_detect = 0 if $ret != 0;
        my $hkey = unpack( 'Q<', Affix::raw( $kptr, 8 ) );
        free($kptr);
        my $vptr = malloc( sizeof( DWORDV() ) );
        my $lptr = malloc(4);
        memcpy( $lptr, pack( 'l<', 4 ), 4 );
        my $q = RegQueryValueExW( $hkey, 'AppsUseLightTheme', undef, undef, $vptr, $lptr );
        RegCloseKey($hkey);
        my $light = $q == 0 ? unpack( 'L<', Affix::raw( $vptr, 4 ) ) : 1;
        free($vptr);
        free($lptr);
        return $dark_detect = ( $light == 1 ? 0 : 1 );
    }

    method _frame_dark ($hwnd) {
        my $val   = pack( 'l<', 1 );
        my $round = pack( 'l<', 2 );
        my $mica  = pack( 'l<', 2 );
        DwmSetWindowAttribute( $hwnd, 20, $val,   4 );
        DwmSetWindowAttribute( $hwnd, 33, $round, 4 );
        DwmSetWindowAttribute( $hwnd, 38, $mica,  4 );
    }

    method _ensure_tooltip () {
        return $tooltip_hwnd if $tooltip_hwnd;
        $tooltip_hwnd = CreateWindowExW( 0, 'tooltips_class32', undef, 0x80000003, 0, 0, 0, 0, $main_hwnd, 0, undef, undef );
        $self->_theme_control($tooltip_hwnd);
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
            $ti->{lpszText} = $self->_nz($text);
            SendMessageW( $tip, 0x0432, 0, Affix::address($ti_ptr) );
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
        my ( $w, $h ) = ( $self->_ux( $r->{right} - $r->{left} ), $self->_uy( $r->{bottom} - $r->{top} ) );
        free($rect);
        return ( $w, $h );
    }

    method measure_text ( $text, $font_hwnd = $main_hwnd ) {
        my $dc = GetDC($font_hwnd);
        return ( 0, 0 ) unless $dc;
        SelectObject( $dc, $gui_font );
        my $buf = malloc( sizeof( SIZE() ) );
        my $sz  = cast( $buf, SIZE() );
        $text = $self->_nz( $text // '' );
        GetTextExtentPoint32W( $dc, $text, length $text, $buf );
        my ( $w, $h ) = ( $self->_ux( $sz->{cx} ), $self->_uy( $sz->{cy} ) );
        free($buf);
        ReleaseDC( $font_hwnd, $dc );
        return ( $w, $h );
    }

    method poll_events () {
        my $msg_ptr = malloc(48);
        while ( PeekMessageW( $msg_ptr, undef, 0, 0, 1 ) ) {
            TranslateMessage($msg_ptr);
            no warnings 'uninitialized';
            DispatchMessageW($msg_ptr);
        }
        free($msg_ptr);
        $self->_repaint_active_spin_arrows;
        $self->_sync_column_orders;
        $self->_track_focus;
    }

    method _track_focus () {
        my $focused = GetFocus() // 0;
        return if $focus_last == $focused;
        my $prev = $focus_last;
        $focus_last = $focused;
        if ($prev) {
            if ( my $prev_id = $self->_id_by_hwnd($prev) ) {
                $channel->put( { type => 'BLUR', blur_id => $prev_id } );
            }
        }
        if ($focused) {
            if ( my $id = $self->_id_by_hwnd($focused) ) {
                $channel->put( { type => 'FOCUS', focus_id => $id } );
            }
        }
    }

    method _id_by_hwnd ($hwnd) {
        return unless $hwnd;
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id} or next;
            next unless defined $rec->{hwnd};
            return $id if $rec->{hwnd} == $hwnd;
            return $id if defined $rec->{aux} && $rec->{aux} == $hwnd;
        }
        for my $surface_hwnd ( keys %$surface_by_hwnd ) {
            return $surface_by_hwnd->{$surface_hwnd} if $surface_hwnd == $hwnd;
        }
        return undef;
    }

    method _mount_node ( $vnode, $parent_hwnd ) {
        my ( $class, $style, $initial_text );
        if ( $vnode->type eq 'button' ) {
            $class        = 'BUTTON';
            $style        = 0x54000000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'color_button' ) {
            $class        = 'BUTTON';
            $style        = 0x5401000B;
            $initial_text = '';
        }
        elsif ( $vnode->type eq 'text' || $vnode->type eq 'status_text' ) {
            $class = 'STATIC';
            $style = 0x54000000;
            $style |= $vnode->align eq 'center' ? 0x0001 : $vnode->align eq 'right' ? 0x0002 : 0x0000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text_input' ) {
            $class        = 'EDIT';
            $style        = 0x54800080;
            $style        = 0x54A10044 if $vnode->multiline;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'multiline_text' ) {
            $class        = 'EDIT';
            $style        = 0x54A10044;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'password' ) {
            $class        = 'EDIT';
            $style        = 0x548000A0;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'search_input' ) {
            $class        = 'EDIT';
            $style        = 0x54800080;
            $initial_text = $self->_to_crlf( $vnode->value // '' );
        }
        elsif ( $vnode->type eq 'slider' ) {
            $class = 'msctls_trackbar32';
            $style = 0x54000001 | ( $vnode->orientation eq 'vertical' ? 0x0080 : 0x0000 );
        }
        elsif ( $vnode->type eq 'date_picker' ) {
            $class = 'SysDateTimePick32';
            $style = 0x54000000;
            $style = 0x54000004 if $vnode->format eq 'long';
            $style = 0x54000009 if $vnode->format eq 'time';
            $style |= 0x54000002 if $self->_nz( $vnode->show_none );
            $style |= 0x54000001 if $self->_nz( $vnode->useynavigate );
        }
        elsif ( $vnode->type eq 'spin_box' ) {
            $class        = 'EDIT';
            $style        = 0x54800880;
            $initial_text = '' . ( $vnode->value // 0 );
        }
        elsif ( $vnode->type eq 'progress_bar' ) {
            $class = 'msctls_progress32';
            $style = 0x54000001 | ( $vnode->indeterminate ? 0x0008 : 0 );    # PBS_SMOOTH (0x0001) | PBS_MARQUEE (0x0008)
        }
        elsif ( $vnode->type eq 'toggle_switch' || $vnode->type eq 'toggle_button' ) {
            $class        = 'BUTTON';
            $style        = 0x54001003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'link_button' ) {
            $class        = 'BUTTON';
            $style        = 0x54008000;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'checkbox' ) {
            $class        = 'BUTTON';
            $style        = 0x54000003;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'radio' ) {
            $class        = 'BUTTON';
            $style        = $vnode->first ? 0x54020009 : 0x54000009;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'combo_box' ) {
            $class = 'COMBOBOX';
            $style = 0x54210200 | ( $vnode->editable ? 0x0002 : 0x0003 );
        }
        elsif ( $vnode->type eq 'list_box' ) {
            $class = 'LISTBOX';
            $style = 0x54A10141 | ( $vnode->multiple ? 0x0008 : 0 );
        }
        elsif ( $vnode->type eq 'status_bar' ) {
            $class = 'msctls_statusbar32';
            $style = 0x54000100;
        }
        elsif ( $vnode->type eq 'group_box' ) {
            $class        = 'BUTTON';
            $style        = 0x54000007;
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'tree_view' ) {
            $class = 'SysTreeView32';
            $style = 0x54010037;
        }
        elsif ( $vnode->type eq 'list_view' ) {
            $class = 'SysListView32';
            $style = 0x54310001 | 0x0008 | ( $vnode->multiple ? 0 : 0x0004 ) | ( $vnode->header ? 0 : 0x4000 );
        }
        elsif ( $vnode->type eq 'toolbar' ) {
            $class = 'ToolbarWindow32';
            $style = 0x54001801;
        }
        elsif ( $vnode->type eq 'scroll_view' ) {
            $class = $viewport_class;
            $style = 0x56000000;
        }
        elsif ( $vnode->type eq 'tab_panel' ) {
            my $hw
                = CreateWindowExW( 0, 'SysTabControl32', undef, 0x54010000, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $vnode->id,
                undef, undef );
            $registry->{ $vnode->id } = { hwnd => $hw, node => $vnode, parent_hwnd => $parent_hwnd, surface => 'main', index => $vnode->index // 0 };
            $self->_theme_control($hw);
            $self->_set_font( $hw, $vnode->font, $vnode->font_size );
            $self->_populate_tabs( $vnode->id );
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
            SetWindowPos( $hw, cast( 1, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );
            SendMessageW( $hw, 0x130C, $registry->{ $vnode->id }{index}, 0 );
            $self->_apply_tab( $vnode->id );
            return;
        }
        elsif ( $vnode->type eq 'split_view' ) {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
            $registry->{ $vnode->id }
                = { hwnd => undef, node => $vnode, parent_hwnd => $parent_hwnd, surface => 'main', orientation => $vnode->orientation };
            return;
        }
        elsif ( $vnode->type eq 'spinner' ) {
            $class = 'STATIC';
            $style = 0x54000203;
        }
        elsif ( $vnode->type eq 'image' ) {
            $class = 'STATIC';
            $style = 0x5400000E;
        }
        elsif ( $vnode->type eq 'canvas' ) {
            $class = $canvas_class;
            $style = 0x54000000;
        }
        elsif ( $vnode->type eq 'separator' ) {
            $class = 'STATIC';
            $style = 0x54000000 | ( $vnode->orientation eq 'vertical' ? 0x0011 : 0x0010 );
        }
        elsif ( $vnode->type eq 'overlay' ) {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
            $self->_apply_overlay($vnode);
            return;
        }
        else {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
            $registry->{ $vnode->id } = { hwnd => undef, node => $vnode, surface => 'main' } if $vnode->type eq 'radio_group';
            return;
        }
        my $cid = $vnode->id =~ /^\d+$/ ? 0 + $vnode->id : ++$cid_counter;
        $cid_to_id->{$cid} = $vnode->id;
        if (
            $self->uses_dark_mode &&
            ( $vnode->type eq 'button' ||
                $vnode->type eq 'checkbox'      ||
                $vnode->type eq 'radio'         ||
                $vnode->type eq 'toggle_switch' ||
                $vnode->type eq 'toggle_button' )
        ) {
            $style |= 0x000B;    # BS_OWNERDRAW
        }
        my $hwnd = CreateWindowExW( 0, $class, $self->_nz($initial_text),
            $style, $vnode->bx, $vnode->by, $vnode->bw, $vnode->bh, $parent_hwnd, $cid, undef, undef );
        $registry->{ $vnode->id } = { hwnd => $hwnd, node => $vnode, parent_hwnd => $parent_hwnd, surface => 'main', cid => $cid };
        $surface_by_hwnd->{$hwnd} = 'main';
        $self->_theme_control($hwnd);
        EnableWindow( $hwnd, $vnode->enabled ? 1 : 0 );
        ShowWindow( $hwnd, $vnode->visible   ? 5 : 0 );
        $self->_set_tooltip( $hwnd, $vnode->tooltip ) if defined $vnode->tooltip;
        $self->_set_font( $hwnd, $vnode->font, $vnode->font_size );    # if $vnode->font || $vnode->font_size;

        if ( $vnode->type eq 'text_input' || $vnode->type eq 'password' || $vnode->type eq 'multiline_text' ) {
            $self->_set_placeholder( $hwnd, $vnode->placeholder ) if defined $vnode->placeholder;
            SendMessageW( $hwnd, 0x00CF, $vnode->readonly ? 1 : 0, 0 );
            SendMessageW( $hwnd, 0x00C5, $vnode->maxlength, 0 ) if $vnode->maxlength;
            SetFocus($hwnd) if $vnode->focused;
        }
        if ( $vnode->type eq 'spinner' ) {
            my $frames = $self->_spinner_frames( $vnode->size // 24, $vnode->color );
            $registry->{ $vnode->id }{spin_frames} = $frames;
            $registry->{ $vnode->id }{spin_idx}    = 0;
            SendMessageW( $hwnd, 0x0170, $frames->[0], 0 );
            $registry->{ $vnode->id }{spin_armed} = 0;
            if ( $vnode->running && @$frames ) {
                SetTimer( $parent_hwnd, $cid, $vnode->speed // 80, undef );
                $registry->{ $vnode->id }{spin_armed} = 1;
            }
        }
        if ( $vnode->type eq 'image' ) {
            $registry->{ $vnode->id }{img_w}   = $vnode->bw || 16;
            $registry->{ $vnode->id }{img_h}   = $vnode->bh || 16;
            $registry->{ $vnode->id }{img_src} = $vnode->src;
            $registry->{ $vnode->id }{img_fit} = $vnode->object_fit // 'contain';
            my $hb = $self->_raster_hbitmap( $vnode->src, $registry->{ $vnode->id }{img_w}, $registry->{ $vnode->id }{img_h}, $vnode->object_fit );
            SendMessageW( $hwnd, 0x0172, 0, $hb ) if $hb;
        }
        if ( $vnode->type eq 'canvas' ) {
            InvalidateRect( $hwnd, undef, 0 );
        }
        if ( $vnode->type eq 'slider' ) {
            SendMessageW( $hwnd, 0x0401, 1, ( $vnode->max << 16 ) | $vnode->min );
            SendMessageW( $hwnd, 0x0405, 1, $vnode->value );
            SendMessageW( $hwnd, 0x041C, 1, $vnode->step );
            SendMessageW( $hwnd, 0x041D, 1, $vnode->step );
        }
        if ( $vnode->type eq 'date_picker' ) {
            $self->_set_date_value( $hwnd, $vnode->value );
            $self->_set_date_range( $hwnd, $vnode->min, $vnode->max );
        }
        if ( $vnode->type eq 'checkbox' || $vnode->type eq 'toggle_switch' || $vnode->type eq 'toggle_button' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->checked ? 1 : 0, 0 );
        }
        if ( $self->uses_dark_mode &&
            ( $vnode->type eq 'checkbox' || $vnode->type eq 'radio' || $vnode->type eq 'toggle_switch' || $vnode->type eq 'toggle_button' ) ) {
            $registry->{ $vnode->id }{check} = $vnode->type eq 'radio' ? ( $vnode->selected ? 1 : 0 ) : ( $vnode->checked ? 1 : 0 );
        }
        if ( $vnode->type eq 'spin_box' ) {
            $self->_mount_spin_buddy( $parent_hwnd, $vnode );
        }
        if ( $vnode->type eq 'progress_bar' ) {
            SendMessageW( $hwnd, 0x0406, $vnode->min,                                     $vnode->max );
            SendMessageW( $hwnd, 0x0402, $self->_clamp_to_range( $vnode, $vnode->value ), 0 );
            SendMessageW( $hwnd, 0x040A, 1, 30 ) if $vnode->indeterminate;    # PBM_SETMARQUEE: wParam=1 (start), lParam=30ms
        }
        if ( $vnode->type eq 'radio' ) {
            SendMessageW( $hwnd, 0x00F1, $vnode->selected ? 1 : 0, 0 );
        }
        if ( $vnode->type eq 'password' && defined $vnode->password_char ) {
            SendMessageW( $hwnd, 0x00CC, CORE::ord( $self->_nz( $vnode->password_char ) ), 0 );
        }
        if ( $vnode->type eq 'combo_box' || $vnode->type eq 'list_box' ) {
            $self->_populate_strings( $hwnd, $vnode );
        }
        if ( $vnode->type eq 'tree_view' ) {
            if ( $self->uses_dark_mode ) {
                my $bg = $vnode->background ? $self->_parse_color( $vnode->background ) : 0x00302D2D;
                my $fg = $vnode->color      ? $self->_parse_color( $vnode->color )      : 0x00E6E6E6;
                SendMessageW( $hwnd, 0x111D, 0, $bg );    # TVM_SETBKCOLOR
                SendMessageW( $hwnd, 0x111E, 0, $fg );    # TVM_SETTEXTCOLOR
            }
            $registry->{ $vnode->id }{tree} = { slots => [], by_value => {}, by_hitem => {} };
            $self->_populate_tree( $vnode->id );
        }
        if ( $vnode->type eq 'toolbar' ) {
            $registry->{ $vnode->id }{toolbar} = { by_cmd => {} };
            SendMessageW( $hwnd, 0x041E, 32, 0 );
            $self->_populate_toolbar( $vnode->id );
        }
        if ( $vnode->type eq 'list_view' ) {
            my $ex = 0x00010000;    # LVS_EX_DOUBLEBUFFER
            $ex |= 0x00000020 if $vnode->full_row_select;
            $ex |= 0x00000010 if $vnode->reorderable;

            # Only enable native LVS_EX_GRIDLINES in light mode without custom grid_color
            $ex |= 0x00000001 if $vnode->grid_lines && !$self->uses_dark_mode && !$vnode->grid_color;
            SendMessageW( $hwnd, 0x1036, 0, $ex );
            if ( $self->uses_dark_mode ) {
                my $bg = $vnode->background ? $self->_parse_color( $vnode->background ) : 0x00302D2D;    # #2D2D30
                my $fg = $vnode->color      ? $self->_parse_color( $vnode->color )      : 0x00E6E6E6;    # #E6E6E6
                SendMessageW( $hwnd, 0x1001, 0, $bg );                                                   # LVM_SETBKCOLOR
                SendMessageW( $hwnd, 0x1026, 0, $bg );                                                   # LVM_SETTEXTBKCOLOR
                SendMessageW( $hwnd, 0x1024, 0, $fg );                                                   # LVM_SETTEXTCOLOR

                # 1. Darken the ListView itself
                $allow_dark->( $hwnd, 1 ) if $allow_dark;
                SetWindowTheme( $hwnd, 'DarkMode_Explorer', undef );
                SendMessageW( $hwnd, 0x031A, 0, 0 );                                                     # WM_THEMECHANGED

                # 2. Darken the Header control
                my $header = SendMessageW( $hwnd, 0x101F, 0, 0 );                                        # LVM_GETHEADER
                if ($header) {
                    $allow_dark->( $header, 1 ) if $allow_dark;
                    SetWindowTheme( $header, 'DarkMode_ItemsView', undef );
                    $self->_set_font( $header, $vnode->font, $vnode->font_size );
                    SendMessageW( $header, 0x031A, 0, 0 );                                               # WM_THEMECHANGED forces dark repaint
                }
            }
            $registry->{ $vnode->id }{listview} = { slots => [], ncols => 0 };
            $self->_populate_listview( $vnode->id );
        }
        if ( $vnode->type eq 'status_bar' ) {
            if ( $self->uses_dark_mode ) {
                my $bg = $vnode->background ? $self->_parse_color( $vnode->background ) : 0x00202020;
                SendMessageW( $hwnd, 0x2001, 0, $bg );    # SB_SETBKCOLOR (CCM_SETBKCOLOR)
            }
            $self->_populate_statusbar( $hwnd, $vnode );
        }
        if ( $vnode->type eq 'search_input' ) {
            $self->_set_placeholder( $hwnd, $vnode->placeholder ) if defined $vnode->placeholder;
            my $left = $vnode->icon ? 24 : 4;
            SendMessageW( $hwnd, 0x00D3, 3, ( 20 << 16 ) | $left );
            $self->_mount_search_aux( $parent_hwnd, $vnode );
        }
        if ( $vnode->type eq 'group_box' ) {
            $self->_mount_node( $_, $parent_hwnd ) for @{ $vnode->children };
        }
        if ( $vnode->type eq 'scroll_view' ) {
            my $rec = $registry->{ $vnode->id };
            $rec->{scroll}     = { ox => 0, oy => 0, base_x => $vnode->bx, base_y => $vnode->by };
            $rec->{scroll}{ox} = $vnode->scroll_x if defined $vnode->scroll_x;
            $rec->{scroll}{oy} = $vnode->scroll_y if defined $vnode->scroll_y;
            for my $kid ( @{ $vnode->children } ) {
                $self->_mount_node( $kid, $hwnd );
                $self->_mark_scrolled( $kid, $rec->{scroll} );
            }
        }
    }

    method _set_font ( $hwnd, $name = undef, $size = undef ) {
        return unless $hwnd;
        if ( defined $name || defined $size ) {
            my $hfont = $self->_get_font( $name, $size );
            if ($hfont) {
                SendMessageW( $hwnd, 0x0030, Affix::address($hfont), 1 );
            }
        }
        elsif ($gui_font) {
            SendMessageW( $hwnd, 0x0030, Affix::address($gui_font), 1 );
        }
    }

    method _set_placeholder ( $hwnd, $text ) {
        return unless $hwnd;
        my $wide = Encode::encode( 'UTF-16LE', $self->_nz($text) );
        my $buf  = malloc( CORE::length($wide) + 2 );
        memcpy( $buf, $wide, CORE::length($wide) );
        SendMessageW( $hwnd, 0x1501, 1, Affix::address($buf) );
        free($buf);
    }

    method _mount_spin_buddy ( $parent_hwnd, $vnode ) {
        my $cxv     = GetSystemMetrics(2);
        my $edit_bw = $vnode->bw - $cxv;
        SetWindowPos( $registry->{ $vnode->id }{hwnd}, undef, $vnode->bx, $vnode->by, $edit_bw, $vnode->bh, 0x0004 );
        my $up = CreateWindowExW( 0, 'msctls_updown32', undef, 0x54000020, $vnode->bx + $edit_bw,
            $vnode->by, $cxv, $vnode->bh, $parent_hwnd, 0, undef, undef );
        EnableWindow( $up, $vnode->enabled ? 1 : 0 );
        ShowWindow( $up, $vnode->visible   ? 5 : 0 );
        return unless $up;
        $registry->{ $vnode->id }{aux} = $up;
        $self->_theme_control($up);
        SendMessageW( $up, 0x046F, 0, ( $vnode->max << 16 ) | $vnode->min );
        SendMessageW( $up, 0x0471, 0, $vnode->value );
        $self->_spin_set_step( $up, $vnode->step ) if $vnode->step != 1;
        InvalidateRect( $up, undef, 0 );
        UpdateWindow($up);
    }

    method _mount_search_aux ( $parent_hwnd, $vnode ) {
        my $rec = $registry->{ $vnode->id } or return;
        if ( $vnode->icon ) {
            my $hicon = $self->_icon_hicon( $vnode->icon, 16 );
            if ($hicon) {
                my $ih = CreateWindowExW(
                    0, 'STATIC', undef, 0x54000203,
                    $vnode->bx + 4,
                    $vnode->by + int( ( $vnode->bh - 16 ) / 2 ),
                    16, 16, $parent_hwnd, 0, undef, undef
                );
                if ($ih) {
                    SendMessageW( $ih, 0x0170, $hicon, 0 );
                    $self->_theme_control($ih);
                    $rec->{icon_hwnd} = $ih;
                }
            }
        }
        my $cmd   = ++$cmd_counter;
        my $clear = CreateWindowExW( 0, 'BUTTON', "\x{2715}", 0x54008000, $vnode->bx + $vnode->bw - 20,
            $vnode->by, 20, $vnode->bh, $parent_hwnd, $cmd, undef, undef );
        return unless $clear;
        EnableWindow( $clear, $vnode->enabled ? 1 : 0 );
        ShowWindow( $clear, $vnode->value     ? 5 : 0 );
        $self->_theme_control($clear);
        $self->_set_font($clear);
        $rec->{aux}             = $clear;
        $rec->{search_clear_id} = $cmd;
        $registry->{$cmd}       = { hwnd => $clear, node => $vnode, search_clear => 1, search_id => $vnode->id };
    }

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

            if ( $over || $was_over ) {
                InvalidateRect( $up, undef, 0 );
                UpdateWindow($up);
            }
        }
    }

    method _spin_sync_text ( $edit_hwnd, $value ) {
        $suppress_events = 1;
        SetWindowTextW( $edit_hwnd, '' . ( $value // 0 ) );
        $suppress_events = 0;
        my $len = CORE::length( '' . ( $value // 0 ) );
        SendMessageW( $edit_hwnd, 0x00B1, $len, $len );
    }

    method _spin_set_step ( $hwnd, $step ) {
        return if $step <= 1;
        my $buf = malloc( sizeof( UDACCEL() ) );
        my $ud  = cast( $buf, UDACCEL() );
        $ud->{nSec} = 0;
        $ud->{nInc} = $step;
        SendMessageW( $hwnd, 0x046B, 1, Affix::address($buf) );
        free($buf);
    }

    method _populate_strings ( $hwnd, $vnode ) {
        my $is_combo = $vnode->type eq 'combo_box';
        my $clear    = $is_combo ? 0x014B : 0x0184;
        my $add      = $is_combo ? 0x0143 : 0x0180;
        my $set      = $is_combo ? 0x014E : 0x0186;
        free($_) for @{ $item_pins->{$hwnd} // [] };
        my @pins;
        for my $opt ( @{ $vnode->options } ) {
            my $text = $self->_nz( '' . ( $opt->{label} // $opt->{value} // '' ) );
            my $wide = Encode::encode( 'UTF-16LE', $text );
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

    method _set_multiselect ( $hwnd, $vnode, $want ) {
        $want = [$want] unless ref $want eq 'ARRAY';
        SendMessageW( $hwnd, 0x0185, 0, -1 );
        my $i = 0;
        for my $opt ( @{ $vnode->options } ) {
            my $val = $opt->{value} // $opt->{label} // '';
            if ( grep { ( $_ // '' ) eq $val } @$want ) {
                SendMessageW( $hwnd, 0x0185, 1, $i );
            }
            $i++;
        }
    }

    method _option_index ( $node, $want ) {
        my $i = 0;
        for my $opt ( @{ $node->options } ) {
            return $i if ( $opt->{value} // '' ) eq ( $want // '' );
            $i++;
        }
        return -1;
    }

    method _set_date_value ( $hwnd, $value ) {
        return unless $hwnd;
        if ( defined $value && $value =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) {
            my $st  = pack( 'S8', $1, $2, 0, $3, 0, 0, 0, 0 );
            my $buf = malloc(16);
            memcpy( $buf, $st, 16 );
            SendMessageW( $hwnd, 0x1002, 0, Affix::address($buf) );
            free($buf);
        }
        else {
            SendMessageW( $hwnd, 0x1002, 1, 0 );
        }
    }

    method _set_date_range ( $hwnd, $min, $max ) {
        return unless $hwnd;
        return if !defined $min && !defined $max;
        my $lo = $min && $min =~ /^(\d{4})-(\d{2})-(\d{2})$/ ? [ $1, $2, $3 ] : [ 1601, 1,  1 ];
        my $hi = $max && $max =~ /^(\d{4})-(\d{2})-(\d{2})$/ ? [ $1, $2, $3 ] : [ 9999, 12, 31 ];
        my $rb = malloc(32);
        memcpy( $rb, pack( 'S8', $lo->[0], $lo->[1], 0, $lo->[2], 0, 0, 0, 0 ) . pack( 'S8', $hi->[0], $hi->[1], 0, $hi->[2], 0, 0, 0, 0 ), 32 );
        SendMessageW( $hwnd, 0x1004, 0x3, Affix::address($rb) );
        free($rb);
    }

    method set_prop ( $vnode_id, $prop_name, $value ) {
        my $record = $registry->{$vnode_id};
        return unless $record;
        if ( $prop_name eq 'title' ) {
            $main_hwnd = $record->{hwnd};
            SetWindowTextW( $main_hwnd, $self->_nz($value) );
        }
        elsif ( $prop_name eq 'topmost' ) {
            SetWindowPos( $record->{hwnd}, $value ? -1 : -2, 0, 0, 0, 0, 0x0013 );
        }
        elsif ( $prop_name eq 'minimized' || $prop_name eq 'maximized' ) {
            if ($value) {
                if ( $prop_name eq 'maximized' && $self->_has_size_constraints( $record->{node} ) ) {
                    return;
                }
                ShowWindow( $record->{hwnd}, $prop_name eq 'minimized' ? 2 : 3 );
            }
            else {
                ShowWindow( $record->{hwnd}, 9 );
            }
        }
        elsif ( $prop_name =~ /^(min|max)_[wh]$/ ) {
            my $vn = $record->{node} || $main_vnode;
            my ( $cw, $ch ) = $self->_get_client_size( $record->{hwnd} );
            my ( $nw, $nh ) = ( $cw, $ch );
            if ( $vn->min_w && $nw < $vn->min_w ) { $nw = $vn->min_w }
            if ( $vn->min_h && $nh < $vn->min_h ) { $nh = $vn->min_h }
            if ( $vn->max_w && $nw > $vn->max_w ) { $nw = $vn->max_w }
            if ( $vn->max_h && $nh > $vn->max_h ) { $nh = $vn->max_h }
            if ( $nw != $cw || $nh != $ch ) {
                $self->_set_window_outer( $record->{hwnd}, $nw, $nh );
                my $surface_id = $self->surface_by_hwnd->{ $record->{hwnd} };
                my $rb         = $self->_get_resize_handler;
                $rb->( $surface_id, $nw, $nh ) if $rb && $surface_id;
            }
        }
        elsif ( $prop_name eq 'label' ) {
            if ( $record->{node}->type eq 'status_bar' ) {
                $self->_populate_statusbar( $record->{hwnd}, $record->{node}, [$value] );
                return;
            }
            SetWindowTextW( $record->{hwnd}, $self->_nz($value) );
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'panels' && $record->{node}->type eq 'status_bar' ) {
            $self->_populate_statusbar( $record->{hwnd}, $record->{node}, $value );
        }
        elsif ( $prop_name eq 'scroll_x' || $prop_name eq 'scroll_y' ) {
            return unless $record->{node}->type eq 'scroll_view';
            return unless $record->{scroll};
            $record->{scroll}{ $prop_name eq 'scroll_x' ? 'ox' : 'oy' } = $value;
            $self->_apply_scroll($vnode_id);
        }
        elsif ( $prop_name eq 'divider' || $prop_name eq 'orientation' ) {
            return unless $record->{node}->type eq 'split_view';
            $record->{orientation} = $value if $prop_name eq 'orientation' && defined $value;
            $record->{divider}     = $value if $prop_name eq 'divider'     && defined $value;
            $self->_place_divider($vnode_id);
        }
        elsif ( $prop_name eq 'index' ) {
            return unless $record->{node}->type eq 'tab_panel';
            $record->{index} = $value if defined $value;
            if ( $record->{hwnd} ) {
                my $cur = SendMessageW( $record->{hwnd}, 0x130B, 0, 0 );
                SendMessageW( $record->{hwnd}, 0x130C, $record->{index}, 0 ) if $cur != $record->{index};
            }
            $self->_apply_tab($vnode_id);
        }
        elsif ( $prop_name eq 'panels' && $record->{node}->type eq 'tab_panel' ) {
            $self->_populate_tabs($vnode_id);
            $self->_apply_tab($vnode_id);
        }
        elsif ( $prop_name =~ /^(running|speed|size|color)$/ && $record->{node}->type eq 'spinner' ) {
            my $new_running = $prop_name eq 'running' ? $value : $record->{node}->running;
            my $new_speed   = $prop_name eq 'speed'   ? $value : $record->{node}->speed;
            my $new_size    = $prop_name eq 'size'    ? $value : $record->{node}->size;
            my $new_color   = $prop_name eq 'color'   ? $value : $record->{node}->color;
            $record->{spin_frames} = $self->_spinner_frames( $new_size, $new_color );
            $record->{spin_idx}    = 0;
            $record->{spin_armed}  = 0;
            SendMessageW( $record->{hwnd}, 0x0170, $record->{spin_frames}[0], 0 );
            KillTimer( $record->{parent_hwnd}, $record->{cid} );

            if ( $new_running && @{ $record->{spin_frames} } ) {
                SetTimer( $record->{parent_hwnd}, $record->{cid}, $new_speed // 80, undef );
                $record->{spin_armed} = 1;
            }
        }
        elsif ( ( $prop_name eq 'src' || $prop_name eq 'object_fit' ) && $record->{node}->type eq 'image' ) {
            my $src = $prop_name eq 'src'        ? $value : $record->{node}->src;
            my $fit = $prop_name eq 'object_fit' ? $value : ( $record->{node}->object_fit // 'contain' );
            my $w   = $record->{img_w} || 16;
            my $h   = $record->{img_h} || 16;
            $record->{img_src} = $src;
            $record->{img_fit} = $fit;
            my $hb = $self->_raster_hbitmap( $src, $w, $h, $fit );
            SendMessageW( $record->{hwnd}, 0x0172, 0, $hb ) if $hb;
        }
        elsif ( $prop_name eq 'color' && $record->{node}->type eq 'color_button' ) {
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'show_hex' && $record->{node}->type eq 'color_button' ) {
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $record->{node}->type eq 'canvas' && ( $prop_name eq 'on_draw' || $prop_name eq 'redraw' ) ) {
            InvalidateRect( $record->{hwnd}, undef, 0 );
        }
        elsif ( $prop_name eq 'indeterminate' && $record->{node}->type eq 'progress_bar' ) {

            # PBM_SETMARQUEE starts (1) or stops (0) the marquee animation
            SendMessageW( $record->{hwnd}, 0x040A, $value ? 1 : 0, 30 );
        }
        elsif ( $prop_name eq 'value' ) {
            if ( $record->{node}->type eq 'date_picker' ) {
                $self->_set_date_value( $record->{hwnd}, $value );
            }
            if ( $record->{node}->type eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0405, 1, $value );
                return;
            }
            if ( $record->{node}->type eq 'spin_box' ) {
                SendMessageW( $record->{aux}, 0x0471, 0, $value );
                $self->_spin_sync_text( $record->{hwnd}, $value );
                return;
            }
            if ( $record->{node}->type eq 'progress_bar' ) {
                SendMessageW( $record->{hwnd}, 0x0402, $self->_clamp_to_range( $record->{node}, $value ), 0 );
                return;
            }
            if ( $record->{node}->type eq 'radio_group' ) {
                return $self->_apply_radio_group( $record, $value );
            }
            if ( $record->{node}->type eq 'tree_view' ) {
                return $self->_select_tree_value( $vnode_id, $value );
            }
            if ( $record->{node}->type eq 'list_view' ) {
                return $self->_select_listvalue( $vnode_id, $value );
            }
            if ( $record->{node}->type eq 'combo_box' || $record->{node}->type eq 'list_box' ) {
                my $is_combo = $record->{node}->type eq 'combo_box';
                return $self->_set_multiselect( $record->{hwnd}, $record->{node}, $value ) if !$is_combo && $record->{node}->multiple;
                my $sel = $is_combo ? 0x014E : 0x0186;
                my $idx = $self->_option_index( $record->{node}, $value );
                if ( $idx >= 0 ) {
                    SendMessageW( $record->{hwnd}, $sel, $idx, 0 );
                }
                elsif ( $is_combo && $record->{node}->editable ) {
                    my $cur = $self->_get_text( $record->{hwnd} );
                    if ( $cur ne $value ) {
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
            my $current = $self->_get_text( $record->{hwnd} );
            if ( $current ne $value ) {
                my $native = $self->_to_crlf( $self->_nz($value) );
                $suppress_events = 1;
                SetWindowTextW( $record->{hwnd}, $native );
                $suppress_events = 0;
                my $len = CORE::length $native;
                SendMessageW( $record->{hwnd}, 0x00B1, $len, $len );
            }
            if ( $record->{node}->type eq 'search_input' && $record->{aux} ) {
                ShowWindow( $record->{aux}, $value ? 5 : 0 );
            }
        }
        elsif ( $prop_name eq 'enabled' ) {
            EnableWindow( $record->{hwnd}, $value ? 1 : 0 );
            if ( $record->{aux} ) {
                EnableWindow( $record->{aux}, $value ? 1 : 0 ) if $record->{node}->type eq 'spin_box' || $record->{node}->type eq 'search_input';
            }
            EnableWindow( $record->{icon_hwnd}, $value ? 1 : 0 ) if $record->{icon_hwnd};
        }
        elsif ( $prop_name eq 'visible' ) {
            ShowWindow( $record->{hwnd}, $value ? 5 : 0 );
            if ( $record->{aux} ) {
                ShowWindow( $record->{aux}, $value                               ? 5 : 0 ) if $record->{node}->type eq 'spin_box';
                ShowWindow( $record->{aux}, ( $value && $record->{node}->value ) ? 5 : 0 ) if $record->{node}->type eq 'search_input';
            }
            ShowWindow( $record->{icon_hwnd}, $value ? 5 : 0 ) if $record->{icon_hwnd};
        }
        elsif ( $prop_name eq 'focused' ) {
            SetFocus( $record->{hwnd} ) if $value;
        }
        elsif ( $prop_name eq 'tooltip' ) {
            $self->_set_tooltip( $record->{hwnd}, $value );
        }
        elsif ( $prop_name eq 'readonly' ) {
            return unless $record->{node}->can('value');
            SendMessageW( $record->{hwnd}, 0x00CF, $value ? 1 : 0, 0 );
        }
        elsif ( $prop_name eq 'maxlength' ) {
            return unless $record->{node}->can('value');
            SendMessageW( $record->{hwnd}, 0x00C5, $value, 0 );
        }
        elsif ( $prop_name eq 'placeholder' ) {
            return unless $record->{node}->can('value');
            $self->_set_placeholder( $record->{hwnd}, $value );
        }
        elsif ( $prop_name eq 'password_char' ) {
            return unless $record->{node}->type eq 'password';
            SendMessageW( $record->{hwnd}, 0x00CC, defined $value && length $value ? CORE::ord($value) : 0, 0 );
        }
        elsif ( $prop_name eq 'font' || $prop_name eq 'font_size' ) {
            my $name = $prop_name eq 'font'      ? $value : $record->{node}->font;
            my $size = $prop_name eq 'font_size' ? $value : $record->{node}->font_size;
            $self->_set_font( $record->{hwnd}, $name, $size );
        }
        elsif ( $prop_name eq 'color' || $prop_name eq 'background' ) {
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'step' ) {
            my $t = $record->{node}->type;
            return unless $t eq 'slider' || $t eq 'spin_box';
            if ( $t eq 'spin_box' ) {
                return $self->_spin_set_step( $record->{aux}, $value );
            }
            SendMessageW( $record->{hwnd}, 0x041C, 1, $value );
            SendMessageW( $record->{hwnd}, 0x041D, 1, $value );
        }
        elsif ( $prop_name eq 'checked' ) {
            my $t = $record->{node}->type;
            return unless $t eq 'checkbox' || $t eq 'toggle_switch' || $t eq 'toggle_button';
            SendMessageW( $record->{hwnd}, 0x00F1, $value ? 1 : 0, 0 );
            if ( $self->uses_dark_mode ) {
                $record->{check} = $value ? 1 : 0;
                InvalidateRect( $record->{hwnd}, undef, 1 );
            }
        }
        elsif ( $prop_name eq 'options' ) {
            return unless $record->{node}->type eq 'combo_box' || $record->{node}->type eq 'list_box';
            $self->_populate_strings( $record->{hwnd}, $record->{node} );
        }
        elsif ( $prop_name eq 'rows' || $prop_name eq 'columns' ) {
            return unless $record->{node}->type eq 'list_view';
            $self->_populate_listview( $vnode_id, $prop_name eq 'rows' ? 1 : 0 );
        }
        elsif ( $prop_name eq 'nodes' || $prop_name eq 'expanded' ) {
            return unless $record->{node}->type eq 'tree_view';
            $self->_populate_tree($vnode_id);
        }
        elsif ( $prop_name eq 'buttons' && $record->{node}->type eq 'toolbar' ) {
            $self->_populate_toolbar( $vnode_id, $value );
        }
        elsif ( $prop_name eq 'menu_bar' && $record->{node}->type eq 'window' ) {
            $self->_mount_menu_bar($vnode_id);
        }
        elsif ( $prop_name eq 'min' || $prop_name eq 'max' ) {
            my $t = $record->{node}->type;
            if ( $t eq 'date_picker' ) {
                my $min = $prop_name eq 'min' ? $value : $record->{node}->min;
                my $max = $prop_name eq 'max' ? $value : $record->{node}->max;
                $self->_set_date_range( $record->{hwnd}, $min, $max );
                return;
            }
            return unless $t eq 'slider' || $t eq 'spin_box' || $t eq 'progress_bar';
            my $min = $prop_name eq 'min' ? $value : $record->{node}->min;
            my $max = $prop_name eq 'max' ? $value : $record->{node}->max;
            if ( $t eq 'progress_bar' ) {
                SendMessageW( $record->{hwnd}, 0x0406, $min, $max );
            }
            elsif ( $t eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0401, 1, ( $max << 16 ) | $min );
            }
            else {
                SendMessageW( $record->{aux} || $record->{hwnd}, 0x046F, 0, ( $max << 16 ) | $min );
            }
        }
    }

    method move_widget ( $vnode_id, $x, $y, $w, $h ) {
        my $record = $registry->{$vnode_id};
        return unless $record;
        if ( $record->{node} && $record->{node}->type eq 'scroll_view' ) {
            my $st = $record->{scroll} ||= { ox => 0, oy => 0, base_x => $x, base_y => $y };
            $st->{base_x} = $x;
            $st->{base_y} = $y;
            $self->_place_scrollbars($vnode_id);
            $self->_apply_scroll($vnode_id);
            return;
        }
        if ( $record->{node} && $record->{node}->type eq 'split_view' ) {
            $self->_place_divider($vnode_id);
            return;
        }
        if ( $record->{node} && $record->{node}->type eq 'tab_panel' && $record->{hwnd} ) {
            SetWindowPos( $record->{hwnd}, cast( 1, Pointer [Void] ), $x, $y, $w, $h, 0x0010 );
            return;
        }
        return unless $record->{hwnd};
        my ( $mx, $my ) = ( 0, 0 );
        if ( my $st = $record->{scroll} ) {
            ( $mx, $my ) = ( -( $st->{base_x} + $st->{ox} ), -( $st->{base_y} + $st->{oy} ) );
        }
        SetWindowPos( $record->{hwnd}, undef, $x + $mx, $y + $my, $w, $h, 0x0004 );
        if ( $record->{node} && $record->{node}->type eq 'image' ) {
            my $new_fit = $record->{node}->object_fit // 'contain';
            if ( $record->{img_w} != $w || $record->{img_h} != $h || ( $record->{img_fit} // '' ) ne $new_fit ) {
                $record->{img_w}   = $w;
                $record->{img_h}   = $h;
                $record->{img_fit} = $new_fit;
                my $hb = $self->_raster_hbitmap( $record->{node}->src, $w, $h, $new_fit );
                SendMessageW( $record->{hwnd}, 0x0172, 0, $hb ) if $hb;
            }
        }
        if ( $record->{node} && $record->{node}->type eq 'canvas' ) {
            InvalidateRect( $record->{hwnd}, undef, 0 );
        }
        if ( $record->{node} && $record->{node}->type eq 'status_bar' ) {
            $self->_repart_statusbar( $record->{hwnd}, $record->{node}, $record->{parts} );
        }
        if ( $record->{node} && $record->{node}->type eq 'spin_box' && $record->{aux} ) {
            my $sw = GetSystemMetrics(2);
            SetWindowPos( $record->{hwnd}, undef, $x + $mx,            $y + $my, $w - $sw, $h, 0x0004 );
            SetWindowPos( $record->{aux},  undef, $x + $mx + $w - $sw, $y + $my, $sw,      $h, 0x0004 );
        }
        if ( $record->{node} && $record->{node}->type eq 'search_input' ) {
            if ( $record->{icon_hwnd} ) {
                SetWindowPos( $record->{icon_hwnd}, undef, $x + $mx + 4, $y + $my + int( ( $h - 16 ) / 2 ), 16, 16, 0x0004 );
            }
            if ( $record->{aux} ) {
                SetWindowPos( $record->{aux}, undef, $x + $mx + $w - 20, $y + $my, 20, $h, 0x0004 );
            }
        }
    }

    method _registry_id_by_key ( $hwnd, $key ) {
        for my $id ( keys %{$registry} ) {
            my $rec = $registry->{$id};
            next unless $rec && $rec->{$key};
            return $id if $rec->{$key} == $hwnd;
        }
        return undef;
    }

    method _create_scrollbar ( $parent, $vertical ) {
        my $sb = CreateWindowExW( 0, 'SCROLLBAR', undef, 0x54000000 | ( $vertical ? 0x0001 : 0x0000 ), 0, 0, 0, 0, $parent, 0, undef, undef );
        $self->_theme_control($sb);
        return $sb;
    }

    method _scrollbar_range_pos ( $hwnd, $max, $pos, $page ) {
        my $sysmax = $page ? $max + $page - 1 : $max;
        my $s      = malloc(28);
        memcpy( $s, pack( 'l<7', 28, 0x0001 | 0x0002 | 0x0004, 0, $sysmax, $page // 0, $pos, 0 ), 28 );
        my $ret = SetScrollInfo( $hwnd, 2, $s, 1 );
        free($s);
        return $ret;
    }

    method _scrollbar_read_pos ($hwnd) {
        my $s = malloc(28);
        memcpy( $s, pack( 'l<7', 28, 0x0004, 0, 0, 0, 0, 0 ), 28 );
        GetScrollInfo( $hwnd, 2, $s );
        my ( undef, undef, undef, undef, undef, $pos ) = unpack 'l<7', Affix::raw( $s, 28 );
        free($s);
        return $pos;
    }

    method _scrollbar_track_pos ($hwnd) {
        my $s = malloc(28);
        memcpy( $s, pack( 'l<7', 28, 0x0010, 0, 0, 0, 0, 0 ), 28 );
        GetScrollInfo( $hwnd, 2, $s );
        my ( undef, undef, undef, undef, undef, undef, $trackpos ) = unpack 'l<7', Affix::raw( $s, 28 );
        free($s);
        return $trackpos;
    }

    method _place_scrollbars ($id) {
        my $rec  = $registry->{$id} or return;
        my $node = $rec->{node}     or return;
        my $st   = $rec->{scroll}   or return;
        my $sbw  = GetSystemMetrics(2);
        my $sbh  = GetSystemMetrics(4);
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
            SetWindowPos( $rec->{aux_h}, cast( 0, Pointer [Void] ), $node->bx, $node->by + $view_h, $view_w, $sbh, 0x0010 );
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
            SetWindowPos( $rec->{aux_v}, cast( 0, Pointer [Void] ), $node->bx + $view_w, $node->by, $sbw, $view_h, 0x0010 );
            ShowWindow( $rec->{aux_v}, 5 );
            $self->_scrollbar_range_pos( $rec->{aux_v}, $range_v, $st->{oy}, $rec->{page_v} );
        }
        elsif ( $rec->{aux_v} ) {
            DestroyWindow( $rec->{aux_v} );
            delete $rec->{aux_v};
            $st->{oy} = 0;
        }
    }

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
            next if $r == $rec;
            next unless $r->{scroll} && $r->{scroll} == $st && $r->{hwnd} && $r->{node};
            SetWindowPos(
                $r->{hwnd}, undef,
                $r->{node}->bx - $st->{base_x} - $st->{ox},
                $r->{node}->by - $st->{base_y} - $st->{oy},
                $r->{node}->bw, $r->{node}->bh, 0x0004
            );
            InvalidateRect( $r->{hwnd}, undef, 1 );
        }
        InvalidateRect( $rec->{hwnd}, undef, 1 );
        UpdateWindow( $rec->{hwnd} );
    }

    method _scrollbar_event ( $id, $axis, $wparam ) {
        my $rec  = $registry->{$id}    or return;
        my $st   = $rec->{scroll}      or return;
        my $sb   = $rec->{"aux_$axis"} or return;
        my $key  = $axis eq 'h' ? 'ox' : 'oy';
        my $code = $wparam & 0xFFFF;
        my $pos  = $st->{$key};
        my $pg   = 8 * 16;
        $pos -= 16  if $code == 0;
        $pos += 16  if $code == 1;
        $pos -= $pg if $code == 2;
        $pos += $pg if $code == 3;

        if ( $code == 5 ) {
            my $tp = $self->_scrollbar_track_pos($sb);
            $pos = $tp || ( ( $wparam >> 16 ) & 0xFFFF );
        }
        elsif ( $code == 4 ) {
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

    method _wheel_target ( $axis, $lparam ) {
        my $px = $lparam & 0xFFFF;
        my $py = ( $lparam >> 16 ) & 0xFFFF;
        my ( $hit, $hit_area, $hit_keyed ) = ( undef, 1 << 30, 0 );
        my $wrect = malloc( sizeof( RECT() ) );
        for my $id ( keys %{$registry} ) {
            my $rec = $registry->{$id};
            next unless $rec && $rec->{node} && $rec->{node}->type eq 'scroll_view' && $rec->{hwnd};
            GetWindowRect( $rec->{hwnd}, $wrect );
            my $r       = cast( $wrect, RECT() );
            my $in_view = $px >= $r->{left} && $px <= $r->{right} && $py >= $r->{top} && $py <= $r->{bottom};
            my $area    = ( $r->{right} - $r->{left} ) * ( $r->{bottom} - $r->{top} );
            my $keyed   = 0;
            for my $ax (qw(v h)) {
                next unless $rec->{"aux_$ax"};
                GetWindowRect( $rec->{"aux_$ax"}, $wrect );
                my $r2  = cast( $wrect, RECT() );
                my $inr = $px >= $r2->{left} && $px <= $r2->{right} && $py >= $r2->{top} && $py <= $r2->{bottom};
                $keyed = 1 if $inr;
                $keyed = 2 if $inr && $ax eq $axis;
            }
            next unless $in_view || $keyed;
            next if $hit && $keyed < $hit_keyed;
            next if $hit && $keyed == $hit_keyed && $area >= $hit_area;
            ( $hit, $hit_area, $hit_keyed ) = ( $id, $area, $keyed );
        }
        free($wrect);
        return $hit;
    }

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

    method _clamp_divider ( $node, $div, $vert, $dw, $avail ) {
        my $min_a = defined $node->min_a ? $node->min_a : 40;
        my $min_b = defined $node->min_b ? $node->min_b : 40;
        $div = $min_a if $div < $min_a;
        my $max = $avail - $dw - $min_b;
        $div = $max   if $div > $max;
        $div = $min_a if $div > $max;
        return $div;
    }

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
        $self->_theme_control($hw);
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

    method _divider_cursor ($hwnd) {
        my $id   = $self->_registry_id_by_key( $hwnd, 'aux' ) or return undef;
        my $node = $registry->{$id}{node}                     or return undef;
        return LoadCursorW( undef, ( $registry->{$id}{orientation} // $node->orientation // 'vertical' ) eq 'horizontal' ? 32644 : 32645 );
    }

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
        $n = 1 unless $n;
        $registry->{ $vnode->id }{parts} = $n;
        return if $n < 2;
        my $widths = pack 'V*', map { int( $vnode->bw * ( $_ + 1 ) / $n ) } 0 .. $n - 1;
        my $buf    = malloc( $n * 4 );
        memcpy( $buf, $widths, $n * 4 );
        SendMessageW( $hwnd, 0x0404, $n, Affix::address($buf) );
        free($buf);
    }

    method _populate_statusbar ( $hwnd, $vnode, $texts = undef ) {
        return unless $hwnd;
        my @texts = defined $texts ? @$texts : @{ $vnode->panels };
        @texts = ( $vnode->label ) unless @texts;
        $self->_repart_statusbar( $hwnd, $vnode, scalar @texts );
        for my $i ( 0 .. $#texts ) {
            my $wide = Encode::encode( 'UTF-16LE', $self->_nz( $texts[$i] ) ) . "\x00\x00";
            my $buf  = malloc( CORE::length($wide) );
            memcpy( $buf, $wide, CORE::length($wide) );
            SendMessageW( $hwnd, 0x040B, $i, Affix::address($buf) );
            free($buf);
        }
    }

    method _populate_tabs ($id) {
        my $rec  = $registry->{$id} or return;
        my $hw   = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $cnt  = SendMessageW( $hw, 0x1304, 0, 0 );
        SendMessageW( $hw, 0x1308, 0, 0 ) while $cnt-- > 0;
        my $tc = malloc( sizeof( TCITEMW() ) );
        my $tp = cast( $tc, TCITEMW() );
        $tp->{mask} = 0x0001;

        for my $i ( 0 .. $#{ $node->panels } ) {
            my $p     = $node->panels->[$i];
            my $title = ref $p eq 'HASH' ? ( $p->{title} // $p->{label} // '' ) : ( $p->[0] // '' );
            $tp->{pszText} = $self->_nz($title);
            SendMessageW( $hw, 0x1307, $i, Affix::address($tc) );
        }
        free($tc);
        if ( $rec->{index} > $#{ $node->panels } ) {
            $rec->{index} = 0;
        }
        SendMessageW( $hw, 0x130C, $rec->{index} // 0, 0 );
    }

    method _populate_tree ($id) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $t    = $rec->{tree}     or return;
        $t->{slots}    = [];
        $t->{by_value} = {};
        $t->{by_hitem} = {};
        SendMessageW( $hwnd, 0x1101, 1, 0 );
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
                my $bytes = pack 'q<q< L< x4 q< L< L< q< l< l< l< l< q<', $parent_hitem // 0, 0xFFFF0002, ( 0x0001 | 0x0004 | 0x0040 ), 0, 0, 0,
                    Affix::address($abuf), 0, 0, 0, $kids, $slot;
                my $struct = malloc( length $bytes );
                memcpy( $struct, $bytes, length $bytes );
                my $hitem = SendMessageW( $hwnd, 0x1132, 0, Affix::address($struct) );
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
        $self->_select_tree_value( $id, $node->value );
    }

    method _tree_expand_value ( $hwnd, $hitem, $value, $want_exp ) {
        return unless $want_exp->{$value};
        SendMessageW( $hwnd, 0x1102, 0x0002, $hitem );
    }
    my $LVITEM = 'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4';

    method _populate_listview ( $id, $reuse_columns = 0 ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        my $lv   = $rec->{listview} ||= { slots => [], ncols => 0 };
        SendMessageW( $hwnd, 0x1009, 0, 0 );
        $lv->{slots} = [];
        $reuse_columns = 0 if ( $lv->{ncols} // 0 ) != scalar @{ $node->columns // [] };
        if ( !$reuse_columns ) {
            my $old_n = $lv->{ncols} // 0;
            SendMessageW( $hwnd, 0x101C, 0, 0 ) while $old_n-- > 0;
            $lv->{ncols} = 0;
        }
        my $cols = $node->columns;
        $cols = [ { label => 'Items' } ] unless @$cols;
        if ( !$reuse_columns ) {
            for my $i ( 0 .. $#$cols ) {
                my $sort  = $lv->{sort} && $lv->{sort}{col} == $i;
                my $label = $cols->[$i]{label} // '';
                $label .= $sort ? ( $lv->{sort}{dir} eq 'asc' ? ' ▲' : ' ▼' ) : '';
                my $width = $cols->[$i]{width};
                if ( !$width ) {
                    my ($tw) = $self->measure_text($label);
                    $width = ( $tw + 24 ) < 60 ? 60 : $tw + 24;
                }
                my $fmt  = ( { left => 0, center => 2, right => 1 }->{ $cols->[$i]{align} // 'left' } // 0 );
                my $wide = Encode::encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00";
                my $abuf = malloc( CORE::length($wide) );
                memcpy( $abuf, $wide, CORE::length($wide) );
                my $bytes = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4', 0x000F, $fmt, $width, Affix::address($abuf), 0, $i, 0, 0, 0, 0,
                    0, 0, 0, 0;
                my $struct = malloc( length $bytes );
                memcpy( $struct, $bytes, length $bytes );
                SendMessageW( $hwnd, 0x1061, $i, Affix::address($struct) );
                free($struct);
                free($abuf);
            }
            $lv->{ncols}    = scalar @$cols;
            $lv->{colorder} = [ 0 .. ( scalar @$cols ) - 1 ];
        }
        my $i = 0;
        for my $row ( @{ $node->rows // [] } ) {
            my $cells = ref $row eq 'HASH' ? $row->{columns} : $row;
            my $value = ref $row eq 'HASH' ? $row->{value}   : ( $cells->[0] // '' );
            push @{ $lv->{slots} }, { value => $value, columns => [ map { '' . ( $_ // '' ) } @{ $cells || [] } ] };
            $self->_lv_write_row( $hwnd, $i, $lv->{slots}[-1]{columns}, $node->columns );
            $i++;
        }
        if ( $lv->{sort} ) {
            $self->_sort_listview( $id, $lv->{sort}{col}, $lv->{sort}{dir}, $node->value );
        }
        else {
            $self->_select_listvalue( $id, $node->value );
        }
    }

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
            my $bytes  = pack $LVITEM, 0x0001, $row, $c, 0, 0, Affix::address($abuf), 0, 0, 0, 0, 0, 0, 0, 0, 0;
            my $struct = malloc( length $bytes );
            memcpy( $struct, $bytes, length $bytes );
            if ( $c == 0 ) {
                SendMessageW( $hwnd, 0x104D, $row, Affix::address($struct) );    # LVM_INSERTITEMW
            }
            else {
                SendMessageW( $hwnd, 0x104C, 0, Affix::address($struct) );       # LVM_SETITEMW
            }
            free($struct);
            free($abuf);
        }
    }

    method _sort_listview ( $id, $col, $dir, $want = 'snapshot' ) {
        my $rec   = $registry->{$id} or return;
        my $hwnd  = $rec->{hwnd}     or return;
        my $node  = $rec->{node}     or return;
        my $lv    = $rec->{listview} or return;
        my $ncols = $lv->{ncols} // 0;
        return if $col < 0 || $col >= $ncols;
        my $numeric = ( ( $node->columns->[$col] // {} )->{sort} // 'text' ) eq 'numeric';
        my %sel;

        if ( ref $want eq 'ARRAY' ) {
            $sel{$_} = 1 for map { ( $_ // '' ) } @$want;
        }
        elsif ( defined $want && $want ne 'snapshot' ) {
            $sel{ '' . $want } = 1;
        }
        else {
            for my $i ( 0 .. $#{ $lv->{slots} } ) {
                my $st = SendMessageW( $hwnd, 0x102C, $i, 0x0002 );
                $sel{ ( $lv->{slots}[$i]{value} // '' ) } = 1 if $st & 0x0002;
            }
        }
        my $cell = sub ($i) {
            my $cs = $lv->{slots}[$i]{columns};
            return $cs ? ( '' . ( $cs->[$col] // '' ) ) : '';
        };
        my @order = 0 .. $#{ $lv->{slots} };
        @order = sort {
            my $cmp = $numeric ? ( ( $cell->($a) + 0 ) <=> ( $cell->($b) + 0 ) ) : ( lc( $cell->($a) ) cmp lc( $cell->($b) ) );
            return $cmp if $cmp;
            ( ( $lv->{slots}[$a]{value} // '' ) cmp ( $lv->{slots}[$b]{value} // '' ) );
        } @order;
        @order = reverse @order if $dir eq 'desc';
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
        $suppress_events = 1;
        for my $i ( 0 .. $#{ $lv->{slots} } ) {
            next unless $sel{ $lv->{slots}[$i]{value} // '' };
            my $selb = pack $LVITEM, 0x0008, $i, 0, 0x0002, 0x0002, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;
            my $sbuf = malloc( length $selb );
            memcpy( $sbuf, $selb, length $selb );
            SendMessageW( $hwnd, 0x102B, $i, Affix::address($sbuf) );    # LVM_SETITEMSTATE
            free($sbuf);
        }
        $suppress_events = 0;
        for my $i ( 0 .. $#{ $lv->{slots} } ) {
            next unless $sel{ $lv->{slots}[$i]{value} // '' };
            SendMessageW( $hwnd, 0x1013, 1, $i );                        # LVM_ENSUREVISIBLE
            last unless $node->multiple;
        }
    }

    method lv_column_order ( $hwnd, $n ) {
        return [] unless $hwnd && $n > 0;
        my $buf = malloc( $n * 4 );
        SendMessageW( $hwnd, 0x103B, $n, Affix::address($buf) );    # LVM_GETCOLUMNORDERARRAY
        my $raw = Affix::raw( $buf, $n * 4 );
        free($buf);
        return [ unpack( ('l<') x $n, $raw ) ];
    }

    method list_view_click_column ( $node, $model_col ) {
        my $id     = $node->id                        or return;
        my $rec    = $self->_get_registry_record($id) or return;
        my $hwnd   = $rec->{hwnd}                     or return;
        my $parent = $rec->{parent_hwnd}              or return;
        my $nmhdr  = "\0" x 64;
        substr( $nmhdr, 0, 8 )  = pack( 'q<', $hwnd );
        substr( $nmhdr, 16, 4 ) = pack( 'l<', -108 );                # LVN_COLUMNCLICK
        substr( $nmhdr, 24, 4 ) = pack( 'l<', -1 );
        substr( $nmhdr, 28, 4 ) = pack( 'l<', $model_col );
        my $buf = malloc(64);
        memcpy( $buf, $nmhdr, 64 );
        SendMessageW( $parent, 0x004E, 0, Affix::address($buf) );    # WM_NOTIFY
        free($buf);
        for ( 1 .. 20 ) { $self->poll_events }
        return;
    }

    method _apply_sort_indicator ( $id, $from_col, $to_col, $dir ) {
        my $rec   = $registry->{$id} or return;
        my $hwnd  = $rec->{hwnd}     or return;
        my $node  = $rec->{node}     or return;
        my $lv    = $rec->{listview} or return;
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

    method _set_header_label ( $hwnd, $vis, $label ) {
        my $wide = Encode::encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00";
        my $abuf = malloc( CORE::length($wide) );
        memcpy( $abuf, $wide, CORE::length($wide) );
        my $bytes  = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4', 0x0004, 0, 0, Affix::address($abuf), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;
        my $struct = malloc( length $bytes );
        memcpy( $struct, $bytes, length $bytes );
        SendMessageW( $hwnd, 0x1060, $vis, Affix::address($struct) );    # LVM_SETCOLUMNW
        free($struct);
        free($abuf);
    }

    method _sync_column_orders () {
        return unless %$registry;
        for my $id ( keys %$registry ) {
            my $rec = $registry->{$id} or next;
            next unless $rec->{node} && $rec->{node}->type eq 'list_view' && $rec->{node}->reorderable;
            my $lv   = $rec->{listview} or next;
            my $hwnd = $rec->{hwnd}     or next;
            my $n    = $lv->{ncols} // 0;
            next unless $n;
            my $order = $self->lv_column_order( $hwnd, $n );
            my $have  = $lv->{colorder} ||= [ 0 .. $n - 1 ];
            my $same  = 1;
            for my $i ( 0 .. $n - 1 ) { $same = 0 if ( $order->[$i] // -1 ) != ( $have->[$i] // -1 ); }
            next if $same;
            $lv->{colorder} = $order;

            if ( $rec->{node}->can('on_reorder') && $rec->{node}->on_reorder ) {
                my $action = $rec->{node}->on_reorder->( [@$order] );
                $self->channel->put($action) if $action;
            }
        }
    }

    method _select_listvalue ( $id, $value ) {
        my $rec   = $registry->{$id} or return;
        my $hwnd  = $rec->{hwnd}     or return;
        my $lv    = $rec->{listview} or return;
        my $want  = ref $value eq 'ARRAY' ? $value : [ defined $value ? $value : () ];
        my $clear = pack $LVITEM, 0x0008, 0, 0, 0, 0x0002, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;
        my $cbuf  = malloc( length $clear );
        memcpy( $cbuf, $clear, length $clear );
        $suppress_events = 1;
        SendMessageW( $hwnd, 0x102B, -1, Affix::address($cbuf) );    # LVM_SETITEMSTATE(-1)
        free($cbuf);

        for my $i ( 0 .. $#{ $lv->{slots} } ) {
            next unless grep { ( $_ // '' ) eq ( $lv->{slots}[$i]{value} // '' ) } @$want;
            my $sel  = pack $LVITEM, 0x0008, $i, 0, 0x0002, 0x0002, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;
            my $sbuf = malloc( length $sel );
            memcpy( $sbuf, $sel, length $sel );
            SendMessageW( $hwnd, 0x102B, $i, Affix::address($sbuf) );    # LVM_SETITEMSTATE
            free($sbuf);
            SendMessageW( $hwnd, 0x1013, 1, $i );                        # LVM_ENSUREVISIBLE
        }
        $suppress_events = 0;
    }

    method _gdiplus_ensure () {
        return if $gdi_started;
        my $in = malloc(24);
        memcpy( $in, pack( 'L< x4 Q< L< L<', 1, 0, 0, 0 ), 24 );
        my $tok = malloc(8);
        my $st  = GdiplusStartup( Affix::address($tok), Affix::address($in), undef );
        $gdi_token   = unpack( 'Q<', Affix::raw( $tok, 8 ) ) if !$st;
        $gdi_started = 1;
        free($tok);
        free($in);
    }

    method _icon_hicon ( $spec, $size ) {
        $self->_gdiplus_ensure;
        my $key = "$spec\@$size";
        return $icon_cache->{$key} if exists $icon_cache->{$key};
        my ( $img, $w, $h ) = $self->_gdi_image($spec);
        return 0 unless $img;
        my $bmp = malloc(8);
        GdipCreateBitmapFromScan0( $size, $size, $size * 4, 0x0026200A, 0, Affix::address($bmp) );
        my $bm = unpack( 'Q<', Affix::raw( $bmp, 8 ) );
        my $g  = malloc(8);
        GdipGetImageGraphicsContext( $bm, Affix::address($g) );
        my $gc = unpack( 'Q<', Affix::raw( $g, 8 ) );
        GdipSetInterpolationMode( $gc, 7 );
        GdipDrawImageRectRectI( $gc, $img, 0, 0, $size, $size, 0, 0, $w, $h, 2, 0, 0, 0 );
        my $hic   = malloc(8);
        my $st2   = GdipCreateHICONFromBitmap( $bm, Affix::address($hic) );
        my $hicon = unpack( 'Q<', Affix::raw( $hic, 8 ) );
        GdipDeleteGraphics($gc);
        GdipDisposeImage($bm);
        GdipDisposeImage($img);
        free($g);
        free($bmp);
        free($hic);
        return 0 if $st2 != 0 || !$hicon;
        $icon_cache->{$key} = $hicon;
        return $hicon;
    }

    method _gdi_image ($spec) {
        $self->_gdiplus_ensure;
        return () unless defined $spec && length $spec;
        my ( $path, $tmp );
        if ( $spec =~ m{^data:image/[^;,]+;base64,(.*)$}s ) {
            require MIME::Base64;
            require File::Temp;
            my $bytes = MIME::Base64::decode_base64($1);
            my $fh;
            ( $fh, $path ) = File::Temp::tempfile( 'uji_img_XXXXXX', SUFFIX => '.png', OPEN => 1 );
            binmode $fh;
            print {$fh} $bytes;
            close $fh;
            $tmp = 1;
        }
        else {
            $path = $spec;
        }
        my $wpath = encode( 'UTF-16LE', $self->_nz($path) ) . "\x00\x00\x00\x00";
        my $wp    = malloc( CORE::length($wpath) );
        memcpy( $wp, $wpath, CORE::length($wpath) );
        my $imgp = malloc(8);
        my $st   = GdipLoadImageFromFile( Affix::address($wp), Affix::address($imgp) );
        free($wp);
        my $img = unpack( 'Q<', Affix::raw( $imgp, 8 ) );

        if ( $st != 0 || !$img ) {
            free($imgp);
            unlink $path if $tmp;
            return ();
        }
        my $uw = malloc(4);
        my $uh = malloc(4);
        GdipGetImageWidth( $img, Affix::address($uw) );
        GdipGetImageHeight( $img, Affix::address($uh) );
        my $w = unpack( 'L<', Affix::raw( $uw, 4 ) );
        my $h = unpack( 'L<', Affix::raw( $uh, 4 ) );
        free($uw);
        free($uh);
        unlink $path if $tmp;
        return ( $img, $w, $h );
    }

    method measure_image ($spec) {
        return ( 0, 0 ) unless defined $spec && length $spec;
        $self->_gdiplus_ensure;
        return @{ $img_dims->{$spec} } if $img_dims->{$spec};
        my ( $img, $w, $h ) = $self->_gdi_image($spec);
        return ( 0, 0 ) unless $img;
        GdipDisposeImage($img);
        $img_dims->{$spec} = [ $w, $h ] if $w && $h;
        return ( $w, $h );
    }

    method _raster_hbitmap ( $spec, $w, $h, $fit ) {
        $self->_gdiplus_ensure;
        $fit //= 'contain';
        return 0 unless defined $spec && length $spec;
        $w = 16 if $w < 1;
        $h = 16 if $h < 1;
        my $key = "$spec\@$w\@$h\@$fit";
        return $bitmap_cache->{$key} if exists $bitmap_cache->{$key};
        my ( $img, $iw, $ih ) = $self->_gdi_image($spec);
        return 0 unless $img && $iw && $ih;
        my $bmp = malloc(8);
        GdipCreateBitmapFromScan0( $w, $h, $w * 4, 0x0026200A, 0, Affix::address($bmp) );
        my $bm = unpack( 'Q<', Affix::raw( $bmp, 8 ) );
        my $g  = malloc(8);
        GdipGetImageGraphicsContext( $bm, Affix::address($g) );
        my $gc = unpack( 'Q<', Affix::raw( $g, 8 ) );
        GdipSetInterpolationMode( $gc, 7 );
        my ( $dx, $dy, $dw, $dh, $sx, $sy, $sw, $sh ) = ( 0, 0, 0, 0, 0, 0, 0, 0 );

        if ( $fit eq 'fill' ) {
            ( $dw, $dh, $sw, $sh ) = ( $w, $h, $iw, $ih );
        }
        elsif ( $fit eq 'cover' ) {
            my $scale = $w / $iw > $h / $ih ? $w / $iw : $h / $ih;
            $sw = int( $w / $scale );
            $sh = int( $h / $scale );
            $sx = int( ( $iw - $sw ) / 2 );
            $sy = int( ( $ih - $sh ) / 2 );
            ( $dw, $dh ) = ( $w, $h );
        }
        else {
            my $scale = $w / $iw < $h / $ih ? $w / $iw : $h / $ih;
            $dw = int( $iw * $scale );
            $dh = int( $ih * $scale );
            $dx = int( ( $w - $dw ) / 2 );
            $dy = int( ( $h - $dh ) / 2 );
            ( $sw, $sh ) = ( $iw, $ih );
        }
        GdipDrawImageRectRectI( $gc, $img, $dx, $dy, $dw, $dh, $sx, $sy, $sw, $sh, 2, 0, 0, 0 );
        my $hbm = malloc(8);
        my $st  = GdipCreateHBITMAPFromBitmap( $bm, Affix::address($hbm), 0x00F0F0F0 );
        GdipDeleteGraphics($gc);
        GdipDisposeImage($bm);
        GdipDisposeImage($img);
        free($g);
        free($bmp);
        my $hbitmap = unpack( 'Q<', Affix::raw( $hbm, 8 ) );
        free($hbm);
        return 0 if $st != 0 || !$hbitmap;
        $bitmap_cache->{$key} = $hbitmap;
        return $hbitmap;
    }

    method _paint_canvas ($hwnd) {
        $self->_gdiplus_ensure;
        my $rec  = $self->_get_registry_by_hwnd($hwnd) or return 0;
        my $node = $rec->{node}                        or return 0;
        my $cr   = malloc( sizeof( RECT() ) );
        GetClientRect( $hwnd, $cr );
        my $rect = cast( $cr, RECT() );
        my $w    = $rect->{right} - $rect->{left};
        my $h    = $rect->{bottom} - $rect->{top};
        free($cr);
        return 0 if $w < 1 || $h < 1;
        my $ps  = malloc( sizeof( PAINTSTRUCT() ) );
        my $hdc = BeginPaint( $hwnd, $ps );
        my $bmp = malloc(8);
        GdipCreateBitmapFromScan0( $w, $h, $w * 4, 0x0026200A, 0, Affix::address($bmp) );
        my $bm = unpack( 'Q<', Affix::raw( $bmp, 8 ) );
        my $g  = malloc(8);
        GdipGetImageGraphicsContext( $bm, Affix::address($g) );
        my $gc = unpack( 'Q<', Affix::raw( $g, 8 ) );
        GdipSetSmoothingMode( $gc, 2 );
        my $bg   = $node->background // '#F0F0F0';
        my $draw = Uji::Draw::Win32->new( gc => $gc, w => $w, h => $h );
        $draw->clear($bg);

        if ( my $cb = $node->on_draw ) {
            $cb->($draw);
        }
        my $hbm = malloc(8);
        GdipCreateHBITMAPFromBitmap( $bm, Affix::address($hbm), 0x00F0F0F0 );
        GdipDeleteGraphics($gc);
        GdipDisposeImage($bm);
        free($g);
        free($bmp);
        my $hb = unpack( 'Q<', Affix::raw( $hbm, 8 ) );
        free($hbm);

        if ($hb) {
            my $mem = CreateCompatibleDC($hdc);
            my $old = SelectObject( $mem, $hb );
            BitBlt( $hdc, 0, 0, $w, $h, $mem, 0, 0, 0x00CC0020 );    # SRCCOPY
            SelectObject( $mem, $old );
            DeleteDC($mem);
            DeleteObject($hb);
        }
        EndPaint( $hwnd, $ps );
        free($ps);
        return 0;
    }

    method _spinner_frames ( $size, $color ) {
        $self->_gdiplus_ensure;
        $color //= '#2e5d8c';
        $size = 24 if $size < 16;
        my $key = join '@', $size, $color;
        return $spin_cache->{$key} if $spin_cache->{$key};
        my $hex = $color;
        $hex =~ s/^#//;
        my $rgb   = hex $hex;
        my $argb  = 0xFF000000 | ( ( $rgb & 0xFF ) << 16 ) | ( $rgb & 0x00FF00 ) | ( ( $rgb >> 16 ) & 0xFF );
        my $pen_w = ( $size / 8 ) < 2 ? 2 : $size / 8;
        my ( @pens, @pen_objs );

        for my $i ( 0 .. 10 ) {
            my $alpha = int( 255 - ( 255 * $i / 11 ) );
            my $pp    = malloc(8);
            GdipCreatePen1( ( $alpha << 24 ) | ( $argb & 0x00FFFFFF ), $pen_w, 2, Affix::address($pp) );
            push @pen_objs, $pp;
            push @pens,     unpack( 'Q<', Affix::raw( $pp, 8 ) );
        }
        my ( $cx, $cy ) = ( $size / 2, $size / 2 );
        my $ro   = $size / 2 - 2;
        my $ri   = $ro / 2;
        my $step = 360 / 12;
        my @frames;
        for my $f ( 0 .. 11 ) {
            my $bmp = malloc(8);
            GdipCreateBitmapFromScan0( $size, $size, $size * 4, 0x0026200A, 0, Affix::address($bmp) );
            my $bm = unpack( 'Q<', Affix::raw( $bmp, 8 ) );
            my $g  = malloc(8);
            GdipGetImageGraphicsContext( $bm, Affix::address($g) );
            my $gc = unpack( 'Q<', Affix::raw( $g, 8 ) );
            GdipSetSmoothingMode( $gc, 2 );
            for my $k ( 0 .. 10 ) {
                my $rad = ( $f * $step + $k * $step ) * 3.14159265358979 / 180;
                my ( $x1, $y1 ) = ( $cx + $ri * cos($rad), $cy + $ri * sin($rad) );
                my ( $x2, $y2 ) = ( $cx + $ro * cos($rad), $cy + $ro * sin($rad) );
                GdipDrawLineI( $gc, $pens[$k], int $x1, int $y1, int $x2, int $y2 );
            }
            my $hic = malloc(8);
            GdipCreateHICONFromBitmap( $bm, Affix::address($hic) );
            my $hicon = unpack( 'Q<', Affix::raw( $hic, 8 ) );
            GdipDeleteGraphics($gc);
            GdipDisposeImage($bm);
            free($g);
            free($bmp);
            free($hic);
            push @frames, $hicon if $hicon;
        }
        for my $i ( 0 .. $#pen_objs ) { GdipDeletePen( $pens[$i] ); free( $pen_objs[$i] ); }
        $spin_cache->{$key} = \@frames;
        return \@frames;
    }

    method _populate_toolbar ( $id, $buttons = undef ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $node = $rec->{node}     or return;
        $buttons //= $node->buttons;
        my $old_cnt = SendMessageW( $hwnd, 0x0418, 0, 0 );
        SendMessageW( $hwnd, 0x0416, 0, 0 ) while $old_cnt-- > 0;
        my $tb = $rec->{toolbar} ||= { by_cmd => {}, himl => 0 };
        for my $cmd ( keys %{ $tb->{by_cmd} } ) {
            delete $toolbar_cmds->{$cmd};
        }
        $tb->{by_cmd} = {};
        if ( my $old = delete $tb->{himl} ) {
            SendMessageW( $hwnd, 0x0430, 0, 0 );
            ImageList_Destroy($old);
        }
        return unless @$buttons;
        my $is = $node->icon_size // 16;
        my %icon_idx;
        {
            my $i = 0;
            for my $b (@$buttons) {
                next unless $b->{icon} && !exists $icon_idx{ $b->{icon} };
                $icon_idx{ $b->{icon} } = $i++;
            }
        }
        if (%icon_idx) {
            my $himl = ImageList_Create( $is, $is, 0x20, 0, 1 );
            my $ok   = 0;
            for my $spec ( sort { $icon_idx{$a} <=> $icon_idx{$b} } keys %icon_idx ) {
                my $hicon = $self->_icon_hicon( $spec, $is ) or next;
                my $got   = ImageList_AddIcon( $himl, $hicon );
                if ( $got >= 0 ) {
                    $ok++;
                    $icon_idx{$spec} = $got;
                }
                else {
                    delete $icon_idx{$spec};
                }
            }
            if ($ok) {
                $tb->{himl} = $himl;
                SendMessageW( $hwnd, 0x0430, 0, Affix::address($himl) );
            }
            else {
                ImageList_Destroy($himl);
            }
        }
        my @structs;
        for my $b (@$buttons) {
            if ( $b->{separator} ) {
                push @structs, pack 'l< l< C C x6 q< q<', ( $b->{width} // 6 ), 0, 0, 0x01, 0, 0;
                next;
            }
            my $label = $b->{label} // '';
            my $wide  = encode( 'UTF-16LE', $self->_nz($label) ) . "\x00\x00\x00\x00";
            my $str   = malloc( CORE::length($wide) );
            memcpy( $str, $wide, CORE::length($wide) );
            my $str_idx = SendMessageW( $hwnd, 0x044D, 0, Affix::address($str) );    # TB_ADDSTRINGW
            free($str);
            my $cmd  = $cmd_counter++;
            my $fsSt = 0x04;
            $fsSt |= 0x01  if $b->{checked};
            $fsSt &= ~0x04 if defined $b->{enabled} && !$b->{enabled};
            my $iBitmap = ( $b->{icon} && exists $icon_idx{ $b->{icon} } ) ? $icon_idx{ $b->{icon} } : -2;
            push @structs, pack 'l< l< C C x6 q< q<', $iBitmap, $cmd, $fsSt, 0x02, 0, $str_idx;
            my $bid = $b->{id} // $label;
            $tb->{by_cmd}{$cmd} = { id => $bid, iBitmap => $iBitmap };
            $toolbar_cmds->{$cmd} = $id;
        }
        my $body = join '', @structs;
        my $arr  = malloc( CORE::length($body) );
        memcpy( $arr, $body, CORE::length($body) );
        SendMessageW( $hwnd, 0x0444, scalar @structs, Affix::address($arr) );    # TB_ADDBUTTONSW
        free($arr);
        SendMessageW( $hwnd, 0x0421, 0, 0 );                                     # TB_AUTOSIZE
    }

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

    method _append_menu_items ( $hmenu, $items, $win_id, $mrec ) {
        for my $it ( @{ $items // [] } ) {
            if ( $it->{separator} ) {
                AppendMenuW( $hmenu, 0x0800, 0, '' );
                next;
            }
            my $label = $self->_nz( $it->{label} // '' );
            if ( $it->{children} && @{ $it->{children} } ) {
                my $sub = CreatePopupMenu();
                $self->_append_menu_items( $sub, $it->{children}, $win_id, $mrec );
                AppendMenuW( $hmenu, 0x0010, $sub, $label );
                next;
            }
            my $cmd   = $cmd_counter++;
            my $flags = 0x0000;
            $flags |= 0x0001 unless $it->{enabled} // 1;
            $flags |= 0x0008 if $it->{checked};
            AppendMenuW( $hmenu, $flags, $cmd, $label );
            $mrec->{by_cmd}{$cmd} = { id => $it->{id} // $label };
            $menu_cmds->{$cmd} = { win_id => $win_id };
        }
    }

    method _select_tree_value ( $id, $value ) {
        my $rec  = $registry->{$id} or return;
        my $hwnd = $rec->{hwnd}     or return;
        my $t    = $rec->{tree}     or return;
        return unless defined $value;
        my $slot = $t->{by_value}{$value};
        return unless defined $slot;
        my $hitem = $t->{slots}[$slot]{hitem};
        return unless $hitem;
        SendMessageW( $hwnd, 0x110B, 0x0009, $hitem );
        SendMessageW( $hwnd, 0x1114, 0,      $hitem );
    }

    method _apply_tab ($id) {
        my $rec  = $registry->{$id} or return;
        my $node = $rec->{node}     or return;
        my $idx  = $rec->{index} // 0;
        my $i    = 0;
        for my $child ( @{ $node->children } ) {
            $self->_set_branch_visible( $child, 0 ) if $i != $idx;
            $i++;
        }
        if ( my $tab_hw = $rec->{hwnd} ) {
            SetWindowPos( $tab_hw, cast( 1, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );
            UpdateWindow($tab_hw);
        }
        if ( my $active = $node->children->[$idx] ) {
            $self->_set_branch_visible( $active, 1 );
        }
    }

    method _set_branch_visible ( $node, $vis ) {
        if ( my $rec = $registry->{ $node->id } ) {
            if ( my $hwnd = $rec->{hwnd} ) {
                if ($vis) {
                    ShowWindow( $hwnd, 5 );
                    SetWindowPos( $hwnd, cast( 0, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );
                    InvalidateRect( $hwnd, undef, 1 );
                    UpdateWindow($hwnd);
                }
                else {
                    ShowWindow( $hwnd, 0 );
                }
            }
            for my $auxkey (qw[ aux aux_h aux_v ]) {
                my $aux = $rec->{$auxkey} or next;
                if ($vis) {
                    ShowWindow( $aux, 5 );
                    SetWindowPos( $aux, cast( 0, Pointer [Void] ), 0, 0, 0, 0, 0x0013 );
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

    method _mark_scrolled ( $node, $store ) {
        return if $node->type eq 'scroll_view';
        if ( my $rec = $registry->{ $node->id } ) {
            $rec->{scroll} = $store;
        }
        $self->_mark_scrolled( $_, $store ) for @{ $node->children };
    }

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

    method unmount_subtree ($node) {
        if ( my $rec = $registry->{ $node->id } ) {
            my $hw = $rec->{hwnd};
            DestroyWindow( $rec->{aux} ) if $rec->{aux};
            if ($hw) {
                DestroyWindow($hw);
                delete $surface_by_hwnd->{$hw};
            }
            delete $cid_to_id->{ $rec->{cid} } if $rec->{cid};
            delete $registry->{ $node->id };
        }
        $self->unmount_subtree($_) for @{ $node->children };
    }

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
        my $flags = 0x4 | 0x8 | 0x800 | 0x80000;

        if ( $mode eq 'save' ) {
            my $op = defined $o{overwrite_prompt} ? $o{overwrite_prompt} : 1;
            $flags |= 0x2 if $op;
        }
        else {
            $flags |= 0x1000 unless $o{no_file_must_exist};
            $flags |= 0x200 if $o{multi};
        }
        $ofn->{Flags} = $flags;
        return ( $struct, [ $ofn, $filebuf, $filterbuf, $titlebuf, $initbuf ] );
    }

    method _ofn_free ( $struct, $parts ) {
        for my $i ( 1 .. $#$parts ) { free( $parts->[$i] ) if $parts->[$i]; }
        free($struct);
    }
    method _get_prompt_edit ()    {$prompt_edit}
    method _set_prompt_value ($v) { $prompt_value = $v }
    method _prompt_finish ()      { $prompt_done  = 1 }

    method prompt_dialog (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        my $hook  = $o{hook};
        $prompt_done  = 0;
        $prompt_value = undef;
        my $dlg = CreateWindowExW( 0, $prompt_class, $self->_nz( $o{title} // 'Prompt' ), 0x80C00000, 200, 200, 380, 160, $owner, 0, 0, 0 );
        return undef unless $dlg;
        $prompt_hwnd = $dlg;
        $self->_theme_control($dlg);
        $self->_set_font($dlg);
        my $msg_text = CreateWindowExW( 0, 'STATIC', $self->_nz( $o{message} // '' ), 0x50000000, 14, 10, 340, 40, $dlg, 0, 0, 0 );
        $self->_theme_control($msg_text);
        $self->_set_font($msg_text);
        my $yes = CreateWindowExW( 0, 'EDIT', $self->_nz( $o{default} // '' ), 0x50810080, 14, 60, 340, 24, $dlg, 0, 0, 0 );
        $self->_theme_control($yes);
        my $ok     = CreateWindowExW( 0, 'BUTTON', 'OK',     0x50000000, 240, 100, 60, 26, $dlg, 1, 0, 0 );
        my $cancel = CreateWindowExW( 0, 'BUTTON', 'Cancel', 0x50000000, 306, 100, 60, 26, $dlg, 2, 0, 0 );
        $self->_theme_control($ok);
        $self->_set_font($ok);
        $self->_theme_control($cancel);
        $self->_set_font($cancel);
        $prompt_edit = $yes;
        ShowWindow( $dlg, 5 );
        SetFocus($prompt_edit);
        $hook->( $dlg, $prompt_edit ) if $hook;
        my $msg_ptr = malloc(48);

        while ( !$prompt_done ) {
            my $gm = GetMessageW( $msg_ptr, undef, 0, 0 );
            last if $gm <= 0;
            TranslateMessage($msg_ptr);
            no warnings 'uninitialized';
            DispatchMessageW($msg_ptr);
            $on_modal_pump->() if $on_modal_pump;
        }
        free($msg_ptr);
        DestroyWindow($dlg);
        return defined $prompt_value ? $prompt_value : undef;
    }

    # Native dialogs with active modal-pump arming (timer ID 1 ticks $on_modal_pump)
    method file_open_dialog (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        SetTimer( $owner, 1, 16, undef ) if $owner && $on_modal_pump;
        my ( $struct, $parts ) = $self->_ofn_build( 'open', %o );
        my $ok  = GetOpenFileNameW($struct);
        my $res = $ok ? $self->_ofn_parse_result( $parts->[1], 32768 * 2, $o{multi} ) : undef;
        $self->_ofn_free( $struct, $parts );
        KillTimer( $owner, 1 ) if $owner && $on_modal_pump;
        return $res;
    }

    method file_save_dialog (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        SetTimer( $owner, 1, 16, undef ) if $owner && $on_modal_pump;
        my ( $struct, $parts ) = $self->_ofn_build( 'save', %o );
        my $ok  = GetSaveFileNameW($struct);
        my $res = $ok ? $self->_ofn_parse_result( $parts->[1], 32768 * 2, 0 ) : undef;
        $self->_ofn_free( $struct, $parts );
        KillTimer( $owner, 1 ) if $owner && $on_modal_pump;
        return $res;
    }

    method _mb_flags (%o) {
        my %btn   = ( ok    => 0x0,  okcancel => 0x1,  abortretryignore => 0x2, yesnocancel => 0x3, yesno => 0x4, retrycancel => 0x5 );
        my %ico   = ( error => 0x10, question => 0x20, warning => 0x30, info => 0x40 );
        my $flags = ( $btn{ $o{buttons} // 'ok' } // 0x0 );
        $flags |= $ico{ $o{icon} }                if $o{icon};
        $flags |= ( 0x100 * ( $o{default} - 1 ) ) if $o{default} && $o{default} >= 2 && $o{default} <= 3;
        return $flags;
    }
    my %MB_RESULT
        = ( 1 => 'ok', 2 => 'cancel', 3 => 'abort', 4 => 'retry', 5 => 'ignore', 6 => 'yes', 7 => 'no', 10 => 'tryagain', 11 => 'continue' );

    method message_box (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        SetTimer( $owner, 1, 16, undef ) if $owner && $on_modal_pump;
        my $rc = MessageBoxW( $owner, $self->_nz( $o{message} ), $self->_nz( $o{title} // 'Uji' ), $self->_mb_flags(%o) );
        KillTimer( $owner, 1 ) if $owner && $on_modal_pump;
        return $MB_RESULT{$rc};
    }

    method color_picker (%o) {
        my $owner = $o{owner} // $main_hwnd // 0;
        SetTimer( $owner, 1, 16, undef ) if $owner && $on_modal_pump;
        my $struct = malloc( sizeof( CHOOSECOLORW() ) );
        my $cc     = cast( $struct, CHOOSECOLORW() );
        my $custom = calloc( 16, 4 );
        my $flags  = 0x1 | 0x100;
        $flags |= 0x2 if $o{full_open};
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
        KillTimer( $owner, 1 ) if $owner && $on_modal_pump;
        return $res;
    }

    method _show_context_menu ( $record, $lparam ) {
        my $node = $record->{node} or return;
        my ( $screen_x, $screen_y );
        my $lx = $lparam & 0xFFFF;
        my $ly = ( $lparam >> 16 ) & 0xFFFF;
        $lx -= 0x10000 if $lx > 0x7FFF;
        $ly -= 0x10000 if $ly > 0x7FFF;

        # If triggered via keyboard (Shift+F10 / Apps key), query current cursor position
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
        my $items;
        if ( ref $menu_def eq 'CODE' ) {
            my $target_info = undef;

            # If right-clicking a ListView, hit-test both row AND column
            if ( $node->type eq 'list_view' ) {
                my $pt_buf = malloc( sizeof( POINT() ) );
                my $pt     = cast( $pt_buf, POINT() );
                $pt->{x} = $screen_x;
                $pt->{y} = $screen_y;
                ScreenToClient( $record->{hwnd}, $pt_buf );

                # Packed binary LVHITTESTINFO (24 bytes): POINT (8B) + flags (4B) + iItem (4B) + iSubItem (4B)
                my $ht_buf = malloc(24);
                memcpy( $ht_buf, pack( 'l<2 L< l<2', $pt->{x}, $pt->{y}, 0, -1, -1 ), 24 );

                # LVM_SUBITEMHITTEST (0x1039) fills iItem and iSubItem
                SendMessageW( $record->{hwnd}, 0x1039, 0, Affix::address($ht_buf) );
                my ( undef, undef, undef, $hit_row, $hit_col ) = unpack( 'l<2 L< l<2', Affix::raw( $ht_buf, 24 ) );
                free($ht_buf);
                free($pt_buf);
                $hit_col = 0 if !defined $hit_col || $hit_col < 0;
                if ( defined $hit_row && $hit_row >= 0 ) {
                    my $lv    = $record->{listview};
                    my $slot  = ( $lv && $lv->{slots} ) ? $lv->{slots}[$hit_row] : undef;
                    my $cells = $slot                   ? $slot->{columns}       : undef;
                    if ( !$cells && $node->rows && $hit_row < @{ $node->rows } ) {
                        my $r = $node->rows->[$hit_row];
                        $cells = ref $r eq 'HASH' ? ( $r->{columns} // [] ) : $r;
                    }
                    $cells //= [];
                    my $orig_row;
                    if ( $node->rows ) {
                        if ( $slot && defined $slot->{value} ) {
                            ($orig_row) = grep { ref $_ eq 'HASH' && ( ( $_->{value} // '' ) eq $slot->{value} ) } @{ $node->rows };
                        }
                        $orig_row //= $node->rows->[$hit_row] if $hit_row < @{ $node->rows };
                    }
                    my $value = $slot ? $slot->{value} : ( $cells->[0] // '' );
                    $target_info = { index => $hit_row, col => $hit_col, cell => $cells->[$hit_col], value => $value, columns => $cells };
                    if ( ref $orig_row eq 'HASH' ) {
                        for my $k ( keys %$orig_row ) {
                            $target_info->{$k} //= $orig_row->{$k};
                        }
                    }
                    my $cols = $node->columns // [];
                    for my $c ( 0 .. $#$cols ) {
                        my $col_def = $cols->[$c];
                        my $val     = $cells->[$c];
                        if ( ref $col_def eq 'HASH' ) {
                            for my $key_field (qw[ id label text ]) {
                                if ( defined $col_def->{$key_field} && length $col_def->{$key_field} ) {
                                    my $k = $col_def->{$key_field};
                                    $target_info->{$k} //= $val;
                                    $target_info->{ lc $k } //= $val;
                                }
                            }
                        }
                    }
                }
            }
            $items = $menu_def->($target_info);
        }
        elsif ( ref $menu_def eq 'ARRAY' ) {
            $items = $menu_def;
        }
        return unless $items && ref $items eq 'ARRAY' && @$items;
        my $hpopup = CreatePopupMenu();
        my $mrec   = { by_cmd => {} };
        $self->_append_menu_items( $hpopup, $items, $record->{surface} // 'main', $mrec );

        # TPM_RIGHTBUTTON (0x0002): allow left- or right-click to select items
        TrackPopupMenuEx( $hpopup, 0x0002, $screen_x, $screen_y, $main_hwnd, undef );
        DestroyMenu($hpopup);
    }

    method _draw_push_button ( $node, $di, $record ) {
        my $hdc          = $di->{hDC} or return;
        my $r            = $di->{rcItem};
        my $sel          = ( $di->{itemState} & 0x0001 ) ? 1         : 0;    # ODS_SELECTED (pressed)
        my $disabled     = ( $di->{itemState} & 0x0004 ) ? 1         : 0;    # ODS_DISABLED
        my $focus        = ( $di->{itemState} & 0x0010 ) ? 1         : 0;    # ODS_FOCUS
        my $fill_color   = $disabled                     ? '#202020' : $sel ? '#1F1F24' : ( $node->background // '#333337' );
        my $border_color = $disabled                     ? '#3A3A3A' : $sel ? '#5CA8FF' : '#555555';
        my $text_color   = $disabled                     ? '#6A6A6A' : ( $node->color // '#E6E6E6' );
        my $face         = CreateSolidBrush( $self->_gdi_colorref($fill_color) );
        my $border       = CreateSolidBrush( $self->_gdi_colorref($border_color) );
        my $rp           = malloc( sizeof( RECT() ) );
        my $rr           = cast( $rp, RECT() );
        ( $rr->{left}, $rr->{top}, $rr->{right}, $rr->{bottom} ) = ( $r->{left}, $r->{top}, $r->{right}, $r->{bottom} );
        FillRect( $hdc, $rp, $face );
        FrameRect( $hdc, $rp, $border );
        free($rp);
        DeleteObject($face);
        DeleteObject($border);
        my $label = $node->label // '';

        if ( CORE::length($label) ) {
            my $hfont = $self->_get_font( $node->font, $node->font_size );
            my $old   = SelectObject( $hdc, $hfont ) if $hfont;
            SetBkMode( $hdc, 1 );    # TRANSPARENT
            SetTextColor( $hdc, $self->_gdi_colorref($text_color) );
            my $tp = malloc( sizeof( RECT() ) );
            my $tr = cast( $tp, RECT() );
            ( $tr->{left}, $tr->{top}, $tr->{right}, $tr->{bottom} )
                = ( $r->{left} + $sel, $r->{top} + $sel, $r->{right} + $sel, $r->{bottom} + $sel );
            DrawTextW( $hdc, $self->_nz($label), -1, $tp, 0x0825 );    # DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX
            free($tp);
            SelectObject( $hdc, $old ) if $old;
        }
        if ($focus) {
            my $fp = malloc( sizeof( RECT() ) );
            my $fr = cast( $fp, RECT() );
            ( $fr->{left}, $fr->{top}, $fr->{right}, $fr->{bottom} ) = ( $r->{left} + 3, $r->{top} + 3, $r->{right} - 3, $r->{bottom} - 3 );
            DrawFocusRect( $hdc, $fp );
            free($fp);
        }
    }

    method _handle_list_view_custom_draw ( $record, $lparam ) {
        my $node = $record ? $record->{node} : undef;
        return ( 0, undef ) unless $node && $node->grid_lines && ( $self->uses_dark_mode || $node->grid_color );

        # Read the 64-bit NMCUSTOMDRAW buffer directly
        my $raw   = Affix::raw( $lparam, 64 );
        my $stage = unpack( 'L<', substr( $raw, 24, 4 ) );    # dwDrawStage at offset 24
        if ( $stage == 0x00000001 ) {                         # CDDS_PREPAINT
            return ( 1, 0x00000020 );                         # CDRF_NOTIFYITEMDRAW
        }
        if ( $stage == 0x00010001 ) {                         # CDDS_ITEMPREPAINT
            return ( 1, 0x00000020 | 0x00000010 );            # CDRF_NOTIFYSUBITEMDRAW | CDRF_NOTIFYPOSTPAINT
        }
        if ( $stage == 0x00030001 ) {                         # CDDS_SUBITEM | CDDS_ITEMPREPAINT
            return ( 1, 0x00000010 );                         # CDRF_NOTIFYPOSTPAINT
        }
        if ( $stage == 0x00030002 || $stage == 0x00010002 ) {    # CDDS_ITEMPOSTPAINT
            my $hdc_int = unpack( 'Q<', substr( $raw, 32, 8 ) );                # hdc at offset 32
            return ( 1, 0 ) unless $hdc_int;
            my $hdc = cast( $hdc_int, Pointer [Void] );
            my ( $l, $t, $r, $b ) = unpack( 'l<4', substr( $raw, 40, 16 ) );    # RECT at offset 40
            my $color = $node->grid_color ? $self->_parse_color( $node->grid_color ) : ( $self->uses_dark_mode ? 0x003D3A3A : 0x00D0D0D0 );
            my $pen   = CreatePen( 0, 1, $color );
            my $old   = SelectObject( $hdc, $pen );
            MoveToEx( $hdc, $l, $b - 1, undef );
            LineTo( $hdc, $r, $b - 1 );
            MoveToEx( $hdc, $r - 1, $t, undef );
            LineTo( $hdc, $r - 1, $b );
            SelectObject( $hdc, $old );
            DeleteObject($pen);
            return ( 1, 0 );                                                    # CDRF_DODEFAULT
        }
        return ( 0, undef );
    }
};
1;
