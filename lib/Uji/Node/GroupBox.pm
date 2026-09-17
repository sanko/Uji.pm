use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::GroupBox v0.0.1 : isa(Uji::Node) {
    field $label    : param : reader = '';
    field $children : param : reader = [];
    field $padding  : param : reader = 8;
    field $spacing  : param : reader = 6;
    sub _type {'group_box'}
};
1;
