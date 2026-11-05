use v5.40;
use experimental 'class';
class Uji::Layout v0.0.1 {
    field $driver : param : reader;

    # Natural (content) size of a node measured through the driver
    method _intrinsic ($node) {
        my $t = $node->type;

        # Flexible whitespace has 0 intrinsic size (or explicit fixed w/h)
        if ( $t eq 'spacer' ) {
            my $w = $node->w || $node->min_w || ( $node->flex > 0 ? 20 : 0 );
            my $h = $node->h || $node->min_h || 0;
            return ( $w, $h );
        }

        # ScrollView viewport: uses explicit w/h if given, or standard viewport fallback
        if ( $t eq 'scroll_view' ) {
            my $w = $node->w || 320;
            my $h = $node->h || 240;
            return ( $w, $h );
        }

        # GroupBox container: frame + child content + title
        if ( $t eq 'group_box' ) {
            my $pad     = $node->padding;
            my $top_pad = $pad + 12;            # extra headroom for the etched title text
            my $label   = $node->label // '';
            my ( $lw, $lh ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            my ( $cw, $ch ) = ( 0, 0 );
            if ( $node->child ) {
                ( $cw, $ch ) = $self->_intrinsic( $node->child );
                $cw = $node->child->w if $node->child->w;
                $ch = $node->child->h if $node->child->h;
            }
            my $min_title_w = $lw + 32;
            my $w           = ( $cw > $min_title_w ? $cw : $min_title_w ) + ( $pad * 2 );
            my $h           = $ch + $top_pad + $pad;
            return ( $w, $h );
        }

        # Progress bar: standard bar width / height
        if ( $t eq 'progress_bar' ) {
            return ( 160, 20 );
        }

        # Static text label: measure text with headroom for ascenders/descenders
        if ( $t eq 'text' ) {
            my $label = $node->label // '';
            my @lines = split /\n/, $label, -1;
            @lines = ('') unless @lines;
            my $max_w   = 0;
            my $total_h = 0;
            for my $line (@lines) {
                my ( $lw, $lh )
                    = $driver && $driver->can('measure_text') ? $driver->measure_text( length($line) ? $line : ' ' ) : ( length($line) * 8, 16 );
                $max_w = $lw if $lw > $max_w;
                $total_h += ( $lh < 16 ? 16 : $lh ) + 4;
            }
            $max_w += 4;
            $total_h = 20 if $total_h < 20;
            return ( $max_w, $total_h );
        }

        # Push button: text metrics + button chrome margins with standard min width
        if ( $t eq 'button' ) {
            my $label = $node->label // '';
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 28;
            $tw = 60 if $tw < 60;
            $th = ( $th < 16 ? 16 : $th ) + 10;
            $th = 26 if $th < 26;
            return ( $tw, $th );
        }

        # Checkbox & Radio button: box/circle glyph + label text + padding
        if ( $t eq 'checkbox' || $t eq 'radio' ) {
            my $label = $node->label // '';
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 28;
            $th = ( $th < 16 ? 16 : $th ) + 6;
            $th = 22 if $th < 22;
            return ( $tw, $th );
        }

        # Toggle switch: push-toggle button
        if ( $t eq 'toggle_switch' ) {
            my $label = $node->label // '';
            my ( $tw, $th ) = $driver && $driver->can('measure_text') ? $driver->measure_text($label) : ( length($label) * 8, 16 );
            $tw += 36;
            $th = ( $th < 16 ? 16 : $th ) + 10;
            $th = 26 if $th < 26;
            return ( $tw, $th );
        }

        # Single-line text input & password: EDIT control with border
        if ( $t eq 'text_input' || $t eq 'password' ) {
            my $val = $node->value // '';
            my $tw  = length $val ? ( $driver && $driver->can('measure_text') ? ( $driver->measure_text($val) )[0] : length($val) * 8 ) : 80;
            $tw += 20;
            return ( $tw < 120 ? 120 : $tw, 24 );
        }

        # Multi-line text area
        if ( $t eq 'multiline_text' ) {
            my $text  = $node->value // '';
            my @lines = split /\n/, $text, -1;
            my $max_w = 0;
            for my $line (@lines) {
                my $lw = $driver && $driver->can('measure_text') ? ( $driver->measure_text($line) )[0] : length($line) * 8;
                $max_w = $lw if $lw > $max_w;
            }
            my $th = $driver && $driver->can('measure_text') ? ( $driver->measure_text('X') )[1] : 16;
            $th = 16 if $th < 16;
            my $rows = $node->rows || 4;
            return ( ( $max_w + 20 < 160 ? 160 : $max_w + 20 ), $rows * ( $th + 4 ) + 10 );
        }

        # ComboBox dropdown
        if ( $t eq 'combo_box' ) {
            my @labels = ( $node->value // '' );
            push @labels, map { $_->{label} // $_->{value} } @{ $node->options };
            my $max_w = 0;
            for my $label (@labels) {
                my $lw = $driver && $driver->can('measure_text') ? ( $driver->measure_text($label) )[0] : length($label) * 8;
                $max_w = $lw if $lw > $max_w;
            }
            my $th = $driver && $driver->can('measure_text') ? ( $driver->measure_text('X') )[1] : 16;
            $th = 16 if $th < 16;
            return ( ( $max_w + 48 < 130 ? 130 : $max_w + 48 ), $th + 10 );
        }

        # ListBox
        if ( $t eq 'list_box' ) {
            my $max_w = 0;
            for my $opt ( @{ $node->options } ) {
                my $label = $opt->{label} // $opt->{value} // '';
                my $lw    = $driver && $driver->can('measure_text') ? ( $driver->measure_text($label) )[0] : length($label) * 8;
                $max_w = $lw if $lw > $max_w;
            }
            my $th = $driver && $driver->can('measure_text') ? ( $driver->measure_text('X') )[1] : 16;
            $th = 16 if $th < 16;
            my $rows = $node->rows || 5;
            return ( ( $max_w + 28 < 130 ? 130 : $max_w + 28 ), $rows * ( $th + 4 ) + 10 );
        }

        # SpinBox (numeric edit + up/down arrows)
        if ( $t eq 'spin_box' ) {
            my $th = $driver && $driver->can('measure_text') ? ( $driver->measure_text('X') )[1] : 16;
            $th = 16 if $th < 16;
            return ( 100, $th + 10 );
        }

        # DatePicker
        if ( $t eq 'date_picker' ) {
            my $th = $driver && $driver->can('measure_text') ? ( $driver->measure_text('X') )[1] : 16;
            $th = 16 if $th < 16;
            return ( 140, $th + 10 );
        }

        # Slider (trackbar)
        if ( $t eq 'slider' ) {
            return ( 120, 28 );
        }

        # Vertical containers (Column, RadioGroup)
        if ( $t eq 'column' || $t eq 'radio_group' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my $max_w    = 0;
            my $total_h  = 0;
            for my $i ( 0 .. $#$children ) {
                my $child = $children->[$i];
                my ( $cw, $ch ) = $self->_intrinsic($child);
                $cw    = $child->w if $child->w;
                $ch    = $child->h if $child->h;
                $max_w = $cw       if $cw > $max_w;
                $total_h += $ch;
                $total_h += $spc if $i < $#$children;
            }
            my $w = $max_w + ( $pad * 2 );
            my $h = $total_h + ( $pad * 2 );
            return ( $w, $h );
        }

        # Horizontal container (Row)
        if ( $t eq 'row' ) {
            my $children = $node->children;
            my $pad      = $node->can('padding') ? $node->padding : 0;
            my $spc      = $node->can('spacing') ? $node->spacing : 0;
            my $total_w  = 0;
            my $max_h    = 0;
            for my $i ( 0 .. $#$children ) {
                my $child = $children->[$i];
                my ( $cw, $ch ) = $self->_intrinsic($child);
                $cw = $child->w if $child->w;
                $ch = $child->h if $child->h;
                $total_w += $cw;
                $total_w += $spc if $i < $#$children;
                $max_h = $ch if $ch > $max_h;
            }
            my $w = $total_w + ( $pad * 2 );
            my $h = $max_h + ( $pad * 2 );
            return ( $w, $h );
        }
        return ( 100, 30 );
    }

    method compute ( $node, $start_x = 0, $start_y = 0, $avail_w = 800, $avail_h = 600 ) {
        my ( $w, $h );
        if ( $node->type eq 'window' ) {
            if ( $node->bw && $node->bh ) {
                $w = $node->bw;
                $h = $node->bh;
            }
            elsif ( $node->child ) {
                my ( $cw, $ch ) = $self->_intrinsic( $node->child );
                $w = $node->w || ( $cw < 320 ? 320 : $cw );
                $h = $node->h || ( $ch < 180 ? 180 : $ch );
            }
            else {
                $w = $node->w || $avail_w;
                $h = $node->h || $avail_h;
            }
        }
        else {
            $w = $node->w || $avail_w;
            if ( $node->h ) {
                $h = $node->h;
            }
            elsif ( $node->flex > 0 && $avail_h > 0 ) {

                # Flex-driven height takes precedence over intrinsic fallback
                $h = $avail_h;
            }
            elsif ( $node->type ne 'column' && $node->type ne 'row' && $node->type ne 'scroll_view' ) {
                my ( $iw, $ih ) = $self->_intrinsic($node);
                $h = $ih;
                $w = $iw if !$node->w && $node->flex <= 0 && $avail_w == 0;
            }
            else {
                my ( $iw, $ih ) = $self->_intrinsic($node);
                $h = ( $avail_h > 0 ? $avail_h : $ih );
            }
        }

        # Apply min/max constraints to the computed viewport geometry
        ( $w, $h ) = $node->clamp_size( $w, $h );
        $node->set_bounds( $start_x, $start_y, $w, $h );
        if ( $node->type eq 'window' ) {
            $self->compute( $node->child, 0, 0, $w, $h ) if $node->child;
        }
        elsif ( $node->type eq 'scroll_view' ) {
            if ( $node->child ) {

                # In a ScrollView, the content canvas is measured in unconstrained space
                # Reserve 18px for the native vertical scrollbar
                my $canvas_avail_w = $w > 18 ? $w - 18 : $w;
                my ( $cw, $ch ) = $self->_intrinsic( $node->child );
                $cw = $node->child->w if $node->child->w;
                $cw = $canvas_avail_w if $cw < $canvas_avail_w;
                $ch = $node->child->h if $node->child->h;
                $ch = $h              if $ch < $h;
                $node->set_content_size( $cw, $ch );

                # Origin resets to (0, 0) for children inside the ScrollView
                $self->compute( $node->child, 0, 0, $cw, $ch );
            }
        }
        elsif ( $node->type eq 'group_box' ) {
            if ( $node->child ) {
                my $pad     = $node->padding;
                my $top_pad = $pad + 12;
                my $inner_x = $start_x + $pad;
                my $inner_y = $start_y + $top_pad;
                my $inner_w = $w - ( $pad * 2 );
                my $inner_h = $h - $top_pad - $pad;
                $inner_w = 0 if $inner_w < 0;
                $inner_h = 0 if $inner_h < 0;
                $self->compute( $node->child, $inner_x, $inner_y, $inner_w, $inner_h );
            }
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
        my $pad     = $container->can('padding') ? $container->padding : 0;
        my $spc     = $container->can('spacing') ? $container->spacing : 0;
        my $align   = $container->can('align')   ? $container->align   : ( $dir eq 'vertical' ? 'stretch' : 'center' );
        my $inner_x = $x + $pad;
        my $inner_y = $y + $pad;
        my $inner_w = $w - ( $pad * 2 );
        my $inner_h = $h - ( $pad * 2 );
        $inner_w = 0 if $inner_w < 0;
        $inner_h = 0 if $inner_h < 0;
        my $is_col     = ( $dir eq 'vertical' );
        my $main_avail = ( $is_col ? $inner_h : $inner_w ) - ( ( @$children - 1 ) * $spc );
        my $total_flex = 0;
        my $used_fixed = 0;
        my %nat;

        for my $child (@$children) {
            my $flx = $child->flex;
            my ( $nw, $nh ) = $self->_intrinsic($child);
            ( $nw, $nh ) = $child->clamp_size( $nw, $nh );
            $nat{ $child->id } = [ $nw, $nh ];
            if ( $flx > 0 ) {
                $total_flex += $flx;
            }
            else {
                $used_fixed += $is_col ? ( $child->h || $nh ) : ( $child->w || $nw );
            }
        }
        my $remain = $main_avail - $used_fixed;
        $remain = 0 if $remain < 0;
        my $cx = $inner_x;
        my $cy = $inner_y;
        for my $child (@$children) {
            my $flx = $child->flex;
            my ( $nw, $nh ) = @{ $nat{ $child->id } };
            my $child_align = $child->align_self // $align;
            if ($is_col) {
                my $target_h = $flx > 0 ? int( ( $flx / $total_flex ) * $remain ) : ( $child->h || $nh );
                $target_h = $child->min_h if $child->min_h && $target_h < $child->min_h;
                $target_h = $child->max_h if $child->max_h && $target_h > $child->max_h;
                my $target_w;
                if ( $child->w ) {
                    $target_w = $child->w;
                }
                elsif ( $child_align eq 'stretch' ) {
                    $target_w = $inner_w;
                }
                else {
                    $target_w = $nw;
                }
                $target_w = $child->min_w if $child->min_w        && $target_w < $child->min_w;
                $target_w = $child->max_w if $child->max_w        && $target_w > $child->max_w;
                $target_w = $inner_w      if $target_w > $inner_w && $inner_w > 0;
                my $child_x = $cx;
                if ( $child_align eq 'center' ) {
                    $child_x = $cx + int( ( $inner_w - $target_w ) / 2 );
                }
                elsif ( $child_align eq 'end' ) {
                    $child_x = $cx + ( $inner_w - $target_w );
                }
                $self->compute( $child, $child_x, $cy, $target_w, $target_h );
                $cy += $target_h + $spc;
            }
            else {
                my $target_w = $flx > 0 ? int( ( $flx / $total_flex ) * $remain ) : ( $child->w || $nw );
                $target_w = $child->min_w if $child->min_w && $target_w < $child->min_w;
                $target_w = $child->max_w if $child->max_w && $target_w > $child->max_w;
                my $target_h;
                if ( $child->h ) {
                    $target_h = $child->h;
                }
                elsif ( $child_align eq 'stretch' ) {
                    $target_h = $inner_h;
                }
                else {
                    $target_h = $nh;
                }
                $target_h = $child->min_h if $child->min_h        && $target_h < $child->min_h;
                $target_h = $child->max_h if $child->max_h        && $target_h > $child->max_h;
                $target_h = $inner_h      if $target_h > $inner_h && $inner_h > 0;
                my $child_y = $cy;
                if ( $child_align eq 'center' ) {
                    $child_y = $cy + int( ( $inner_h - $target_h ) / 2 );
                }
                elsif ( $child_align eq 'end' ) {
                    $child_y = $cy + ( $inner_h - $target_h );
                }
                $self->compute( $child, $cx, $child_y, $target_w, $target_h );
                $cx += $target_w + $spc;
            }
        }
    }
};
1;
