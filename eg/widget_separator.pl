use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { clicks => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'CLICK' ) {
            $model->{clicks}++;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Separator Demo',
            w        => 430,
            h        => 400,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [

                    # A horizontal separator draws a ruled line across the whole column width;
                    # the 3px thickness and full-width span come automatically from layout.
                    Uji::text('Horizontal rule across the column:'), Uji::separator(), Uji::text('Below the line'),

                    # A vertical separator divides a row's buttons from edge to edge.
                    Uji::text('Vertical rule between row buttons:'),
                    Uji::row(
                        spacing  => 0,
                        children => [
                            Uji::button( label => 'Left', on_click => { type => 'CLICK' } ),
                            Uji::separator( orientation => 'vertical' ),
                            Uji::button( label => 'Right', on_click => { type => 'CLICK' } )
                        ],
                    ),

                    # The separator participates in flex/term layout like any node: give it an
                    # explicit h (or flex) to grow it into a taller band.
                    Uji::text('A taller rule (h => 12):'),
                    Uji::separator( h => 12 ),
                    Uji::spacer( flex => 1 ),
                    Uji::status_text( 'Buttons clicked: ' . $model->{clicks} )
                ],
            ),
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
