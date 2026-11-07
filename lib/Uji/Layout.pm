use v5.40;
use experimental 'class';
class Uji::Layout v0.0.1 {
    field $driver : param : reader;

    sub _is_container ($type) {
        return $type eq 'column'   ||
            $type eq 'row'         ||
            $type eq 'group_box'   ||
            $type eq 'scroll_view' ||
            $type eq 'split_view'  ||
            $type eq 'tab_panel'   ||
            $type eq 'tree_view'   ||
            $type eq 'list_view'   ||
            $type eq 'calendar'    ||
            $type eq 'overlay';
    }

    sub _clamp ( $v, $min, $max ) {
        $v = $min if $min && $v < $min;
        $v = $max if $max && $v > $max;
        return $v;
    }

    sub _align_frac ($policy) {
        return 0.5 if defined $policy && $policy eq 'center';
        return 1.0 if defined $policy && $policy eq 'end';
        return 0;
    }

    method _cross_size ( $node, $axis, $cell ) {
        if ( $axis eq 'w' ) {
            return _clamp( $node->w, $node->min_w, $node->max_w ) if $node->w;
            my ( $nw, undef ) = $self->_natural($node);
            my $fw = $node->fit_policy('w');
            return defined $fw && $fw eq 'content' ? $nw : $cell;
        }
        return _clamp( $node->h, $node->min_h, $node->max_h ) if $node->h;
        my ( undef, $nh ) = $self->_natural($node);
        my $fh = $node->fit_policy('h');
        my $fill_h
            = defined $fh &&
            $fh eq 'fill' ? 1 : defined $fh &&
            $fh eq 'content' ? 0 : ( _is_container( $node->type ) || $node->type eq 'spacer' || $node->type eq 'separator' ) ? 1 : 0;
        return $fill_h ? $cell : $nh;
    }

    method _natural ($node) {
        my ( $w, $h ) = $self->_intrinsic($node);
        $w = $node->w if $node->w;
        $h = $node->h if $node->h;
        $w = _clamp( $w, $node->min_w, $node->max_w );
        $h = _clamp( $h, $node->min_h, $node->max_h );
        return ( $w, $h );
    }

    method _intrinsic ($node) {
        my $t = $node->type;
        return ( 0, 0 ) if $t eq 'spacer';
        if ( $t eq 'separator' ) {
            my $vert = ( $node->orientation // 'horizontal' ) eq 'vertical';
            return $vert ? ( 3, 0 ) : ( 0, 3 );
        }
        return ( ( $node->size // 24 ) x 2 ) if $t eq 'spinner';
        if ( $t eq 'canvas' ) {
            return ( $node->w || 200, $node->h || 100 );
        }
        if ( $t eq 'image' ) {
            my ( $nw, $nh ) = $driver && $driver->can('measure_image') ? $driver->measure_image( $node->src // '' ) : ( 64, 64 );
            ( $nw, $nh ) = ( 64, 64 ) unless $nw && $nh;
            if ( $node->w && !$node->h ) {
                $nh = int( $nh * $node->w / $nw );
            }
            elsif ( $node->h && !$node->w ) {
                $nw = int( $nw * $node->h / $nh );
            }
            return ( $nw, $nh );
        }
        if ( $t eq 'color_button' ) {
            my $hex = '' . ( $node->color // '#000000' );
            my ( $tw, $th ) = ( 0, 16 );
            if ( $node->show_hex ) {
                ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($hex) : ( CORE::length($hex) * 8, 16 );
            }
            return ( 3 + 3 + 16 + ( $node->show_hex ? 3 + 6 + $tw : 0 ) + 3, 22 );
        }
        if ( $t eq 'text' || $t eq 'button' ) {
            my $label = '' . ( $node->label // '' );
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 24, $th += 10 if $t eq 'button';
            return ( $tw, $th );
        }
        if ( $t eq 'status_text' ) {
            my $label = '' . ( $node->label // '' );
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            return ( $tw, $th );
        }
        if ( $t eq 'status_bar' ) {
            my @texts = @{ $node->panels };
            @texts = ( $node->label ) unless @texts;
            my $w = 0;
            for my $item (@texts) {
                my $l = '' . ( $item // '' );
                my ($tw) = $driver && $driver->can('measure_text') ? $driver->measure_text($l) : ( length($l) * 8, 16 );
                $w = $tw if $tw > $w;
            }
            return ( ( $w + 24 ) < 100 ? 100 : $w + 24, 22 );
        }
        if ( $t eq 'scroll_view' ) {
            my $child = @{ $node->children } ? $node->children->[0] : undef;
            return ( 100, 30 ) unless $child;
            return $self->_natural($child);
        }
        if ( $t eq 'checkbox' || $t eq 'radio' ) {
            my $label = '' . ( $node->label // '' );
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 24, $th += 4;
            return ( $tw, $th );
        }
        if ( $t eq 'text_input' || $t eq 'password' ) {
            my $val = '' . ( $node->value // '' );
            my $tw  = length $val ? ( $driver && $driver->can('measure_text') ? ( $driver->measure_text($val) )[0] : length($val) * 8 ) : 80;
            $tw += 16;
            if ( $t eq 'text_input' && $node->multiline ) {
                my $lines = () = ( $val =~ /\n/g );
                $lines++;
                $lines = 3 if $lines < 3;
                return ( $tw < 80 ? 80 : $tw, $lines * 20 );
            }
            return ( $tw < 80 ? 80 : $tw, 20 );
        }
        if ( $t eq 'search_input' ) {
            my $val = '' . ( $node->value // '' );
            my $tw  = length $val ? ( $driver && $driver->can('measure_text') ? ( $driver->measure_text($val) )[0] : length($val) * 8 ) : 80;
            $tw += 16;
            $tw += 28 if $node->icon;
            $tw += 22;
            return ( $tw < 100 ? 100 : $tw, 24 );
        }
        if ( $t eq 'multiline_text' ) {
            my $val = '' . ( $node->value // '' );
            my ( $w, $lines ) = ( 80, ( $val =~ tr/\n// ) + 1 );
            for my $line ( split /\n/, $val ) {
                my ($tw) = $driver && $driver->can('measure_text') ? $driver->measure_text($line) : ( length($line) * 8, 16 );
                $w = $tw if $tw > $w;
            }
            $lines = 3 if $lines < 3;
            return ( ( $w + 16 ) < 80 ? 80 : $w + 16, $lines * 20 );
        }
        if ( $t eq 'slider' ) {
            return $node->orientation eq 'vertical' ? ( 26, 120 ) : ( 120, 26 );
        }
        if ( $t eq 'spin_box' ) {
            my $val = '' . ( $node->value // '' );
            my $tw  = length $val ? ( $driver && $driver->can('measure_text') ? ( $driver->measure_text($val) )[0] : length($val) * 8 ) : 80;
            $tw += 40;
            return ( $tw < 80 ? 80 : $tw, 20 );
        }
        if ( $t eq 'progress_bar' ) {
            return ( 100, 18 );
        }
        if ( $t eq 'toggle_switch' || $t eq 'toggle_button' ) {
            my $label = '' . ( $node->label // '' );
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 34, $th += 10;
            return ( $tw, $th );
        }
        if ( $t eq 'link_button' ) {
            my $label = '' . ( $node->label // '' );
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 20, $th += 8;
            return ( $tw, $th );
        }
        if ( $t eq 'combo_box' || $t eq 'list_box' ) {
            my $opts = $node->options;
            my $w    = 0;
            for my $o (@$opts) {
                my $l = '' . ( $o->{label} // $o->{value} // '' );
                my ($tw) = $driver && $driver->can('measure_text') ? $driver->measure_text($l) : ( length($l) * 8, 16 );
                $w = $tw if $tw > $w;
            }
            my $n = @$opts <= 6 ? @$opts : 6;
            if ( $t eq 'combo_box' ) {
                return ( ( $w + 40 ) < 100 ? 100 : $w + 40, 20 + ( $n * 18 ) );
            }
            return ( ( $w + 16 ) < 100 ? 100 : $w + 16, ( $n * 18 ) + 4 );
        }
        if ( $t eq 'column' || $t eq 'radio_group' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my ( $max_w, $h ) = ( 0, $pad * 2 );
            for my $i ( 0 .. $#$children ) {
                my ( $cw, $ch ) = $self->_natural( $children->[$i] );
                $max_w = $cw if $cw > $max_w;
                $h += $ch;
                $h += $spc if $i < $#$children;
            }
            return ( $max_w + ( $pad * 2 ), $h );
        }
        if ( $t eq 'row' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my ( $w, $max_h ) = ( $pad * 2, 0 );
            for my $i ( 0 .. $#$children ) {
                my ( $cw, $ch ) = $self->_natural( $children->[$i] );
                $max_h = $ch if $ch > $max_h;
                $w += $cw;
                $w += $spc if $i < $#$children;
            }
            return ( $w, $max_h + ( $pad * 2 ) );
        }
        if ( $t eq 'group_box' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my ( $max_w, $h ) = ( 0, $pad * 2 + 16 );
            for my $i ( 0 .. $#$children ) {
                my ( $cw, $ch ) = $self->_natural( $children->[$i] );
                $max_w = $cw if $cw > $max_w;
                $h += $ch;
                $h += $spc if $i < $#$children;
            }
            return ( $max_w + ( $pad * 2 ), $h );
        }
        if ( $t eq 'split_view' ) {
            my $kids = $node->children;
            my $dw   = $node->divider_w // 6;
            my $vert = $node->orientation eq 'vertical';
            my ( $w, $h ) = ( $dw, $dw );
            for my $i ( 0 .. $#$kids ) {
                my ( $cw, $ch ) = $self->_natural( $kids->[$i] );
                if   ($vert) { $h += $ch; $w = $cw if $cw > $w; }
                else         { $w += $cw; $h = $ch if $ch > $h; }
            }
            return ( $w, $h );
        }
        if ( $t eq 'tab_panel' ) {
            my ( $w, $h ) = ( 200, 200 );
            for my $kid ( grep {defined} @{ $node->children } ) {
                my ( $cw, $ch ) = $self->_natural($kid);
                $w = $cw if $cw > $w;
                $h = $ch if $ch > $h;
            }
            return ( $w, $h + 25 );
        }
        if ( $t eq 'toolbar' ) {
            my $w  = 0;
            my $is = $node->icon_size // 16;
            for my $b ( @{ $node->buttons // [] } ) {
                if ( $b->{separator} ) {
                    $w += $b->{width} // 6;
                    next;
                }
                my $label = '' . ( $b->{label} // '' );
                my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
                $w += $tw + 16 + ( $b->{icon} ? $is + 4 : 0 );
            }
            return ( ( $w + 8 ) < 80 ? 80 : $w + 8, 28 );
        }
        if ( $t eq 'list_view' ) {
            my $w = 0;
            for my $c ( @{ $node->columns // [] } ) {
                my $cw = $c->{width} // 0;
                if ( !$cw ) {
                    my $label = '' . ( $c->{label} // '' );
                    my ($tw)  = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
                    $cw = ( $tw + 24 ) < 60 ? 60 : $tw + 24;
                }
                $w += $cw;
            }
            my $n = @{ $node->rows // [] };
            $n = 1 if $n < 1;
            $n = 8 if $n > 8;
            return ( $w ? $w : 100, ( $n * 22 ) + 20 );
        }
        if ( $t eq 'calendar' ) {
            return ( 232, 200 );
        }
        if ( $t eq 'overlay' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my ( $max_w, $max_h ) = ( 0, 0 );
            for my $child (@$children) {
                my ( $cw, $ch ) = $self->_natural($child);
                $max_w = $cw if $cw > $max_w;
                $max_h = $ch if $ch > $max_h;
            }
            return ( $max_w + ( $pad * 2 ), $max_h + ( $pad * 2 ) );
        }
        return ( 100, 30 );
    }

    method compute ( $node, $start_x = 0, $start_y = 0, $avail_w = 800, $avail_h = 600, $main = 'h' ) {
        my ( $w, $h );
        if ( $node->type eq 'window' ) {
            $w = $node->bw || $avail_w;
            $h = $node->bh || $avail_h;
        }
        else {
            my $is_container = _is_container( $node->type );
            my ( $nw, $nh ) = $self->_natural($node);
            my $fw = $node->fit_policy('w');
            $w = $node->w ? $node->w : defined $fw && $fw eq 'content' ? $nw : $avail_w;
            $w = _clamp( $w, $node->min_w, $node->max_w );
            my $fh   = $node->fit_policy('h');
            my $flex = $node->flex // 0;
            my $fill_h
                = ( $main eq 'h' && $flex > 0 ) ? 1 : defined $fh &&
                $fh eq 'fill'                   ? 1 : defined $fh &&
                $fh eq 'content'                ? 0 : ( $is_container || $node->type eq 'spacer' || $node->type eq 'separator' ) ? 1 : 0;
            $h = $node->h ? $node->h : $fill_h ? $avail_h : $nh;
            $h = _clamp( $h, $node->min_h, $node->max_h );
        }
        $node->set_bounds( $start_x, $start_y, $w, $h );
        if ( $node->type eq 'window' ) {
            $self->compute( $node->child, 0, 0, $w, $h, 'h' ) if $node->child;
        }
        elsif ( $node->type eq 'column' || $node->type eq 'radio_group' ) {
            $self->_layout_flex( $node, 'vertical', $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'row' ) {
            $self->_layout_flex( $node, 'horizontal', $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'group_box' ) {
            $self->_layout_group_box( $node, $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'scroll_view' ) {
            my $child = @{ $node->children } ? $node->children->[0] : undef;
            if ($child) {
                my ( $iw, $ih ) = $self->_natural($child);
                $iw = $child->w if $child->w;
                $ih = $child->h if $child->h;
                if ( $node->orientation eq 'vertical' ) {
                    $iw = $w if $w > $iw;
                }
                elsif ( $node->orientation eq 'horizontal' ) {
                    $ih = $h if $h > $ih;
                }
                $self->compute( $child, $start_x, $start_y, $iw, $ih, 'h' );
            }
        }
        elsif ( $node->type eq 'split_view' ) {
            $self->_layout_split( $node, $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'tab_panel' ) {
            $self->_layout_tab( $node, $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'calendar' ) {
            $self->_layout_flex( $node, 'vertical', $start_x, $start_y, $w, $h );
        }
        elsif ( $node->type eq 'overlay' ) {
            $self->_layout_overlay( $node, $start_x, $start_y, $w, $h );
        }
    }

    method _layout_overlay ( $node, $x, $y, $w, $h ) {
        my $children = $node->children;
        return unless @$children;
        my $pad = $node->can('padding') ? $node->padding : 0;
        my $ix  = $x + $pad;
        my $iy  = $y + $pad;
        my $iw  = $w - ( $pad * 2 );
        my $ih  = $h - ( $pad * 2 );
        for my $child (@$children) {
            my $cw = $self->_cross_size( $child, 'w', $iw );
            my $ch = $self->_cross_size( $child, 'h', $ih );
            my $ox = int( _align_frac( $child->align_policy('w') ) * ( $iw - $cw ) );
            my $oy = int( _align_frac( $child->align_policy('h') ) * ( $ih - $ch ) );
            $ox = 0 if $ox < 0;
            $oy = 0 if $oy < 0;
            $self->compute( $child, $ix + $ox, $iy + $oy, $iw, $ih, 'h' );
        }
    }

    method _layout_group_box ( $node, $x, $y, $w, $h ) {
        my $children = $node->children;
        return unless @$children;
        my $pad        = $node->can('padding') ? $node->padding : 0;
        my $spc        = $node->can('spacing') ? $node->spacing : 0;
        my $ix         = $x + $pad;
        my $iy         = $y + 16;
        my $iw         = $w - ( $pad * 2 );
        my $ih         = $h - 16 - $pad;
        my $main_avail = $ih - ( ( @$children - 1 ) * $spc );
        my $total_flex = 0;
        my $used_fixed = 0;
        my $fill_count = 0;
        my ( %fill, %nat, %explicit );

        for my $child (@$children) {
            my ( $nw, $nh ) = $self->_natural($child);
            $nat{ $child->id } = [ $nw, $nh ];
            my $expl = $child->h;
            $explicit{ $child->id } = $expl;
            my $flex   = $child->flex // 0;
            my $policy = $child->fit_policy('h');
            my $fillc
                = defined $policy &&
                $policy eq 'fill' ? 1 :
                ( ( $child->type eq 'split_view' || $child->type eq 'tab_panel' || $child->type eq 'tree_view' || $child->type eq 'list_view' ) &&
                    !$expl ) ? 1 :
                0;
            $fill{ $child->id } = $fillc;
            if    ( $flex > 0 ) { $total_flex += $flex; }
            elsif ($expl)       { $used_fixed += $expl; }
            elsif ($fillc)      { $fill_count++; }
            else                { $used_fixed += $nh; }
        }
        my $remain = $main_avail - $used_fixed;
        $remain = 0 if $remain < 0;
        my $cy = $iy;
        for my $child (@$children) {
            my $flex  = $child->flex // 0;
            my $fillc = $fill{ $child->id };
            my $expl  = $explicit{ $child->id };
            my ( $nw, $nh ) = @{ $nat{ $child->id } };
            my $ch
                = $flex > 0 ? int( ( $flex / $total_flex ) * $remain ) :
                $expl       ? $expl :
                $fillc      ? int( ( $main_avail - $used_fixed ) / $fill_count ) :
                $nh;
            my $cross = $self->_cross_size( $child, 'w', $iw );
            my $off   = int( _align_frac( $child->align_policy('w') ) * ( $iw - $cross ) );
            $off = 0 if $off < 0;
            $self->compute( $child, $ix + $off, $cy, $iw, $ch, 'h' );
            $cy += $child->bh + $spc;
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
        my $main       = $is_col ? 'h' : 'w';
        my $main_avail = ( $is_col ? $inner_h : $inner_w ) - ( ( @$children - 1 ) * $spc );
        my $total_flex = 0;
        my $used_fixed = 0;
        my $fill_count = 0;
        my ( %fill, %nat, %explicit );

        for my $child (@$children) {
            my ( $nw, $nh ) = $self->_natural($child);
            $nat{ $child->id } = [ $nw, $nh ];
            my $expl = $is_col ? $child->h : $child->w;
            $explicit{ $child->id } = $expl;
            my $flex   = $child->flex // 0;
            my $policy = $child->fit_policy($main);
            my $fillc  = defined $policy && $policy eq 'fill' ? 1 : (
                (
                    $child->type eq 'scroll_view'    ||
                        $child->type eq 'split_view' ||
                        $child->type eq 'tab_panel'  ||
                        $child->type eq 'tree_view'  ||
                        $child->type eq 'list_view'
                ) &&
                    !$expl
            ) ? 1 : 0;
            $fill{ $child->id } = $fillc;
            if    ( $flex > 0 ) { $total_flex += $flex; }
            elsif ($expl)       { $used_fixed += $expl; }
            elsif ($fillc)      { $fill_count++; }
            else                { $used_fixed += $is_col ? $nh : $nw; }
        }
        my $fill_budget = $main_avail - $used_fixed;
        my $remain      = $main_avail - $used_fixed;
        $remain      = 0 if $remain < 0;
        $fill_budget = 0 if $fill_budget < 0;
        my $cx = $inner_x;
        my $cy = $inner_y;
        for my $child (@$children) {
            my $flex  = $child->flex // 0;
            my $fillc = $fill{ $child->id };
            my $expl  = $explicit{ $child->id };
            my ( $nw, $nh ) = @{ $nat{ $child->id } };
            my $main_size
                = $flex > 0 ? int( ( $flex / $total_flex ) * $remain ) :
                $expl       ? $expl :
                $fillc      ? int( $fill_budget / $fill_count ) :
                ( $is_col ? $nh : $nw );
            if ($is_col) {
                my $cross = $self->_cross_size( $child, 'w', $inner_w );
                my $off   = int( _align_frac( $child->align_policy('w') ) * ( $inner_w - $cross ) );
                $off = 0 if $off < 0;
                $self->compute( $child, $cx + $off, $cy, $inner_w, $main_size, 'h' );
                $cy += $child->bh + $spc;
            }
            else {
                my $cell = $child->type eq 'spacer' ?
                    do {
                    my $mx = 0;
                    for my $c (@$children) {
                        next if $c->type eq 'spacer';
                        my $ch = $self->_cross_size( $c, 'h', $inner_h );
                        $mx = $ch if $ch > $mx;
                    }
                    $mx || $inner_h;
                    } :
                    $inner_h;
                my $cross = $self->_cross_size( $child, 'h', $cell );
                my $off   = int( _align_frac( $child->align_policy('h') ) * ( $inner_h - $cross ) );
                $off = 0 if $off < 0;
                $self->compute( $child, $cx, $cy + $off, $main_size, $cross, 'w' );
                $cx += $child->bw + $spc;
            }
        }
    }

    method _layout_split ( $node, $x, $y, $w, $h ) {
        my $kids = $node->children;
        return unless @$kids;
        my ( $div, $vert, $dw );
        if ( $driver && $driver->can('split_position') ) {
            ( $div, $vert, $dw ) = $driver->split_position( $node, $w, $h );
        }
        else {
            $vert = $node->orientation eq 'vertical';
            $dw   = $node->divider_w // 6;
            $div  = defined $node->divider ? $node->divider : int( ( ( $vert ? $h : $w ) - $dw ) / 2 );
            my $min_a = $node->min_a // 40;
            my $min_b = $node->min_b // 40;
            $div = $min_a if $div < $min_a;
            my $max = ( $vert ? $h : $w ) - $dw - $min_b;
            $div = $max   if $div > $max;
            $div = $min_a if $div > $max;
        }
        if ($vert) {
            $self->compute( $kids->[0], $x, $y,              $w, $div,            'h' );
            $self->compute( $kids->[1], $x, $y + $div + $dw, $w, $h - $div - $dw, 'h' ) if $kids->[1];
        }
        else {
            $self->compute( $kids->[0], $x,              $y, $div,            $h, 'w' );
            $self->compute( $kids->[1], $x + $div + $dw, $y, $w - $div - $dw, $h, 'w' ) if $kids->[1];
        }
    }

    method _layout_tab ( $node, $x, $y, $w, $h ) {
        my @kids = grep {defined} @{ $node->children };
        return unless @kids;
        my $strip  = 25;
        my $body_x = $x + 2;
        my $body_y = $y + $strip;
        my $body_w = $w - 4;
        my $body_h = $h - $strip - 2;
        $self->compute( $_, $body_x, $body_y, $body_w, $body_h ) for @kids;
    }
};
1;
