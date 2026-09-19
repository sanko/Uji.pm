use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { running => 1, status => 'An indicator spinner: swap running with the toggle.' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'TOGGLE' ) {
            $model->{running} = $model->{running} ? 0 : 1;
            $model->{status}  = $model->{running} ? 'Spinner is running.' : 'Spinner stopped.';
        }
        elsif ( $msg->{type} eq 'TICK' ) {
            $model->{count} = ( $model->{count} // 0 ) + 1;
            $model->{status} = "Tick $model->{count} - the spinner is still spinning.";
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Spinner Demo',
            w        => 360,
            h        => 220,
            centered => 1,
            child    => Uji::column(
                padding  => 24,
                spacing  => 16,
                children => [
                    Uji::row(
                        align_h   => 'center',
                        spacing   => 18,
                        children  => [
                            map { Uji::spinner( size => $_, running => $model->{running} ) } ( 16, 28, 48 )
                        ]
                    ),
                    Uji::separator(),
                    Uji::button(
                        label    => $model->{running} ? 'Stop' : 'Spin',
                        fit      => 'content',
                        align_h  => 'center',
                        on_click => { type => 'TOGGLE' }
                    ),
                    Uji::status_text( $model->{status} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
