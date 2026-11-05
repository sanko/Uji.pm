use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::GroupBox v0.0.1 : isa(Uji::Node) {
    field $label   : param : reader = '';
    field $child   : param : reader = undef;
    field $padding : param : reader = 12;
    sub _type          {'group_box'}
    method children () { $child ? [$child] : [] }
};
1;
