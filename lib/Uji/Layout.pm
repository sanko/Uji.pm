use v5.40;
use experimental 'class';
class Uji::Layout v0.0.1 {
    field $driver : param : reader;

    # Natural (content) size of a node measured through the driver
    method _intrinsic ($node) {
        my $t = $node->type;
        if ( $t eq 'text' || $t eq 'button' ) {
            my $label = $node->label // '';
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 24, $th += 10 if $t eq 'button';
            return ( $tw, $th );
        }
        if ( $t eq 'checkbox' || $t eq 'radio' ) {
            my $label = $node->label // '';
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 24, $th += 4;    # checkbox box / radio circle + text
            return ( $tw, $th );
        }
        if ( $t eq 'text_input' || $t eq 'password' ) {
            my $val = $node->value // '';
            my $tw  = length $val ? ( $driver && $driver->can('measure_text') ? ( $driver->measure_text($val) )[0] : length($val) * 8 ) : 80;
            $tw += 16;
            return ( $tw < 80 ? 80 : $tw, 20 );
        }
        if ( $t eq 'slider' ) {
            return ( 120, 26 );
        }
        if ( $t eq 'column' || $t eq 'radio_group' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my ( $w, $h ) = ( $pad * 2, $pad * 2 );
            for my $i ( 0 .. $#$children ) {
                my ( $cw, $ch ) = $self->_intrinsic( $children->[$i] );
                $w = $cw if $cw > $w;
                $h += $ch;
                $h += $spc if $i < $#$children;
            }
            return ( $w, $h );
        }
        if ( $t eq 'row' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my ( $w, $h ) = ( $pad * 2, $pad * 2 );
            for my $i ( 0 .. $#$children ) {
                my ( $cw, $ch ) = $self->_intrinsic( $children->[$i] );
                $h = $ch if $ch > $h;
                $w += $cw;
                $w += $spc if $i < $#$children;
            }
            return ( $w, $h );
        }
        return ( 100, 30 );
    }

    method compute ( $node, $start_x = 0, $start_y = 0, $avail_w = 800, $avail_h = 600 ) {
        my ( $w, $h );
        if ( $node->type eq 'window' ) {

            # Window node: size is the *measured* client area, refreshed by mount /
            # sync_window_bounds / _relayout_now via set_bounds()
            $w = $node->bw || $avail_w;
            $h = $node->bh || $avail_h;
        }
        else {
            $w = $node->w || $avail_w;
            $h = $node->h || ( $node->type eq 'column' || $node->type eq 'row' ? $avail_h : 30 );

            # Containers without an explicit size fill their parent; leaves that lack an explicit
            # height shrink to their content (intrinsic size).
            if ( $node->type ne 'column' && $node->type ne 'row' && !$node->h ) {
                my ( $iw, $ih ) = $self->_intrinsic($node);
                $h = $ih;
            }
        }
        $node->set_bounds( $start_x, $start_y, $w, $h );
        if ( $node->type eq 'window' ) {
            $self->compute( $node->child, 0, 0, $w, $h ) if $node->child;
        }
        elsif ( $node->type eq 'column' || $node->type eq 'radio_group' ) {
            $self->_layout_flex( $node, 'vertical', $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'row' ) {
            $self->_layout_flex( $node, 'horizontal', $start_x, $start_y, $w, $h );
        }
    }

    method _layout_flex ( $container, $dir, $x, $y, $w, $h ) {
        my $children = $container->children;
        return unless @$children;
        my $pad        = $container->can('padding') ? $container->padding : 0;
        my $spc        = $container->can('spacing') ? $container->spacing : 0;
        my $inner_x    = $x + $pad;
        my $inner_y    = $y + $pad;
        my $inner_w    = $w - ( $pad * 2 );
        my $inner_h    = $h - ( $pad * 2 );
        my $is_col     = ( $dir eq 'vertical' );
        my $main_avail = ( $is_col ? $inner_h : $inner_w ) - ( ( @$children - 1 ) * $spc );
        my $total_flex = 0;
        my $used_fixed = 0;
        my %nat;    # natural cross/main sizes cached per child

        for my $child (@$children) {
            my $flx = $child->can('flex') ? $child->flex : 0;
            my ( $nw, $nh ) = $self->_intrinsic($child);
            $nat{ $child->id } = [ $nw, $nh ];
            if   ( $flx > 0 ) { $total_flex += $flx; }
            else              { $used_fixed += $is_col ? ( $child->h || $nh ) : ( $child->w || $nw ); }
        }
        my $remain = $main_avail - $used_fixed;
        $remain = 0 if $remain < 0;
        my $cx = $inner_x;
        my $cy = $inner_y;
        for my $child (@$children) {
            my $flx = $child->can('flex') ? $child->flex : 0;
            my ( $nw, $nh ) = @{ $nat{ $child->id } };
            my ( $cw, $ch );
            if ($is_col) {
                $cw = $inner_w;
                $ch = $flx > 0 ? int( ( $flx / $total_flex ) * $remain ) : ( $child->h || $nh );
                $self->compute( $child, $cx, $cy, $cw, $ch );
                $cy += $ch + $spc;
            }
            else {
                $ch = $inner_h;
                $cw = $flx > 0 ? int( ( $flx / $total_flex ) * $remain ) : ( $child->w || $nw );
                $self->compute( $child, $cx, $cy, $cw, $ch );
                $cx += $cw + $spc;
            }
        }
    }
};
1;
