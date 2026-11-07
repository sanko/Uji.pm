use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Spinner v0.0.1 : isa(Uji::Node) {
    field $size    : param : reader = 24;
    field $speed   : param : reader = 80;    # ms/frame
    field $running : param : reader = 1;
    sub _type {'spinner'}
};
1;
