use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::MenuItem v0.0.1 : isa(Uji::Node) {
    field $label    : param : reader = '';
    field $on_click : param : reader = undef;
    field $checked  : param : reader = 0;
    field $shortcut : param : reader = undef;    # e.g. "Ctrl+O"
    sub _type {'menu_item'}
};
1;
