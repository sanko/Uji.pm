use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Overlay v0.0.1 : isa(Uji::Node) {
    field $children : param : reader = [];
    field $padding  : param : reader = 0;
    sub _type {'overlay'}
};
1;