use v5.40;
use experimental 'class';
class Uji::Node v0.0.1 {    # Base class for all VDOM nodes
    field $id : param : reader : writer //= __CLASS__->_rand_id;
    field $key : param : reader = undef;
    sub _rand_id { CORE::state $id //= 100; ++$id; }
    field $type       : reader = __CLASS__->_type;
    field $x          : param : reader = 0;        # requested x
    field $y          : param : reader = 0;        # requested y
    field $w          : param : reader = 0;        # requested w
    field $h          : param : reader = 0;        # requested h
    field $min_w      : param : reader = 0;        # minimum width constraint
    field $min_h      : param : reader = 0;        # minimum height constraint
    field $max_w      : param : reader = 0;        # maximum width constraint (0 = unconstrained)
    field $max_h      : param : reader = 0;        # maximum height constraint (0 = unconstrained)
    field $flex       : param : reader = 0;        # flex growth factor (0 = fixed or intrinsic)
    field $align_self : param : reader = undef;    # cross-axis override: 'start', 'center', 'end', 'stretch'
    field $enabled    : param : reader = 1;
    field $visible    : param : reader = 1;
    field $tooltip    : param : reader = undef;
    field $bx         : reader = 0;                # computed bounds (set per layout pass)
    field $by         : reader = 0;
    field $bw         : reader = 0;
    field $bh         : reader = 0;

    # Clamp a proposed (width, height) against the node's min/max constraints
    method clamp_size ( $cw, $ch ) {
        $cw = $min_w if $min_w && $cw < $min_w;
        $cw = $max_w if $max_w && $cw > $max_w;
        $ch = $min_h if $min_h && $ch < $min_h;
        $ch = $max_h if $max_h && $ch > $max_h;
        return ( $cw, $ch );
    }

    # set_bounds writes the computed geometry so compute() can re-derive from avail_sizes every
    # pass without stale 'requested' w/h shadowing
    method set_bounds ( $nx, $ny, $nw, $nh ) {
        $bx = $nx;
        $by = $ny;
        $bw = $nw;
        $bh = $nh;
    }
    method children () { [] }
};
1;
