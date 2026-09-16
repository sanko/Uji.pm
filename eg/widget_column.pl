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
            title    => 'Uji Column Demo',
            w        => 360,
            h        => 320,
            centered => 1,

            # Children stack vertically. A flex child expands to fill leftover height
            # (here the +/- buttons share it) rather than hugging its content.
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Vertical stack with flex:'),
                    Uji::button( label => 'Click me (' . $model->{clicks} . ')', flex => 1, on_click => { type => 'CLICK' } ),
                    Uji::button( label => 'Fixed', on_click => { type => 'CLICK' } ),
                    Uji::row(
                        spacing  => 10,
                        children =>
                            [ Uji::text('A row inside the column:'), Uji::button( label => '+1', flex => 1, on_click => { type => 'CLICK' } ) ]
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
