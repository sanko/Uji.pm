use v5.40;
use experimental 'class';
class Uji::Driver v0.0.1 {    # Base class/factory for OS detection
    field $on_resize : reader(_get_resize_handler) = undef;

    sub detect () {
        if ( $^O eq 'MSWin32' ) {
            require Uji::Driver::Win32;
            return Uji::Driver::Win32->new();
        }
        if ( $^O eq 'darwin' ) {
            require Uji::Driver::macOS;
            return Uji::Driver::macOS->new();
        }
        require Uji::Driver::GTK4;
        return Uji::Driver::GTK4->new();
        die 'Unsupported platform: ' . $^O;
    }
    method init ($channel) {...}
    method poll_events ()  {...}
    method mount              ($vtree)                            {...}
    method mount_children     ($vtree)                            {...}
    method mount_widget       ( $vnode, $parent_node_id = undef ) {...}
    method set_prop           ( $id, $prop, $val )                {...}
    method move_widget        ( $id, $x, $y, $w, $h )             {...}
    method destroy_widget     ($id)                               {...}
    method update_registry    ($node)                             {...}
    method sync_window_bounds ($vtree)                            {...}
    method set_resize_handler ($cb)                               { $on_resize = $cb; $self }
};
1;
