use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Canvas v0.0.1 : isa(Uji::Node) {
    field $on_draw : param : reader = undef;    # code ref: sub ($draw) { ... }
    field $redraw  : param : reader = 0;        # bump to force a repaint
    sub _type {'canvas'}
};
1;