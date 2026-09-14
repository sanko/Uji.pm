use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return (
            {   title       => 'Uji.pm Flexbox Demo',
                name        => 'World',
                count       => 0,
                level       => 50,
                secret      => '',
                locked      => 0,
                topmost     => 0,
                constrained => 0,
                show_extra  => 1,
                dark        => 0,
                color       => 'blue'
            },
            undef
        );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_TITLE' ) {
            $model->{title} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_NAME' ) {
            $model->{name} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'TOGGLE_LOCK' ) {
            $model->{locked} = $model->{locked} ? 0 : 1;
        }
        elsif ( $msg->{type} eq 'TOGGLE_TOPMOST' ) {
            $model->{topmost} = $model->{topmost} ? 0 : 1;
        }
        elsif ( $msg->{type} eq 'TOGGLE_CONSTRAINTS' ) {
            $model->{constrained} = $model->{constrained} ? 0 : 1;
        }
        elsif ( $msg->{type} eq 'TOGGLE_EXTRA' ) {
            $model->{show_extra} = $model->{show_extra} ? 0 : 1;
        }
        elsif ( $msg->{type} eq 'TOGGLE_DARK' ) {
            $model->{dark} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_COLOR' ) {
            $model->{color} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_SECRET' ) {
            $model->{secret} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'INCREMENT' ) {
            $model->{count} += 1;
        }
        elsif ( $msg->{type} eq 'SET_LEVEL' ) {
            $model->{level} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'RESET' ) {    # Clear everything
            ($model) = init();
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title     => $model->{title} // 'Application',
            w         => 380,
            h         => 600,
            topmost   => $model->{topmost},
            min_w     => $model->{constrained} ? 300 : 0,
            max_w     => $model->{constrained} ? 500 : 0,
            min_h     => $model->{constrained} ? 200 : 0,
            max_h     => $model->{constrained} ? 600 : 0,
            centered  => 1,
            resizable => 1,
            child     => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    (    # Window title, editable live from the model
                        Uji::text( 'Title: ' . ( $model->{title} // '' ) ),
                        Uji::text_input(
                            value     => $model->{title} // '',
                            readonly  => $model->{locked},
                            maxlength => 20,
                            on_input  => sub ($text) { { type => 'SET_TITLE', value => $text } }
                        )
                    ), (
                        # Live two-way text binding; locked disables the edit box
                        Uji::text( 'Hello, ' . $model->{name} . '!' ),
                        Uji::text_input(
                            value    => $model->{name},
                            enabled  => !$model->{locked},
                            focused  => $model->{locked} ? 0 : 1,
                            on_input => sub ($text) { { type => 'SET_NAME', value => $text } }
                        )
                    ), (
                        # Range slider with live on_change binding; locked snaps in steps of 25
                        Uji::text( 'Level: ' . $model->{level} ),
                        Uji::slider(
                            value     => $model->{level},
                            min       => 0,
                            max       => 100,
                            step      => ( $model->{locked} ? 25 : 1 ),
                            on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } }
                        )
                    ), (
                        # Checkbox with live two-way binding
                        Uji::checkbox(
                            label     => 'Dark mode',
                            checked   => $model->{dark},
                            on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } }
                        ),
                        Uji::text( 'Dark: ' . ( $model->{dark} ? 'ON' : 'OFF' ) )
                    ), (
                        # Radio group: the model holds one scalar, options map value => label
                        Uji::text('Highlight color'),
                        Uji::radio_group(
                            value   => $model->{color},
                            spacing => 2,
                            options =>
                                [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' } ],
                            on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
                        ),
                        Uji::text( 'Color: ' . ( $model->{color} // '(none)' ) )
                    ), (
                        # Masked password field with two-way binding
                        Uji::password( value => $model->{secret}, on_input => sub ($text) { { type => 'SET_SECRET', value => $text } } ),
                        Uji::text(
                            'Secret: ' . ( '#' x length $model->{secret} ) . ( $model->{secret} ? '' : '(empty)' ),
                            visible => $model->{show_extra}
                        )
                    ), (
                        # Horizontal row with proportional flex buttons
                        Uji::text( 'Counter: ' . $model->{count} ),
                        Uji::row(
                            spacing  => 10,
                            children => [

                                # flex => 2 gets twice the width of flex => 1
                                Uji::button( label => '+1',    flex => 2, on_click => { type => 'INCREMENT' } ),
                                Uji::button( label => 'Reset', flex => 1, on_click => { type => 'RESET' } )
                            ]
                        )
                    ), (
                        # Toggle enabled/readonly/step behavior across the app
                        Uji::button(
                            label    => ( $model->{locked} ? 'Unlock' : 'Lock' ),
                            on_click => { type => 'TOGGLE_LOCK' },
                            tooltip  => 'Toggles enabled on the name box, readonly on the title box, and the slider step'
                        ), (
                            Uji::button(
                                label    => 'Topmost: ' . ( $model->{topmost} ? 'ON' : 'OFF' ),
                                on_click => { type => 'TOGGLE_TOPMOST' },
                                tooltip  => 'Keeps this window above all others'
                            ),
                            Uji::button(
                                label    => 'Constraints: ' . ( $model->{constrained} ? 'ON' : 'OFF' ),
                                on_click => { type => 'TOGGLE_CONSTRAINTS' },
                                tooltip  => 'Clamps the window between 300/500 wide and 200/420 tall'
                            )
                        ), (
                            Uji::button(
                                label    => 'Secret hint ' . ( $model->{show_extra} ? 'shown' : 'hidden' ),
                                on_click => { type => 'TOGGLE_EXTRA' },
                                tooltip  => 'Shows/hides the secret text line (visible prop)'
                            )
                        )
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
