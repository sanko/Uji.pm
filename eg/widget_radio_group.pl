use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { color => 'blue' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_COLOR' ) {
            $model->{color} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji RadioGroup Demo',
            w        => 360,
            h        => 220,
            centered => 1,

            # The group is one scalar in the model; on_select receives the selected option value.
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Pick a highlight color'),
                    Uji::radio_group(
                        value   => $model->{color},
                        spacing => 4,
                        options => [
                            { value => 'red',   label => 'Red' },
                            { value => 'green', label => 'Green' },
                            { value => 'blue',  label => 'Blue' },
                            { value => 'none',  label => 'None' }
                        ],
                        on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
                    ),
                    Uji::text( 'Chosen: ' . ( $model->{color} // '(none)' ) )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
