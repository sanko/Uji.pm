use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;
use Uji::Draw;

package main {

    sub init () {
        return ( { redraws => 0, status => 'Live GDI+ surface: drag nothing, just look.' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'REDRAW' ) {
            $model->{redraws}++;
            $model->{status} = "Forced a repaint: on_draw ran again ($model->{redraws} total).";
        }
        return ( $model, undef );
    }

    sub view ($model) {

        # The drawing callback: a small GDI+ scene sized to whatever box the layout gives it.
        my $on_draw = sub ($d) {
            my ( $w, $h ) = $d->size;

            # Checkerboard background.
            $d->clear('#FFFFFF');
            my $cell = 20;
            for ( my $y = 0; $y < $h; $y += $cell ) {
                for ( my $x = 0; $x < $w; $x += $cell ) {
                    next unless ( ( $x / $cell ) + ( $y / $cell ) ) % 2 == 0;
                    $d->color('#DDEEFF');
                    $d->fill_rect( $x, $y, $cell, $cell );
                }
            }

            # A red border rectangle around the whole surface.
            $d->color('#CC0000');
            $d->width(3);
            $d->rect( 2, 2, $w - 4, $h - 4 );

            # Overlapping translucent circles.
            $d->color('#3366FF');
            $d->fill_ellipse( 30, 30, 80, 80 );
            $d->color('#33CC66');
            $d->fill_ellipse( 90, 50, 70, 70 );

            # Arc and pie on the right side.
            $d->color('#FF8800');
            $d->width(4);
            $d->arc( $w - 120, 20, 100, 80, 0, 270 );
            $d->color('#8800FF');
            $d->fill_pie( $w - 120, $h - 90, 90, 70, 45, 180 );

            # A diagonal seam line.
            $d->color('#333333');
            $d->width(2);
            $d->line( 0, $h - 1, $w - 1, 0 );
        };
        Uji::window(
            title    => 'Uji Canvas Demo',
            w        => 520,
            h        => 380,
            centered => 1,
            child    => Uji::column(
                padding  => 16,
                spacing  => 12,
                children => [
                    Uji::canvas( w => 320, h => 220, background => '#F0F0F0', on_draw => $on_draw, redraw => $model->{redraws} ),
                    Uji::row(
                        align_h  => 'center',
                        spacing  => 12,
                        children => [ Uji::button( label => 'Repaint', fit => 'content', on_click => { type => 'REDRAW' } ) ]
                    ),
                    Uji::status_text( $model->{status} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
