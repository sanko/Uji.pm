use v5.40;
use experimental 'class';
class Uji::Driver v0.0.1 {    # Base class/factory for OS detection

    sub detect () {
        require Uji::Driver::Win32;
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

    # System dialogs (blocking on real drivers; Mock should override with canned values).
    method message_box      (%o) {...}
    method file_open_dialog (%o) {...}
    method file_save_dialog (%o) {...}
    method color_picker     (%o) {...}
    method prompt_dialog    (%o) {...}
};
1;
