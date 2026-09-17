use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { clicks => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'CLICK' ) {
            $model->{clicks}++;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Fit Policy Demo',
            w        => 380,
            h        => 340,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::text('Fit + align policy demo:'),
                    Uji::text( 'Centered heading', fit => 'content', align_w => 'center' ),
                    Uji::row(
                        align_h => 'center',
                        spacing => 10,
                        children => [
                            Uji::button( label => 'Hug me', fit => 'content' ),
                            Uji::button( label => 'Aligned', fit_w => 'content', align_h => 'end' ),
                            Uji::button( label => 'Fills',  fit => 'fill' ),
                        ],
                    ),
                    Uji::text( 'Wide, clamped to 120px', fit_w => 'content', min_w => 120, max_w => 120 ),
                    Uji::button( label => 'This one flexes: ' . $model->{clicks}, flex => 1, fit_h => 'fill', on_click => { type => 'CLICK' } ),
                    Uji::button( label => 'Fixed', w => 120, h => 30, on_click => { type => 'CLICK' } )
                ],
            ),
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
