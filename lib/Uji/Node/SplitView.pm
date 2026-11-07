use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::SplitView v0.0.1 : isa(Uji::Node) {
    field $children    : param = [];
    field $orientation : param : reader = 'vertical';    # 'vertical' | 'horizontal'
    field $divider     : param : reader = undef;         # pixel offset along main axis
    field $divider_w   : param : reader = 6;
    field $min_a       : param : reader = 40;
    field $min_b       : param : reader = 40;
    field $on_divider  : param : reader = undef;
    sub _type          {'split_view'}
    method children () {$children}
};
1;
