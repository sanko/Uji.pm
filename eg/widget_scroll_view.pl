use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { count => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'ADD_ROW' ) {
            $model->{count}++;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        my $content = Uji::column(
            spacing  => 6,
            padding  => 6,
            children => [ map { Uji::text("Log line #$_ — the scroll view clips overflow and shows a scrollbar.") } 1 .. 30 + $model->{count} ]
        );
        Uji::window(
            title    => 'Uji ScrollView Demo',
            w        => 380,
            h        => 300,
            centered => 1,
            child    => Uji::column(
                padding  => 10,
                spacing  => 8,
                children => [
                    Uji::row( children => [ Uji::button( label => 'Add a row', on_click => { type => 'ADD_ROW' } ) ] ),
                    Uji::scroll_view( $content, orientation => 'vertical', on_scroll => sub ( $x, $y ) { { type => 'SCROLLED', x => $x, y => $y } } )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
