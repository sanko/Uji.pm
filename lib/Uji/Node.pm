use v5.40;
use experimental 'class';
class Uji::Node v0.0.1 {    # Base class for all VDOM nodes
    field $id : param : reader : writer //= __CLASS__->_rand_id;
    sub _rand_id { CORE::state $id //= 100; ++$id; }
    field $type    : reader = __CLASS__->_type;
    field $x       : param : reader = 0;       # requested x
    field $y       : param : reader = 0;       # requested y
    field $w       : param : reader = 0;       # requested w
    field $h       : param : reader = 0;       # requested h
    field $flex    : param : reader = 0;
    field $enabled : param : reader = 1;
    field $visible : param : reader = 1;
    field $tooltip : param : reader = undef;
    field $bx      : reader = 0;               # computed bounds (set per layout pass)
    field $by      : reader = 0;
    field $bw      : reader = 0;
    field $bh      : reader = 0;

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
