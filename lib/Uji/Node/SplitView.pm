use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::SplitView v0.0.1 : isa(Uji::Node) {
    field $children    : param = [];                     # exactly two panes (the split's sub-trees)
    field $orientation : param : reader = 'vertical';    # vertical (top/bottom panes) | horizontal (left/right)
    field $divider     : param : reader = undef;         # divider offset in px along the main axis (undef = centered)
    field $divider_w   : param : reader = 6;             # drag handle thickness
    field $min_a       : param : reader = 40;            # min main-axis extent of the first pane (px)
    field $min_b       : param : reader = 40;            # min main-axis extent of the second pane (px)
    field $on_divider  : param : reader = undef;         # sub ($pos) -> update (fired on drag)
    sub _type          {'split_view'}
    method children () {$children}
};
1;
