use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ColorButton v0.0.1 : isa(Uji::Node) {
    field $show_hex  : param : reader = 1;
    field $on_change : param : reader = undef;
    sub _type {'color_button'}
};
1;
