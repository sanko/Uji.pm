use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { loud => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'TOGGLE_LOUD' ) {
            $model->{loud} = $model->{loud} ? 0 : 1;
        }
        elsif ( $msg->{type} eq 'SHOUT' ) {
            return ( undef, $model->{loud} ? 'LOUDLY!' : 'softly.' );
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji GroupBox Demo',
            w        => 360,
            h        => 240,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::group_box(
                        label    => 'Sound settings',
                        padding  => 10,
                        spacing  => 8,
                        children => [
                            Uji::checkbox( label => 'Loud mode', checked => $model->{loud}, on_toggle => sub ($on) { { type => 'TOGGLE_LOUD' } } ),
                            Uji::button( label => 'Shout', on_click => { type => 'SHOUT' } )
                        ]
                    ),
                    Uji::row( children => [ Uji::button( label => 'Demo', on_click => { type => 'DEMO' } ) ] )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
