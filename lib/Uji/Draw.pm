use v5.40;
use experimental 'class';
class Uji::Draw v0.0.1 {
    field $w : param;    # surface width
    field $h : param;    # surface height
    field $color = '#000000';
    field $width = 1;
    field $aa    = 1;
    method size () { return ( $w, $h ) }
    method color ( $c = undef ) { $color = $c if defined $c; return $color }
    method width ( $n = undef ) { $width = $n if defined $n; return $width }

    method antialias ( $yes = undef ) {
        if ( defined $yes ) {
            $aa = $yes ? 1 : 0;
            $self->_apply_smoothing;
        }
        return $aa;
    }

    method _argb ( $hex, $alpha = 255 ) {
        my $h = $hex;
        $h =~ s/^#//;
        return ( $alpha << 24 ) | hex($h);
    }
    method clear        ( $hex = undef )                     { $self->_clear( $hex // $color ) }
    method line         ( $x1, $y1, $x2, $y2 )               { $self->_line( $x1, $y1, $x2, $y2 ) }
    method rect         ( $x, $y, $rw, $rh )                 { $self->_rect( $x, $y, $rw, $rh ) }
    method fill_rect    ( $x, $y, $rw, $rh )                 { $self->_fill_rect( $x, $y, $rw, $rh ) }
    method ellipse      ( $x, $y, $rw, $rh )                 { $self->_ellipse( $x, $y, $rw, $rh ) }
    method fill_ellipse ( $x, $y, $rw, $rh )                 { $self->_fill_ellipse( $x, $y, $rw, $rh ) }
    method arc          ( $x, $y, $rw, $rh, $start, $sweep ) { $self->_arc( $x, $y, $rw, $rh, $start, $sweep ) }
    method fill_pie     ( $x, $y, $rw, $rh, $start, $sweep ) { $self->_fill_pie( $x, $y, $rw, $rh, $start, $sweep ) }
    method _apply_smoothing () { }
    method _clear        ($hex)                               { die ref($self) . ' must implement _clear' }
    method _line         ( $x1, $y1, $x2, $y2 )               { die ref($self) . ' must implement _line' }
    method _rect         ( $x, $y, $rw, $rh )                 { die ref($self) . ' must implement _rect' }
    method _fill_rect    ( $x, $y, $rw, $rh )                 { die ref($self) . ' must implement _fill_rect' }
    method _ellipse      ( $x, $y, $rw, $rh )                 { die ref($self) . ' must implement _ellipse' }
    method _fill_ellipse ( $x, $y, $rw, $rh )                 { die ref($self) . ' must implement _fill_ellipse' }
    method _arc          ( $x, $y, $rw, $rh, $start, $sweep ) { die ref($self) . ' must implement _arc' }
    method _fill_pie     ( $x, $y, $rw, $rh, $start, $sweep ) { die ref($self) . ' must implement _fill_pie' }
};
1;
