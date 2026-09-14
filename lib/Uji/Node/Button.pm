use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Button v0.0.1 : isa(Uji::Node) {
    field $label    : param : reader = '';
    field $on_click : param : reader = undef;
    sub _type {'button'}
};
1;
