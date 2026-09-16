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
            title    => 'Uji Row Demo',
            w        => 420,
            h        => 200,
            centered => 1,

            # Children stack horizontally; flex distributes leftover width proportionally.
            child => Uji::column(
                padding  => 15,
                spacing  => 14,
                children => [
                    Uji::text('Horizontal stack with proportional flex:'),
                    Uji::row(
                        spacing  => 10,
                        children => [
                            Uji::button( label => '1', flex => 1, on_click => { type => 'CLICK' } ),
                            Uji::button( label => '2', flex => 2, on_click => { type => 'CLICK' } ),
                            Uji::button( label => '1', flex => 1, on_click => { type => 'CLICK' } )
                        ]
                    ),
                    Uji::row(
                        spacing  => 10,
                        children => [
                            Uji::text('Fixed children hug their content:'),
                            Uji::button( label => 'A', on_click => { type => 'CLICK' } ),
                            Uji::button( label => 'B', on_click => { type => 'CLICK' } )
                        ]
                    ),
                    Uji::text( 'Clicks: ' . $model->{clicks} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
