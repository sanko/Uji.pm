use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { divider => 180 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'MOVE' ) {    # divider drag -> updates the split's model position
            $model->{divider} = $msg->{pos};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        my $left
            = Uji::column( spacing => 6, padding => 8, children => [ Uji::text('Left pane'), map { Uji::button( label => "Action $_" ) } 1 .. 4 ] );
        my $right = Uji::column(
            spacing  => 6,
            padding  => 8,
            children => [
                Uji::text('Right pane - drag the divider between the panes to resize them.'),
                Uji::scroll_view(
                    Uji::column( spacing => 4, children => [ map { Uji::text("Detail line $_") } 1 .. 20 ] ),
                    orientation => 'vertical'
                )
            ]
        );
        Uji::window(
            title    => 'Uji SplitView Demo',
            w        => 520,
            h        => 360,
            centered => 1,
            child    => Uji::split_view(
                $left, $right,
                orientation => 'horizontal',
                divider     => $model->{divider},
                min_a       => 90,
                min_b       => 70,
                on_divider  => sub ($pos) { { type => 'MOVE', pos => $pos } }
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
