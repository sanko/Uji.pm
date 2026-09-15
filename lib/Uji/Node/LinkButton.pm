use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::LinkButton v0.0.1 : isa(Uji::Node) {
    field $label    : param : reader = '';
    field $on_click : param : reader = undef;
    sub _type {'link_button'}
};
1;