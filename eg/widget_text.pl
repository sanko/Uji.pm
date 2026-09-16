use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { name => 'Uji.pm', mood => 'curious', clicks => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_NAME' ) {
            $model->{name} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_MOOD' ) {
            $model->{mood} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'CLICK' ) {
            $model->{clicks}++;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title     => 'Uji Text Demo',
            w         => 380,
            h         => 260,
            centered  => 1,
            resizable => 1,

            # Text nodes are just labels; Uji::text() is fully recomposed live by the
            # reconciler whenever the model changes.
            child => Uji::column(
                padding  => 15,
                spacing  => 10,
                children => [
                    Uji::text( 'Hello, ' . $model->{name} . '!' ),
                    Uji::text( 'I feel ' . $model->{mood} . ' after ' . $model->{clicks} . ' clicks.' ),
                    Uji::text('Uji::text() is the lightweight static-label widget.'),
                    Uji::text( 'This line has a tooltip.', tooltip => 'Just a label!' ),
                    Uji::text_input( value => $model->{name}, on_input => sub ($text) { { type => 'SET_NAME', value => $text } } ),
                    Uji::row(
                        spacing  => 10,
                        children => [
                            Uji::button( label => 'Mood: happy',  on_click => { type => 'SET_MOOD', value => 'happy' } ),
                            Uji::button( label => 'Mood: sleepy', on_click => { type => 'SET_MOOD', value => 'sleepy' } ),
                            Uji::button( label => 'Click me',     on_click => { type => 'CLICK' } )
                        ]
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
