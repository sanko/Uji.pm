use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { month => '2026-05', iso => '2026-05-04', status => 'Pick a day, or step months with the arrows.' }, undef );
    }

    sub step_month ( $month, $delta ) {
        my ( $y, $m ) = split /-/, $month;
        $m += $delta;
        if ( $m < 1 )  { $m += 12; --$y; }
        if ( $m > 12 ) { $m -= 12; ++$y; }
        return sprintf '%04d-%02d', $y, $m;
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'PICKED' ) {
            $model->{iso}    = $msg->{value};
            $model->{status} = "Selected $msg->{value}";
        }
        elsif ( $msg->{type} eq 'MONTH' ) {
            $model->{month}  = step_month( $model->{month}, $msg->{delta} );
            $model->{status} = "Showing $model->{month}";
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Calendar Demo',
            w        => 320,
            h        => 360,
            centered => 1,
            child    => Uji::column(
                padding  => 12,
                spacing  => 10,
                children => [
                    Uji::calendar(
                        month     => $model->{month},
                        value     => $model->{iso},
                        on_select => sub ($iso) { { type => 'PICKED', value => $iso } },
                        on_nav    => sub ($delta) { { type => 'MONTH', delta => $delta } },
                    ),
                    Uji::status_text( $model->{status} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}