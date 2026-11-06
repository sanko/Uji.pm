use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::SplitView v0.0.1 : isa(Uji::Node) {
    field $orientation   : param : reader = 'horizontal';    # 'horizontal' or 'vertical'
    field $split         : param : reader = 0.5;             # fraction 0.0 .. 1.0
    field $first         : param : reader = undef;           # first pane (left or top)
    field $second        : param : reader = undef;           # second pane (right or bottom)
    field $min_first     : param : reader = 60;              # minimum size (px) of first pane
    field $min_second    : param : reader = 60;              # minimum size (px) of second pane
    field $splitter_size : param : reader = 6;               # thickness of the draggable bar (px)
    field $on_change     : param : reader = undef;

    # Computed splitter bar geometry
    field $bar_bx : reader = 0;
    field $bar_by : reader = 0;
    field $bar_bw : reader = 0;
    field $bar_bh : reader = 0;
    sub _type {'split_view'}

    method children () {
        my @c;
        push @c, $first  if $first;
        push @c, $second if $second;
        return \@c;
    }

    method set_bar_bounds ( $nx, $ny, $nw, $nh ) {
        $bar_bx = $nx;
        $bar_by = $ny;
        $bar_bw = $nw;
        $bar_bh = $nh;
    }
};
1;
