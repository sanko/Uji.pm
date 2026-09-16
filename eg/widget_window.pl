use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { title => 'Uji Window Demo', topmost => 0, constrained => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_TITLE' ) {
            $model->{title} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'TOGGLE_TOPMOST' ) {
            $model->{topmost} = $model->{topmost} ? 0 : 1;
        }
        elsif ( $msg->{type} eq 'TOGGLE_CONSTRAINTS' ) {
            $model->{constrained} = $model->{constrained} ? 0 : 1;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title     => $model->{title},
            w         => 380,
            h         => 260,
            centered  => 1,
            resizable => 1,
            topmost   => $model->{topmost},

            # With constraints on, the window is clamped between the given min/max sizes.
            min_w => $model->{constrained} ? 300 : 0,
            min_h => $model->{constrained} ? 200 : 0,
            max_w => $model->{constrained} ? 500 : 0,
            max_h => $model->{constrained} ? 300 : 0,
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Edit the window title live:'),
                    Uji::text_input( value => $model->{title}, on_input => sub ($t) { { type => 'SET_TITLE', value => $t } } ),
                    Uji::text( 'Current title: ' . $model->{title} ),
                    Uji::button( label => 'Always on top: ' . ( $model->{topmost} ? 'ON' : 'OFF' ), on_click => { type => 'TOGGLE_TOPMOST' } ),
                    Uji::button(
                        label    => 'Constraints: ' . ( $model->{constrained} ? 'ON (300-500 x 200-300)' : 'OFF' ),
                        on_click => { type => 'TOGGLE_CONSTRAINTS' }
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
