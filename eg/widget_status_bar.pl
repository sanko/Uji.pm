use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { answers => 3 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'ANSWERED' ) {
            $model->{answers}++;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji StatusBar Demo',
            w        => 360,
            h        => 180,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::button( label => 'Answer', on_click => { type => 'ANSWERED' }, ),
                    Uji::status_bar( panels => [ 'Hull integrity OK', "Answers: $model->{answers}", 'v1.0' ] )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
