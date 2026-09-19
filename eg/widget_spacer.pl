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
            title    => 'Uji Spacer Demo',
            w        => 430,
            h        => 330,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [

                    # A flex spacer absorbs the leftover row width, so the buttons hug the edges.
                    Uji::text('Flex spacer: pushes the row children apart:'),
                    Uji::row(
                        spacing  => 0,
                        children => [
                            Uji::button( label => 'Left',  on_click => { type => 'CLICK' } ),
                            Uji::spacer( flex => 1 ),
                            Uji::button( label => 'Right', on_click => { type => 'CLICK' } )
                        ]
                    ),

                    # Multiple spacers split the leftover proportionally by their flex weight
                    # (1 and 2), so the middle button sits a third of the way across.
                    Uji::text('Flex weights: the leftover is split 1 : 2:'),
                    Uji::row(
                        spacing  => 0,
                        children => [
                            Uji::button( label => 'Start',  on_click => { type => 'CLICK' } ),
                            Uji::spacer( flex => 1 ),
                            Uji::button( label => 'Middle', on_click => { type => 'CLICK' } ),
                            Uji::spacer( flex => 2 ),
                            Uji::button( label => 'End',    on_click => { type => 'CLICK' } )
                        ]
                    ),

                    # An explicit w/h makes the spacer a fixed-size gap (no flex).
                    Uji::text('Fixed spacer: an exact gap of w => 40:'),
                    Uji::row(
                        spacing  => 0,
                        children => [
                            Uji::text('Two words'),
                            Uji::spacer( w => 40 ),
                            Uji::text('sit 40px apart')
                        ]
                    ),

                    # In a column the spacer works the same way along the vertical main axis,
                    # pinning the footer to the bottom of the window.
                    Uji::text('Vertical spacer: pins the footer to the bottom:'),
                    Uji::spacer( flex => 1 ),
                    Uji::status_text( 'Buttons clicked: ' . $model->{clicks} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
