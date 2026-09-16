use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { secret => '', reveal => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_SECRET' ) {
            $model->{secret} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'TOGGLE_REVEAL' ) {
            $model->{reveal} = $model->{reveal} ? 0 : 1;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Password Demo',
            w        => 360,
            h        => 210,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Enter a password:'),
                    Uji::password( value => $model->{secret}, on_input => sub ($text) { { type => 'SET_SECRET', value => $text } } ),
                    Uji::text( 'Length: ' . length( $model->{secret} ) . ' characters' ),
                    Uji::text( 'So far: ' . ( $model->{reveal} ? $model->{secret} : '#' x length( $model->{secret} ) ) ),

                    # The value is stored plain in the model and echoed with the visible prop.
                    Uji::checkbox(
                        label     => 'Reveal',
                        checked   => $model->{reveal},
                        on_toggle => sub ($on) { { type => 'TOGGLE_REVEAL', value => $on } }
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
