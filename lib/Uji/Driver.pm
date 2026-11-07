use v5.40;
use experimental 'class';
class Uji::Driver v0.0.1 {    # Base class/factory for OS detection

    sub detect () {
        require Uji::Driver::Win32;
        return Uji::Driver::Win32->new() if $^O eq 'MSWin32';
        die 'Unsupported platform: ' . $^O;    # TODO: GTK4, Cocoa
    }
    method init ($channel) {...}
    method poll_events ()  {...}
    method mount              ($vtree)                {...}
    method set_prop           ( $id, $prop, $val )    {...}
    method move_widget        ( $id, $x, $y, $w, $h ) {...}
    method destroy_widget     ($id)                   {...}
    method update_registry    ($node)                 {...}
    method sync_window_bounds ($vtree)                {...}

    # System dialogs (blocking on native drivers; MockDriver supplies canned responses)
    method message_box      (%o) {...}
    method file_open_dialog (%o) {...}
    method file_save_dialog (%o) {...}
    method color_picker     (%o) {...}
    method prompt_dialog    (%o) {...}

    # Portable simulation seam: tests invoke this instead of platform WM_* messages
    method list_view_click_column ( $node, $model_col ) {...}
};
1;
