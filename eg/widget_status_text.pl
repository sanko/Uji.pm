use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { status => 'Ready', saved => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'REPORT' ) {
            $model->{status} = 'Last action: ' . $msg->{value};
        }
        elsif ( $msg->{type} eq 'SAVE' ) {
            $model->{saved}++;
            $model->{status} = 'Saved ' . $model->{saved} . ' time' . ( $model->{saved} == 1 ? '' : 's' );
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji StatusText Demo',
            w        => 360,
            h        => 180,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::status_text( $model->{status}, align => 'center' ),
                    Uji::row(
                        spacing  => 8,
                        children => [
                            Uji::button( label => 'Touch', on_click => { type => 'REPORT', value => 'touchdown' } ),
                            Uji::button( label => 'Save',  on_click => { type => 'SAVE' } )
                        ]
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
