use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;
$|++;

package main {

    sub init () {
        return ( { date => '2026-09-17' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_DATE' ) {
            $model->{date} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji DatePicker Demo',
            w        => 300,
            h        => 220,
            centered => 1,

            # DTM_SETSYSTEMTIME (0x1002, GDT_VALID) at mount; DTN_DATETIMECHANGE (-759) reports
            # every user change as ISO-8601 through on_change, exactly like the slider's on_change.
            child => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text( 'Selected: ' . ( $model->{date} // '(none)' ) ),
                    Uji::date_picker(
                        value     => $model->{date},
                        format    => 'short',
                        min       => '2020-01-01',
                        max       => '2030-12-31',
                        show_none => 1,
                        on_change => sub ($iso) { { type => 'SET_DATE', value => $iso } }
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
