use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { dark => 0, beep => 1 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'TOGGLE_DARK' ) {
            $model->{dark} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'TOGGLE_BEEP' ) {
            $model->{beep} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Checkbox Demo',
            w        => 360,
            h        => 200,
            centered => 1,

            # Checkboxes are stateful in the model; on_toggle receives the true post-click state.
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::checkbox(
                        label     => 'Dark mode',
                        checked   => $model->{dark},
                        on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } }
                    ),
                    Uji::checkbox(
                        label     => 'Beep on change',
                        checked   => $model->{beep},
                        on_toggle => sub ($on) { { type => 'TOGGLE_BEEP', value => $on } }
                    ),
                    Uji::text( 'Dark mode is ' . ( $model->{dark} ? 'ON' : 'OFF' ) . '; beep is ' . ( $model->{beep} ? 'ON' : 'OFF' ) . '.' ),
                    Uji::checkbox( label => 'Disabled checkbox', enabled => 0, checked => 1 )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
