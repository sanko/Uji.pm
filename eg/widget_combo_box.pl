use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { color => 'green', custom => '' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_COLOR' ) {
            $model->{color} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_CUSTOM' ) {
            $model->{custom} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji ComboBox Demo',
            w        => 360,
            h        => 240,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Pick a color'),

                    # Dropdown list (not editable): on_select gets the option value.
                    Uji::combo_box(
                        value   => $model->{color},
                        options =>
                            [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' } ],
                        on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
                    ),
                    Uji::text( 'Chosen: ' . $model->{color} ),
                    Uji::text('Or type anything:'),

                    # Editable dropdown: on_select fires on picks, on_input on typed text.
                    Uji::combo_box(
                        value     => $model->{custom},
                        editable  => 1,
                        options   => [ map { { value => $_, label => $_ } } qw(alpha beta gamma delta) ],
                        on_select => sub ($v) { { type => 'SET_CUSTOM', value => $v } },
                        on_input  => sub ($t) { { type => 'SET_CUSTOM', value => $t } }
                    ),
                    Uji::text( 'Custom: ' . ( $model->{custom} || '(empty)' ) )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
