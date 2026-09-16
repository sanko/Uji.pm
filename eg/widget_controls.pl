use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { level => 40, enabled => 0, locked => 1, info => 'Ready' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_LEVEL' ) {
            $model->{level} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'TOGGLE_SW' ) {
            $model->{enabled} = $msg->{value} ? 1 : 0;
        }
        elsif ( $msg->{type} eq 'TOGGLE_LOCK' ) {
            $model->{locked} = $msg->{value} ? 1 : 0;
        }
        elsif ( $msg->{type} eq 'OPEN_LINK' ) {
            $model->{info} = 'You clicked the link!';
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Controls Demo',
            w        => 360,
            h        => 560,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text( 'Level: ' . $model->{level} . '%' ),
                    Uji::progress_bar( value => $model->{level}, min => 0, max => 100 ),
                    Uji::spin_box(
                        value     => $model->{level},
                        min       => 0,
                        max       => 100,
                        step      => 5,
                        enabled   => $model->{enabled},
                        on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } }
                    ),
                    Uji::toggle_switch(
                        label     => 'Enable editing',
                        checked   => $model->{enabled},
                        on_toggle => sub ($on) { { type => 'TOGGLE_SW', value => $on } }
                    ),
                    Uji::toggle_button(
                        label     => ( $model->{locked} ? 'Locked' : 'Unlocked' ),
                        checked   => $model->{locked},
                        on_toggle => sub ($on) { { type => 'TOGGLE_LOCK', value => $on } }
                    ),
                    Uji::link_button( label => 'Visit docs', on_click => { type => 'OPEN_LINK' } ),
                    Uji::text( $model->{info} ),
                    Uji::text( 'Props batch', align => 'center', color => '#1E6FEB', font_size => 10 ),
                    Uji::password( value => '', placeholder => 'Password', password_char => '*', font => 'Consolas' ),
                    Uji::multiline_text( value => "line one\nline two\nline three", color => '#0F7B0F', focused => 0 ),
                    Uji::row(
                        spacing  => 12,
                        children => [
                            Uji::slider(
                                orientation => 'vertical',
                                value       => $model->{level},
                                min         => 0,
                                max         => 100,
                                on_change   => sub ($v) { { type => 'SET_LEVEL', value => $v } }
                            ),
                            Uji::text( 'Vertical', color => '#888888' )
                        ]
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
