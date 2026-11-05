use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Row v0.0.1 : isa(Uji::Node) {
    field $children : param : reader = [];
    field $padding  : param : reader = 0;
    field $spacing  : param : reader = 10;
    field $align    : param : reader = 'center';    # cross-axis alignment: 'center', 'stretch', 'start', 'end'
    sub _type {'row'}
};
1;
