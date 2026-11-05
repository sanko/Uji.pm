use v5.40;
use experimental 'class';
class Uji::Driver v0.0.1 {    # Base class/factory for OS detection

    sub detect () {
        require Uji::Driver::Win32;
        return Uji::Driver::Win32->new() if $^O eq 'MSWin32';
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
};
1;
