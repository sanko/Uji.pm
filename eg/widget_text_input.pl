use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { name => '' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_NAME' ) {
            $model->{name} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji TextInput Demo',
            w        => 360,
            h        => 220,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Type on the field below...'),
                    Uji::text_input( value => $model->{name}, focused => 1, on_input => sub ($text) { { type => 'SET_NAME', value => $text } } ),
                    Uji::text( 'Echo: ' . ( $model->{name} || '(empty)' ) ),
                    Uji::text_input( value => 'A read-only field', readonly => 1, maxlength => 20 )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
