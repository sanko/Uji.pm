use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { selected => 'AB-12', picks => [] }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_SKU' ) {
            $model->{selected} = $msg->{value};
        }
        elsif ( $msg->{type} eq 'SET_PICKS' ) {
            $model->{picks} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji ListView Demo',
            w        => 560,
            h        => 460,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::list_view(
                        value          => $model->{selected},
                        columns        => [
                            { label => 'SKU',   width => 90  },
                            { label => 'Fruit', width => 160 },
                            { label => 'Qty',   width => 70  },
                        ],
                        rows           => [
                            [ 'AB-12', 'Apples',   '3' ],
                            [ 'AB-21', 'Bananas',  '2' ],
                            { value => 'CD-34', columns => [ 'CD-34', 'Cherries', '5' ] },
                            [ 'DE-45', 'Damsons',  '8' ],
                            [ 'EF-56', 'Figs',     '1' ],
                        ],
                        full_row_select => 1,
                        grid_lines      => 1,
                        on_select       => sub ($v) { { type => 'SET_SKU', value => $v } }
                    ),
                    Uji::list_view(
                        multiple   => 1,
                        value      => $model->{picks},
                        columns    => [ { label => 'Fruit', width => 200 } ],
                        rows       => [
                            { value => 'Apples',  columns => ['Apples'] },
                            { value => 'Bananas', columns => ['Bananas'] },
                            { value => 'Cherries', columns => ['Cherries'] },
                        ],
                        on_select  => sub ($v) { { type => 'SET_PICKS', value => $v } }
                    ),
                    Uji::text( 'Selected: ' . ( $model->{selected} // 'none' ) . ' | Picks: ' . join( ', ', @{ $model->{picks} } ) )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}