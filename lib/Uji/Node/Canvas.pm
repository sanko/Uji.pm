use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Canvas v0.0.1 : isa(Uji::Node) {
    field $on_draw : param : reader = undef;    # sub ($draw) { ... }
    field $redraw  : param : reader = 0;        # bump counter to trigger repaints
    sub _type {'canvas'}
};
1;
