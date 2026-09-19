use v5.40;
use experimental 'class';

# The drawing vocabulary handed to a canvas `on_draw` callback.
#
# Uji::Draw is the PLATFORM-NEUTRAL half of the drawing stack: it owns the state a
# callback can both set and read (colour, pen width, antialiasing) plus the size of
# the box being drawn, and it defines the primitive vocabulary the callback uses.
# The actual pixels come from a platform IMPLEMENTATION (Uji::Draw::Win32 is the
# GDI+ one; GTK4/Cocoa backends arrive with those drivers). A driver constructs the
# implementation for its platform and the callback talks to it through THIS class,
# so the code written inside `on_draw` stays portable verbatim.
class Uji::Draw v0.0.1 {

    field $w     :param;    # box width  (pixels of the canvas)
    field $h     :param;    # box height
    field $color = '#000000';
    field $width = 1;
    field $aa    = 1;

    # ---- accessors ----------------------------------------------------------
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

    # internal: the canonical '#RRGGBB' -> packed ARGB map (alpha at the top byte),
    # the shared starting point for every platform implementation.
    method _argb ( $hex, $alpha = 255 ) {
        my $h = $hex;
        $h =~ s/^#//;
        return ( $alpha << 24 ) | hex($h);
    }

    # ---- public drawing vocabulary ------------------------------------------
    # State-validating entry points that dispatch to the per-platform primitives
    # (_clear, _line, _rect, ... the PLATFORM CONTRACT below).
    method clear        ($hex = undef)         { $self->_clear( $hex // $color ) }
    method line         ( $x1, $y1, $x2, $y2 ) { $self->_line( $x1, $y1, $x2, $y2 ) }
    method rect         ( $x, $y, $rw, $rh )   { $self->_rect( $x, $y, $rw, $rh ) }
    method fill_rect    ( $x, $y, $rw, $rh )   { $self->_fill_rect( $x, $y, $rw, $rh ) }
    method ellipse      ( $x, $y, $rw, $rh )   { $self->_ellipse( $x, $y, $rw, $rh ) }
    method fill_ellipse ( $x, $y, $rw, $rh )   { $self->_fill_ellipse( $x, $y, $rw, $rh ) }
    method arc          ( $x, $y, $rw, $rh, $start, $sweep ) { $self->_arc( $x, $y, $rw, $rh, $start, $sweep ) }
    method fill_pie     ( $x, $y, $rw, $rh, $start, $sweep ) { $self->_fill_pie( $x, $y, $rw, $rh, $start, $sweep ) }

    # ---- platform contract (abstract) ----------------------------------------
    # A subclass supplies these. The base die()s so a platform that forgets one
    # fails loudly at draw time instead of silently drawing nothing.
    method _apply_smoothing () {}
    method _clear ( $hex )                 { die ref($self) . ' must implement _clear' }
    method _line ( $x1, $y1, $x2, $y2 )    { die ref($self) . ' must implement _line' }
    method _rect ( $x, $y, $rw, $rh )      { die ref($self) . ' must implement _rect' }
    method _fill_rect ( $x, $y, $rw, $rh ) { die ref($self) . ' must implement _fill_rect' }
    method _ellipse ( $x, $y, $rw, $rh )   { die ref($self) . ' must implement _ellipse' }
    method _fill_ellipse ( $x, $y, $rw, $rh ) { die ref($self) . ' must implement _fill_ellipse' }
    method _arc ( $x, $y, $rw, $rh, $start, $sweep )     { die ref($self) . ' must implement _arc' }
    method _fill_pie ( $x, $y, $rw, $rh, $start, $sweep ) { die ref($self) . ' must implement _fill_pie' }
};
1;