use v5.40;
use experimental 'class';
class Uji::Node v0.0.1 {    # Base class for all VDOM nodes
    field $id : param : reader : writer //= __CLASS__->_rand_id;
    sub _rand_id { CORE::state $id //= 100; ++$id; }
    field $type         : reader = __CLASS__->_type;
    field $x            : param : reader = 0;        # requested x
    field $y            : param : reader = 0;        # requested y
    field $w            : param : reader = 0;        # requested w
    field $h            : param : reader = 0;        # requested h
    field $flex         : param : reader = 0;
    field $fit          : param : reader = undef;    # fit policy ('fill'|'content'|'fixed')
    field $fit_w        : param : reader = undef;    # per-axis override of $fit
    field $fit_h        : param : reader = undef;
    field $min_w        : param : reader = 0;        # computed-size clamps (0 = unconstrained)
    field $min_h        : param : reader = 0;
    field $max_w        : param : reader = 0;
    field $max_h        : param : reader = 0;
    field $align_w      : param : reader = undef;    # cross-axis alignment ('start'|'center'|'end'|'stretch')
    field $align_h      : param : reader = undef;
    field $enabled      : param : reader = 1;
    field $visible      : param : reader = 1;
    field $tooltip      : param : reader = undef;
    field $context_menu : param : reader = undef;    # arrayref of items or sub ($target) -> [...]
    field $color        : param : reader = undef;    # foreground text colour ('#RRGGBB')
    field $background   : param : reader = undef;    # background fill colour ('#RRGGBB')
    field $font         : param : reader = undef;    # font family name (undef = default GUI font)
    field $font_size    : param : reader = undef;    # point size (undef = default ~9pt)
    field $bx           : reader = 0;                # computed bounds (set per layout pass)
    field $by           : reader = 0;
    field $bw           : reader = 0;
    field $bh           : reader = 0;

    method set_bounds ( $nx, $ny, $nw, $nh ) {
        $bx = $nx;
        $by = $ny;
        $bw = $nw;
        $bh = $nh;
    }
    method children () { [] }

    # Resolve the fit policy for one axis ('w' or 'h') to 'fill' | 'content' | 'fixed'
    method fit_policy ($axis) {
        my $p = $axis eq 'w' ? ( $fit_w // $fit ) : ( $fit_h // $fit );
        return undef unless defined $p;
        return 'fill'    if $p eq 'fill'    || $p eq 'stretch';
        return 'content' if $p eq 'content' || $p eq 'fit' || $p eq 'shrink';
        return 'fixed'   if $p eq 'fixed';
        die "Uji::Node: unknown fit policy '$p' (expected fill/stretch, content/fit/shrink, or fixed)";
    }

    # Resolve the alignment policy for one axis ('w' or 'h') to 'start'|'center'|'end'|'stretch'
    method align_policy ($axis) {
        my $p = $axis eq 'w' ? $align_w : $align_h;
        return undef unless defined $p;
        return 'start'   if $p eq 'start';
        return 'center'  if $p eq 'center';
        return 'end'     if $p eq 'end';
        return 'stretch' if $p eq 'stretch';
        die "Uji::Node: unknown align policy '$p' (expected start, center, end, or stretch)";
    }

    # Props that require native control recreation when changed (mount-time-only styles)
    method _mount_only_props () { [] }
};
1;
