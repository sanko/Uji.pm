use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ScrollView v0.0.1 : isa(Uji::Node) {
    field $child     : param : reader = undef;
    field $hscroll   : param : reader = 'auto';    # 'auto', 'always', 'never'
    field $vscroll   : param : reader = 'auto';    # 'auto', 'always', 'never'
    field $scroll_x  : param : reader = 0;
    field $scroll_y  : param : reader = 0;
    field $on_scroll : param : reader = undef;
    field $content_w : reader = 0;                 # computed natural width of scrollable canvas
    field $content_h : reader = 0;                 # computed natural height of scrollable canvas
    sub _type          {'scroll_view'}
    method children () { $child ? [$child] : [] }

    method set_content_size ( $cw, $ch ) {
        $content_w = $cw;
        $content_h = $ch;
    }
};
1;
