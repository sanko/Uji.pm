use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Toolbar v0.0.1 : isa(Uji::Node) {
    field $buttons  : param : reader = [];       # [{ label => '', id => '', separator => 0, checked => 0, enabled => 1 }]
    field $on_click : param : reader = undef;    # sub ($id) { ... }
    sub _type {'toolbar'}
};
1;
