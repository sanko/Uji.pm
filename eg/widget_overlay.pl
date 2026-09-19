use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { badge => 1, count => 0, status => 'The badge sits bottom-right over the frame.' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'HIDE' ) {
            $model->{badge}  = $model->{badge} ? 0              : 1;
            $model->{status} = $model->{badge} ? 'Badge shown.' : 'Badge hidden.';
        }
        elsif ( $msg->{type} eq 'COUNT' ) {
            $model->{count}++;
            $model->{status} = "Clicked $model->{count} time" . ( $model->{count} == 1 ? '' : 's' );
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Overlay Demo',
            w        => 420,
            h        => 320,
            centered => 1,
            child    => Uji::column(
                padding  => 16,
                spacing  => 12,
                children => [

                    # An overlay stacks its children in the same plane: array order is the draw
                    # order, so later layers paint over earlier ones. Child 1 is the full frame
                    # (it fills the box by default); child 2 is a content-fit badge aligned to
                    # the bottom-right corner.
                    Uji::overlay(
                        children => [
                            Uji::text( 'Overlay demo frame', w => 388, h => 180, align => 'center', font_size => 18, ), (
                                $model->{badge} ?
                                    Uji::button(
                                    id       => 'badge',
                                    label    => sprintf( '%d hits', $model->{count} ),
                                    fit      => 'content',
                                    align_w  => 'end',
                                    align_h  => 'end',
                                    on_click => { type => 'COUNT' }
                                    ) :
                                    ()
                            ),
                        ],
                    ),
                    Uji::separator(),
                    Uji::button( label => 'Toggle badge', on_click => { type => 'HIDE' } ),
                    Uji::status_text( $model->{status} )
                ],
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
