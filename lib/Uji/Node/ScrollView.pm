use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ScrollView v0.0.1 : isa(Uji::Node) {
    field $child       : param : reader = undef;         # scrolled content (single subtree)
    field $orientation : param : reader = 'vertical';    # vertical | horizontal | both
    field $scroll_x    : param : reader = 0;             # current scroll offset (px)
    field $scroll_y    : param : reader = 0;
    field $on_scroll   : param : reader = undef;         # sub ($x, $y) -> update
    field $_kids       : reader = undef;
    sub _type {'scroll_view'}

    # Renaming axes or switching orientation recreates the whole viewport control.
    method _mount_only_props { ['orientation'] }
    method children ()       { return $_kids if $_kids; my @k = $child ? ($child) : (); $_kids = \@k; return $_kids; }
};
1;
