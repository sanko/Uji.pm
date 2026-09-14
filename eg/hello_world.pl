use v5.40;
use experimental 'class';
my $NEXT_ID = 100;

class Uji::Node {    # Base class for all VDOM nodes
    field $id : param : reader : writer //= __CLASS__->_rand_id;
    sub _rand_id { CORE::state $id //= 100; ++$id; }
    field $type : reader = __CLASS__->_type;
    field $x    : param : reader = 0;
    field $y    : param : reader = 0;
    field $w    : param : reader = 0;
    field $h    : param : reader = 0;
    field $flex : param : reader = 0;

    method set_bounds ( $nx, $ny, $nw, $nh ) {
        $x = $nx;
        $y = $ny;
        $w = $nw;
        $h = $nh;
    }
    method children () { [] }
}

class Uji::Node::Button : isa(Uji::Node) {
    field $label    : param : reader = '';
    field $on_click : param : reader = undef;
    sub _type {'button'}
};

class Uji::Node::Text : isa(Uji::Node) {
    field $label : param : reader = '';
    sub _type {'text'}
}

class Uji::Node::TextInput : isa(Uji::Node) {
    field $value    : param : reader = '';
    field $on_input : param : reader = undef;
    sub _type {'text_input'}
}

class Uji::Node::Slider : isa(Uji::Node) {
    field $value     : param : reader = 0;
    field $min       : param : reader = 0;
    field $max       : param : reader = 100;
    field $on_change : param : reader = undef;
    sub _type {'slider'}
}

class Uji::Node::Column : isa(Uji::Node) {
    field $children : param : reader = [];
    field $padding  : param : reader = 10;
    field $spacing  : param : reader = 10;
    sub _type {'column'}
}

class Uji::Node::Row : isa(Uji::Node) {
    field $children : param : reader = [];
    field $padding  : param : reader = 0;
    field $spacing  : param : reader = 10;
    sub _type {'row'}
}

class Uji::Node::Window : isa(Uji::Node) {
    field $title : param : reader = 'Uji Application';
    field $child : param : reader = undef;
    sub _type          {'window'}
    method children () { $child ? [$child] : [] }
};

class Uji::Layout {

    method compute ( $node, $start_x = 0, $start_y = 0, $avail_w = 800, $avail_h = 600 ) {
        my $w = $node->w || $avail_w;
        my $h = $node->h || 30;
        $node->set_bounds( $start_x, $start_y, $w, $h );
        if ( $node->type eq 'window' ) {
            $self->compute( $node->child, 0, 0, $node->w, $node->h ) if $node->child;
        }
        elsif ( $node->type eq 'column' ) {
            $self->_layout_flex( $node, 'vertical', $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'row' ) {
            $self->_layout_flex( $node, 'horizontal', $start_x, $start_y, $w, $h );
        }
    }

    method _layout_flex ( $container, $dir, $x, $y, $w, $h ) {
        my $children = $container->children;
        return unless @$children;
        my $pad        = $container->can('padding') ? $container->padding : 0;
        my $spc        = $container->can('spacing') ? $container->spacing : 0;
        my $inner_x    = $x + $pad;
        my $inner_y    = $y + $pad;
        my $inner_w    = $w - ( $pad * 2 );
        my $inner_h    = $h - ( $pad * 2 );
        my $is_col     = ( $dir eq 'vertical' );
        my $main_avail = ( $is_col ? $inner_h : $inner_w ) - ( ( @$children - 1 ) * $spc );
        my $total_flex = 0;
        my $used_fixed = 0;

        for my $child (@$children) {
            my $flx = $child->can('flex') ? $child->flex : 0;
            if   ( $flx > 0 ) { $total_flex += $flx; }
            else              { $used_fixed += $is_col ? ( $child->h || 30 ) : ( $child->w || 100 ); }
        }
        my $remain = $main_avail - $used_fixed;
        $remain = 0 if $remain < 0;
        my $cx = $inner_x;
        my $cy = $inner_y;
        for my $child (@$children) {
            my $flx = $child->can('flex') ? $child->flex : 0;
            my ( $cw, $ch );
            if ($is_col) {
                $cw = $inner_w;
                $ch = $flx > 0 ? int( ( $flx / $total_flex ) * $remain ) : ( $child->h || 30 );
                $self->compute( $child, $cx, $cy, $cw, $ch );
                $cy += $ch + $spc;
            }
            else {
                $ch = $inner_h;
                $cw = $flx > 0 ? int( ( $flx / $total_flex ) * $remain ) : ( $child->w || 100 );
                $self->compute( $child, $cx, $cy, $cw, $ch );
                $cx += $cw + $spc;
            }
        }
    }
};

class Uji::Driver {    # Base class/factory for OS detection

    sub detect () {
        return Uji::Driver::Win32->new() if $^O eq 'MSWin32';
        die 'Unsupported platform: ' . $^O;    # TODO
    }
    method init ($channel) {...}
    method poll_events ()  {...}
    method mount              ($vtree)                {...}
    method set_prop           ( $id, $prop, $val )    {...}
    method move_widget        ( $id, $x, $y, $w, $h ) {...}
    method destroy_widget     ($id)                   {...}
    method update_registry    ($node)                 {...}
    method sync_window_bounds ($vtree)                {...}
};

class Uji::Driver::Win32 : isa(Uji::Driver) {

    # user32.dll, gdi32.dll
    use Affix  qw[:memory :types :core];
    use Encode qw[decode];
    field $channel;
    field $registry;
    field $wndproc_cb;
    field $main_hwnd;
    field $suppress_events : reader(_is_suppressed) = 0;
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
        affix 'user32', 'ShowWindow',       [ Pointer [Void], Int ]                                      => Int;
        affix 'user32', 'SetWindowTextW',   [ Pointer [Void], WString ]                                  => Int;
        affix 'user32', 'SetWindowPos',     [ Pointer [Void], Pointer [Void], Int, Int, Int, Int, UInt ] => Int;
        affix 'user32', 'DefWindowProcW',   [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;
        affix 'user32', 'PeekMessageW',     [ Pointer [Void], Pointer [Void], UInt, UInt, UInt ]         => Int;
        affix 'user32', 'TranslateMessage', [ Pointer [Void] ]                                           => Int;
        affix 'user32', 'DispatchMessageW', [ Pointer [Void] ]                                           => SSize_t;
        affix 'user32', 'UpdateWindow',     [ Pointer [Void] ]                                           => Int;
        affix 'user32', 'InvalidateRect',   [ Pointer [Void], Pointer [Void], Int ]                      => Int;
        affix 'user32', 'LoadCursorW',      [ Pointer [Void], Size_t ]                                   => Pointer [Void];
        affix 'user32', 'SendMessageW',     [ Pointer [Void], UInt, Size_t, SSize_t ]                    => SSize_t;

        # Read native control text
        affix 'user32', 'GetWindowTextLengthW', [ Pointer [Void] ]                      => Int;
        affix 'user32', 'GetWindowTextW',       [ Pointer [Void], Pointer [Void], Int ] => Int;
        affix 'user32', 'GetClientRect',        [ Pointer [Void], Pointer [Void] ]      => Int;
        typedef RECT => Struct [ left => Int, top => Int, right => Int, bottom => Int ];

        # Common controls (trackbar/slider, etc.)
        typedef INITCOMMONCONTROLSEX => Struct [ dwSize => ULong, dwICC => ULong ];
        affix 'comctl32', 'InitCommonControlsEx', [ Pointer [ INITCOMMONCONTROLSEX() ] ] => Int;
        my $icc   = malloc( sizeof( INITCOMMONCONTROLSEX() ) );
        my $icc_s = cast( $icc, INITCOMMONCONTROLSEX() );
        $icc_s->{dwSize} = sizeof( INITCOMMONCONTROLSEX() );
        $icc_s->{dwICC}  = 0x00000004;                         # ICC_BAR_CLASSES (includes trackbars)
        InitCommonControlsEx($icc);
        free($icc);
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
                        $self_ref->_get_channel->put( $node->on_click );
                    }

                    # EN_CHANGE (0x0300) -> Text changed by user typing
                    elsif ( $notify_code == 0x0300 && $node->can('on_input') && $node->on_input ) {

                        # Ignore EN_CHANGE if triggered programmatically by SetWindowTextW!
                        return DefWindowProcW( $hwnd, $msg, $wparam, $lparam ) if $self_ref->_is_suppressed;
                        my $text       = $self_ref->_get_text( $record->{hwnd} );
                        my $action_msg = $node->on_input->($text);
                        $self_ref->_get_channel->put($action_msg) if $action_msg;
                    }
                }
            }
            elsif ( $msg == 0x0002 ) {    # WM_DESTROY
                $self_ref->_get_channel->put( { type => 'QUIT' } );
            }
            elsif ( $msg == 0x0114 ) {    # WM_HSCROLL -> slider/trackbar drag
                my $slider_hwnd = $lparam;
                my $record      = $self_ref->_get_registry_by_hwnd($slider_hwnd);
                if ($record) {
                    my $node = $record->{node};
                    if ( $node->can('on_change') && $node->on_change ) {
                        my $pos = SendMessageW( $slider_hwnd, 0x0400, 0, 0 );    # TBM_GETPOS
                        my $msg = $node->on_change->($pos);
                        $self_ref->_get_channel->put($msg) if $msg;
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
        my $buf = malloc( ( $len + 1 ) * sizeof(WChar) );

        # GetWindowTextW returns the EXACT number of characters copied
        my $copied = GetWindowTextW( $hwnd, $buf, $len + 1 );

        # Read the raw UTF-16 bytes directly from C memory
        my $raw_bytes = Affix::raw( $buf, $copied * sizeof(WChar) );
        free($buf);

        # Decode directly to Perl UTF-8 without touching C pointer types
        return Encode::decode( 'UTF-16LE', $raw_bytes );
    }
    method _get_registry_record ($id) { $registry->{$id} }

    method _get_registry_by_hwnd ($hwnd) {
        for my $id ( keys %$registry ) {
            return $registry->{$id} if $registry->{$id}{hwnd} == $hwnd;
        }
        return undef;
    }
    method _get_channel () {$channel}

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };
    }

    method mount ($vtree) {
        $main_hwnd = CreateWindowExW( 0, 'UjiWindowClass', $vtree->title, 0x10CF0000, 100, 100, $vtree->w, $vtree->h, undef, 0, undef, undef );
        $registry->{ $vtree->id } = { hwnd => $main_hwnd, node => $vtree };

        # Lay out against the real client area: the outer size includes the
        # title bar and borders, so we re-measure and fix up the window node
        # before children are computed.
        my ( $cw, $ch ) = $self->_get_client_size($main_hwnd);
        $vtree->set_bounds( 0, 0, $cw, $ch );
        ShowWindow( $main_hwnd, 5 );
        UpdateWindow($main_hwnd);
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

    method poll_events () {
        my $msg_ptr = malloc(48);
        while ( PeekMessageW( $msg_ptr, undef, 0, 0, 1 ) ) {
            TranslateMessage($msg_ptr);
            DispatchMessageW($msg_ptr);
        }
        free($msg_ptr);
    }

    method _mount_node ( $vnode, $parent_hwnd ) {
        my ( $class, $style, $initial_text );
        if ( $vnode->type eq 'button' ) {
            $class        = 'BUTTON';
            $style        = 0x50000001;            # WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text' ) {
            $class        = 'STATIC';
            $style        = 0x50000000;            # WS_CHILD | WS_VISIBLE
            $initial_text = $vnode->label // '';
        }
        elsif ( $vnode->type eq 'text_input' ) {
            $class = 'EDIT';

            # WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL
            $style        = 0x50800080;
            $initial_text = $vnode->value // '';
        }
        elsif ( $vnode->type eq 'slider' ) {
            $class = 'msctls_trackbar32';

            # WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS | TBS_HORZ
            $style = 0x50000001;
        }
        else {
            foreach my $child ( @{ $vnode->children } ) {
                $self->_mount_node( $child, $parent_hwnd );
            }
            return;
        }
        my $hwnd
            = CreateWindowExW( 0, $class, $initial_text, $style, $vnode->x, $vnode->y, $vnode->w, $vnode->h, $parent_hwnd, $vnode->id, undef, undef );
        $registry->{ $vnode->id } = { hwnd => $hwnd, node => $vnode };
        if ( $vnode->type eq 'slider' ) {

            # TBM_SETRANGE (0x0406): (max << 16) | min, wParam = redraw
            SendMessageW( $hwnd, 0x0406, 1, ( $vnode->max << 16 ) | $vnode->min );
            SendMessageW( $hwnd, 0x0405, 1, $vnode->value );    # TBM_SETPOS
        }
    }

    method set_prop ( $vnode_id, $prop_name, $value ) {
        my $record = $registry->{$vnode_id};
        return unless $record;
        if ( $prop_name eq 'label' ) {
            SetWindowTextW( $record->{hwnd}, $value );
            InvalidateRect( $record->{hwnd}, undef, 1 );
        }
        elsif ( $prop_name eq 'value' ) {
            if ( $record->{node}->type eq 'slider' ) {
                SendMessageW( $record->{hwnd}, 0x0405, 1, $value );
                return;
            }

            # Only update if the native control differs (prevents typing cursor jump)
            my $current = $self->_get_text( $record->{hwnd} );
            if ( $current ne $value ) {
                $suppress_events = 1;
                SetWindowTextW( $record->{hwnd}, $value );
                $suppress_events = 0;

                # SetWindowTextW snaps the caret to position 0; move it to the end.
                my $len = length $value;
                SendMessageW( $record->{hwnd}, 0x00B1, $len, $len );
            }
        }
        elsif ( $prop_name eq 'min' || $prop_name eq 'max' ) {
            return unless $record->{node}->type eq 'slider';
            my $min = $prop_name eq 'min' ? $value : $record->{node}->min;
            my $max = $prop_name eq 'max' ? $value : $record->{node}->max;
            SendMessageW( $record->{hwnd}, 0x0406, 1, ( $max << 16 ) | $min );
        }
    }

    method move_widget ( $vnode_id, $x, $y, $w, $h ) {
        my $record = $registry->{$vnode_id};
        return unless $record;
        SetWindowPos( $record->{hwnd}, undef, $x, $y, $w, $h, 0x0004 );
    }
}

class Uji::Driver::GTK4 : isa(Uji::Driver) {

    # libgtk-4.so, libglib-2.0.so
}

class Uji::Driver::Cocoa : isa(Uji::Driver) {    # libobjc.A.dylib (macOS Runtime)
}

class Uji::Reconciler {    # VDOM diffing and patching engine

    method patch ( $old_node, $new_node, $driver ) {
        return unless $old_node && $new_node;
        $new_node->set_id( $old_node->id );
        $driver->update_registry($new_node);

        # Check label (Text/Buttons)
        if ( $old_node->can('label') && $new_node->can('label') ) {
            if ( $old_node->label ne $new_node->label ) {
                $driver->set_prop( $new_node->id, 'label', $new_node->label );
            }
        }

        # Check value (TextInput, Slider)
        if ( $old_node->can('value') && $new_node->can('value') ) {
            if ( $old_node->value ne $new_node->value ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }

        # Check range (Slider)
        if ( $old_node->can('min') && $old_node->can('max') ) {
            if ( $old_node->min ne $new_node->min ) {
                $driver->set_prop( $new_node->id, 'min', $new_node->min );
            }
            if ( $old_node->max ne $new_node->max ) {
                $driver->set_prop( $new_node->id, 'max', $new_node->max );
            }
        }

        # Check Bounds (skip window — its size is managed by the OS)
        if ( $old_node->type ne 'window' ) {
            if ( $old_node->x != $new_node->x || $old_node->y != $new_node->y || $old_node->w != $new_node->w || $old_node->h != $new_node->h ) {
                $driver->move_widget( $new_node->id, $new_node->x, $new_node->y, $new_node->w, $new_node->h );
            }
        }
        my $old_children = $old_node->children;
        my $new_children = $new_node->children;
        my $max          = @$old_children > @$new_children ? @$old_children : @$new_children;
        for my $i ( 0 .. $max - 1 ) {
            my $old_child = $old_children->[$i];
            my $new_child = $new_children->[$i];
            if ( $old_child && $new_child ) {
                $self->patch( $old_child, $new_child, $driver );
            }
        }
    }
};

class Uji::App {    # The TEA Runtime (Parataxis fibers & message loop)
    use Acme::Parataxis          qw[async fiber await_sleep];
    use Acme::Parataxis::Channel qw[];
    field $init   : param;
    field $update : param;
    field $view   : param;
    field $model;
    field $vtree;
    field $channel    : param //= Acme::Parataxis::Channel->new( capacity => 1024 );
    field $driver     : param //= Uji::Driver::detect();
    field $reconciler : param //= Uji::Reconciler->new();
    field $layout     : param //= Uji::Layout->new();

    method run () {
        $driver->init($channel);
        async {
            ( $model, my $cmd ) = $init->();
            $vtree = $view->($model);

            # Mount window first so we can measure its real client area,
            # then compute layout against that, then create the child widgets.
            $driver->mount($vtree);
            $layout->compute($vtree);
            $driver->mount_children($vtree);
            fiber {
                while (1) {
                    $driver->poll_events();
                    await_sleep(2);
                }
            };
            fiber {
                while ( my $msg = $channel->get() ) {
                    exit(0) if ref $msg eq 'HASH' && $msg->{type} eq 'QUIT';

                    # Drain the whole queue in one pass so fast typing collapses
                    # into a single render with the latest state (no stale writes).
                    my @batch = ($msg);
                    push @batch, $channel->get() while $channel->size;
                    for my $m (@batch) {
                        exit(0) if ref $m eq 'HASH' && $m->{type} eq 'QUIT';
                        ( my $new_model, my $new_cmd ) = $update->( $m, $model );
                        $model = $new_model;
                    }
                    my $new_vtree = $view->($model);
                    $driver->sync_window_bounds($new_vtree);
                    $layout->compute($new_vtree);
                    $reconciler->patch( $vtree, $new_vtree, $driver );
                    $vtree = $new_vtree;
                }
            };
        };
    }
};

package Uji {
    use v5.40;
    use Exporter 'import';
    our @EXPORT = qw[app window column row text button text_input slider];
    sub app        (%args)  { Uji::App->new(%args) }
    sub window     (%args)  { Uji::Node::Window->new(%args) }
    sub column     (%args)  { Uji::Node::Column->new(%args) }
    sub row        (%args)  { Uji::Node::Row->new(%args) }
    sub text       ($label) { Uji::Node::Text->new( label => $label ) }
    sub button     (%args)  { Uji::Node::Button->new(%args) }
    sub text_input (%args)  { Uji::Node::TextInput->new(%args) }
    sub slider     (%args)  { Uji::Node::Slider->new(%args) }
};
#
package main {
    use v5.40;

    sub init () {
        return ( { name => 'World', count => 0, level => 5 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_NAME' ) {
            $model->{name} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'INCREMENT' ) {
            $model->{count} += 1;
        }
        elsif ( $msg->{type} eq 'SET_LEVEL' ) {
            $model->{level} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'RESET' ) {
            $model->{count} = 0;
            $model->{name}  = 'World';
            $model->{level} = 5;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title => 'Uji.pm Flexbox Demo',
            w     => 360,
            h     => 300,
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    (    # Live two-way text binding
                        Uji::text( 'Hello, ' . $model->{name} . '!' ),
                        Uji::text_input( value => $model->{name}, on_input => sub ($text) { { type => 'SET_NAME', value => $text } } )
                    ), (
                        # Range slider with live on_change binding
                        Uji::text( 'Level: ' . $model->{level} ),
                        Uji::slider( value => $model->{level}, min => 0, max => 10, on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } } )
                    ), (
                        # Horizontal row with proportional flex buttons
                        Uji::text( 'Counter: ' . $model->{count} ),
                        Uji::row(
                            spacing  => 10,
                            children => [

                                # flex => 2 gets twice the width of flex => 1
                                Uji::button( label => '+1',    flex => 2, on_click => { type => 'INCREMENT' } ),
                                Uji::button( label => 'Reset', flex => 1, on_click => { type => 'RESET' } )
                            ]
                        )
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
