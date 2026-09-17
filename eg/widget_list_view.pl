use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { selected => 'AB-12', picks => [], stock => [ [ 'AB-12', 'Apples',  3, 1.25 ], [ 'AB-21', 'Bananas', 2, 0.75 ], [ 'CD-34', 'Cherries', 5, 2.00 ], [ 'DE-45', 'Damsons', 8, 1.50 ], [ 'EF-56', 'Figs', 1, 3.10 ] ] }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_SKU' ) {
            $model->{selected} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_PICKS' ) {
            $model->{picks} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'RESORT' ) {
            my ( $col, $dir ) = @{ $msg->{value} };
            my @rows = @{ $model->{stock} };
            my $num  = $col >= 2;    # Qty/Price columns sort numerically
            @rows = sort {
                my $cmp = $num
                    ? ( ( $a->[$col] + 0 ) <=> ( $b->[$col] + 0 ) )
                    : ( lc( $a->[$col] ) cmp lc( $b->[$col] ) );
                return $dir eq 'asc' ? $cmp : -$cmp;
            } @rows;
            $model->{stock} = \@rows;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji ListView Demo',
            w        => 620,
            h        => 560,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::list_view(
                        value             => $model->{selected},
                        sortable          => 1,
                        reorderable       => 1,
                        full_row_select   => 1,
                        grid_lines        => 1,
                        columns => [
                            { label => 'SKU',   width => 90 },
                            { label => 'Fruit', width => 160 },
                            { label => 'Qty',   width => 70, sort => 'numeric', align => 'center' },
                            { label => 'Price', width => 80, sort => 'numeric', format => '$%0.2f', align => 'right' },
                        ],
                        rows       => $model->{stock},
                        on_select  => sub ($v) { { type => 'SET_SKU', value => $v } },
                        on_sort    => sub ($col, $dir) { { type => 'RESORT', value => [ $col, $dir ] } },
                        on_reorder => sub ($order) { { type => 'NOP' } }    # native columns already moved
                    ),
                    Uji::list_view(
                        multiple => 1,
                        value    => $model->{picks},
                        columns  => [ { label => 'Fruit', width => 200 } ],
                        rows     => [
                            { value => 'Apples',   columns => ['Apples'] },
                            { value => 'Bananas',  columns => ['Bananas'] },
                            { value => 'Cherries', columns => ['Cherries'] }
                        ],
                        on_select => sub ($v) { { type => 'SET_PICKS', value => $v } }
                    ),
                    Uji::text(
                        'Selected: ' . ( $model->{selected} // 'none' )
                            . ' | Picks: ' . join( ', ', @{ $model->{picks} } )
                            . '  ·  click headers to sort, drag headers to reorder (Qty/Price sort numerically; Price shows $1.25)'
                    )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
