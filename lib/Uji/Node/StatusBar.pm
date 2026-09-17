use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::StatusBar v0.0.1 : isa(Uji::Node) {
    field $label  : param : reader = '';    # single-pane text (part 0)
    field $panels : param : reader = [];    # list of pane texts; when non-empty it overrides label
    sub _type {'status_bar'}
};
1;
