use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { level => 50, snap => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_LEVEL' ) {
            $model->{level} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'TOGGLE_SNAP' ) {
            $model->{snap} = $model->{snap} ? 0 : 1;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Slider Demo',
            w        => 360,
            h        => 200,
            centered => 1,

            # The slider posts SET_LEVEL on every drag via on_change; locked snaps in steps of 25.
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text( 'Level: ' . $model->{level} . '%' ),
                    Uji::slider(
                        value     => $model->{level},
                        min       => 0,
                        max       => 100,
                        step      => ( $model->{snap} ? 25 : 1 ),
                        on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } }
                    ),
                    Uji::checkbox(
                        label     => 'Snap to 25',
                        checked   => $model->{snap},
                        on_toggle => sub ($on) { { type => 'TOGGLE_SNAP', value => $on } }
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
