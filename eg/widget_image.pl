use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    # A tiny base64 PNG (1x1) to swap in; eg/inline.png (any size) is used when present.
    my $swap_png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    sub init () {
        return ( { fit => 'contain', swaps => 0, status => 'contain: the whole image fits.' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'CYCLE' ) {
            $model->{fit} = $model->{fit} eq 'contain' ? 'cover' : $model->{fit} eq 'cover' ? 'fill' : 'contain';
            my %what = ( contain => 'contain: the whole image fits inside the box.',
                cover   => 'cover: the box is filled, excess cropped.',
                fill    => 'fill: stretched to the box, aspect ignored.' );
            $model->{status} = $what{ $model->{fit} };
        }
        elsif ( $msg->{type} eq 'SWAP' ) {
            $model->{swaps}++;
            $model->{status} = "Swapped in a data:image URI ($model->{swaps} times).";
        }
        return ( $model, undef );
    }

    sub view ($model) {

        # Path-based source (eg/inline.png when present) or the bundled data: URI.
        my $src = -e "$FindBin::Bin/inline.png" ? "$FindBin::Bin/inline.png" : "data:image/png;base64,$swap_png";

        Uji::window(
            title    => 'Uji Image Demo',
            w        => 420,
            h        => 300,
            centered => 1,
            child    => Uji::column(
                padding  => 24,
                spacing  => 14,
                children => [
                    Uji::row(
                        align_h  => 'center',
                        spacing  => 16,
                        children => [
                            Uji::image( src => $src, w => 120, h => 60, object_fit => $model->{fit} ),
                            Uji::image( src => $src, w => 90,  h => 60, object_fit => 'fill' ),
                        ],
                    ),
                    Uji::image( src => $src, w => 220, h => 90, object_fit => $model->{fit} ),
                    Uji::separator(),
                    Uji::row(
                        align_h  => 'center',
                        spacing  => 12,
                        children => [
                            Uji::button( label => "Fit: $model->{fit}", fit => 'content', on_click => { type => 'CYCLE' } ),
                            Uji::button( label => 'Swap picture',       fit => 'content', on_click => { type => 'SWAP' } ),
                        ],
                    ),
                    Uji::status_text( $model->{status} ),
                ],
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}