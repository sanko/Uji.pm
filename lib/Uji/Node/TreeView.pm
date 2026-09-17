use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::TreeView v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = undef;
    field $nodes     : param : reader = [];
    field $expanded  : param : reader = [];
    field $on_select : param : reader = undef;
    sub _type {'tree_view'}
};
1;
