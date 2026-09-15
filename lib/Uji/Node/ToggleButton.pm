use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ToggleButton v0.0.1 : isa(Uji::Node) {
    field $label     : param : reader = '';
    field $checked   : param : reader = 0;
    field $on_toggle : param : reader = undef;
    sub _type {'toggle_button'}
};
1;
