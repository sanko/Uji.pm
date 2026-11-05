use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    my @items;
    for my $i ( 1 .. 25 ) {
        push @items, { id => $i, title => "Task item #$i - Description of item content", done => ( $i % 3 == 0 ? 1 : 0 ), count => 0 };
    }
    return ( { items => \@items, status => 'Scroll with mousewheel or drag the scrollbar' }, undef );
};
my $update = sub ( $msg, $model ) {
    my $m = { %$model, items => [ @{ $model->{items} } ] };
    my $t = $msg->{type};
    if ( $t eq 'TOGGLE' ) {
        for my $item ( @{ $m->{items} } ) {
            if ( $item->{id} == $msg->{id} ) {
                $item->{done} = $msg->{val};
                $m->{status}  = "Toggled item #$msg->{id}";
                last;
            }
        }
    }
    elsif ( $t eq 'CLICK_ITEM' ) {
        for my $item ( @{ $m->{items} } ) {
            if ( $item->{id} == $msg->{id} ) {
                $item->{count}++;
                $m->{status} = "Clicked button on item #$msg->{id} ($item->{count} times)";
                last;
            }
        }
    }
    return ( $m, undef );
};
my $view = sub ($model) {
    my @rows;
    for my $it ( @{ $model->{items} } ) {
        my $id = $it->{id};
        push @rows,
            row(
            key      => "row-$id",
            spacing  => 8,
            children => [
                checkbox(
                    key       => "chk-$id",
                    label     => '',
                    checked   => $it->{done},
                    on_toggle => sub ($v) { { type => 'TOGGLE', id => $id, val => $v } }
                ),
                text( ( $it->{done} ? "[DONE] " : "" ) . $it->{title}, key => "txt-$id", flex => 1 ),
                button( key => "btn-$id", label => "Hit ($it->{count})", on_click => { type => 'CLICK_ITEM', id => $id } )
            ]
            );
    }
    window(
        title    => 'Uji Native ScrollView & Hardware Clipping Demo',
        w        => 560,
        h        => 480,
        centered => 1,
        child    => column(
            padding  => 14,
            spacing  => 10,
            children => [
                text('Scrollable List (25 items in a 360px clipped viewport):'),

                # Native ScrollView container: hardware clips everything outside 360px height
                scroll_view( flex => 1, child => column( padding => 8, spacing => 6, children => \@rows ) ),

                # Bottom status bar sitting cleanly outside the scroll view
                row(
                    spacing  => 10,
                    children => [ text("Status: $model->{status}"), spacer(), text( "Total items: " . scalar( @{ $model->{items} } ) ) ]
                )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
