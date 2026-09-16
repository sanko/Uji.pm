use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { pick => 3, picks => [ 2, 5 ] }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_PICK' ) {
            $model->{pick} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_PICKS' ) {
            $model->{picks} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji ListBox Demo',
            w        => 360,
            h        => 400,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Single selection'),

                    # A visible scrollable list; the height sizes to the option count (max ~6 rows).
                    Uji::list_box(
                        value     => $model->{pick},
                        options   => [ map { { value => $_, label => 'Row ' . $_ } } 1 .. 20 ],
                        on_select => sub ($v) { { type => 'SET_PICK', value => $v } }
                    ),
                    Uji::text( 'Picked: row ' . ( $model->{pick} // 'none' ) ),
                    Uji::text('Multiple selection (click several)'),
                    Uji::list_box(
                        multiple  => 1,
                        value     => $model->{picks},
                        options   => [ map { { value => $_, label => 'Row ' . $_ } } 1 .. 20 ],
                        on_select => sub ($v) { { type => 'SET_PICKS', value => $v } }
                    ),
                    Uji::text( 'Picked rows: ' . ( @{ $model->{picks} } ? join( ', ', map {"row $_"} @{ $model->{picks} } ) : 'none' ) )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
