use v5.40;
use experimental 'class';
use Uji::Draw;

# The GDI+ implementation of Uji::Draw used by the Win32 driver. Each draw method
# creates and destroys its own pen/brush, so the object carries no heavyweight
# state beyond what Uji::Draw already holds. The raw GpGraphics* pointer is an
# unpacked integer (same pattern as the driver's _spinner_frames/_raster_hbitmap).
class Uji::Draw::Win32 v0.0.1 :isa(Uji::Draw) {
    use Affix qw[:memory :types :core];

    field $gc : param;    # raw GpGraphics* integer

    # GDI+ flat API
    affix 'gdiplus', 'GdipGraphicsClear',    [ Pointer [Void], Size_t ]                                           => Int;
    affix 'gdiplus', 'GdipCreatePen1',       [ Size_t, Float, Int, Pointer [Void] ]                               => Int;
    affix 'gdiplus', 'GdipDeletePen',        [ Pointer [Void] ]                                                   => Int;
    affix 'gdiplus', 'GdipCreateSolidFill',  [ Size_t, Pointer [Void] ]                                           => Int;
    affix 'gdiplus', 'GdipDeleteBrush',      [ Pointer [Void] ]                                                   => Int;
    affix 'gdiplus', 'GdipSetSmoothingMode', [ Pointer [Void], Int ]                                              => Int;
    affix 'gdiplus', 'GdipDrawLineI',        [ Pointer [Void], Pointer [Void], Int, Int, Int, Int ]               => Int;
    affix 'gdiplus', 'GdipDrawRectangleI',   [ Pointer [Void], Pointer [Void], Int, Int, Int, Int ]               => Int;
    affix 'gdiplus', 'GdipFillRectangleI',   [ Pointer [Void], Pointer [Void], Int, Int, Int, Int ]               => Int;
    affix 'gdiplus', 'GdipDrawEllipseI',     [ Pointer [Void], Pointer [Void], Int, Int, Int, Int ]               => Int;
    affix 'gdiplus', 'GdipFillEllipseI',     [ Pointer [Void], Pointer [Void], Int, Int, Int, Int ]               => Int;
    affix 'gdiplus', 'GdipDrawArcI',         [ Pointer [Void], Pointer [Void], Int, Int, Int, Int, Float, Float ] => Int;
    affix 'gdiplus', 'GdipFillPieI',         [ Pointer [Void], Pointer [Void], Int, Int, Int, Int, Float, Float ] => Int;

    # ---- platform contract ---------------------------------------------------

    method _apply_smoothing () {
        GdipSetSmoothingMode( $gc, $self->antialias ? 4 : 3 );    # AntiAlias / None
    }

    method _clear ( $hex ) {
        GdipGraphicsClear( $gc, $self->_argb($hex) );
    }

    method _line ( $x1, $y1, $x2, $y2 ) {
        my $pp = malloc(8);
        GdipCreatePen1( $self->_argb( $self->color ), $self->width, 2, Affix::address($pp) );
        my $pen = unpack( 'Q<', Affix::raw( $pp, 8 ) );
        GdipDrawLineI( $gc, $pen, int $x1, int $y1, int $x2, int $y2 );
        GdipDeletePen($pen);
        free($pp);
    }

    method _rect ( $x, $y, $rw, $rh ) {
        my $pp = malloc(8);
        GdipCreatePen1( $self->_argb( $self->color ), $self->width, 2, Affix::address($pp) );
        my $pen = unpack( 'Q<', Affix::raw( $pp, 8 ) );
        GdipDrawRectangleI( $gc, $pen, int $x, int $y, int $rw, int $rh );
        GdipDeletePen($pen);
        free($pp);
    }

    method _fill_rect ( $x, $y, $rw, $rh ) {
        my $bp = malloc(8);
        GdipCreateSolidFill( $self->_argb( $self->color ), Affix::address($bp) );
        my $brush = unpack( 'Q<', Affix::raw( $bp, 8 ) );
        GdipFillRectangleI( $gc, $brush, int $x, int $y, int $rw, int $rh );
        GdipDeleteBrush($brush);
        free($bp);
    }

    method _ellipse ( $x, $y, $rw, $rh ) {
        my $pp = malloc(8);
        GdipCreatePen1( $self->_argb( $self->color ), $self->width, 2, Affix::address($pp) );
        my $pen = unpack( 'Q<', Affix::raw( $pp, 8 ) );
        GdipDrawEllipseI( $gc, $pen, int $x, int $y, int $rw, int $rh );
        GdipDeletePen($pen);
        free($pp);
    }

    method _fill_ellipse ( $x, $y, $rw, $rh ) {
        my $bp = malloc(8);
        GdipCreateSolidFill( $self->_argb( $self->color ), Affix::address($bp) );
        my $brush = unpack( 'Q<', Affix::raw( $bp, 8 ) );
        GdipFillEllipseI( $gc, $brush, int $x, int $y, int $rw, int $rh );
        GdipDeleteBrush($brush);
        free($bp);
    }

    method _arc ( $x, $y, $rw, $rh, $start, $sweep ) {
        my $pp = malloc(8);
        GdipCreatePen1( $self->_argb( $self->color ), $self->width, 2, Affix::address($pp) );
        my $pen = unpack( 'Q<', Affix::raw( $pp, 8 ) );
        GdipDrawArcI( $gc, $pen, int $x, int $y, int $rw, int $rh, $start + 0.0, $sweep + 0.0 );
        GdipDeletePen($pen);
        free($pp);
    }

    method _fill_pie ( $x, $y, $rw, $rh, $start, $sweep ) {
        my $bp = malloc(8);
        GdipCreateSolidFill( $self->_argb( $self->color ), Affix::address($bp) );
        my $brush = unpack( 'Q<', Affix::raw( $bp, 8 ) );
        GdipFillPieI( $gc, $brush, int $x, int $y, int $rw, int $rh, $start + 0.0, $sweep + 0.0 );
        GdipDeleteBrush($brush);
        free($bp);
    }
};
1;