use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Column v0.0.1 : isa(Uji::Node) {
    field $children : param : reader = [];
    field $padding  : param : reader = 10;
    field $spacing  : param : reader = 10;
    sub _type {'column'}
};
1;
