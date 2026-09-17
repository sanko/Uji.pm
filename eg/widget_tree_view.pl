use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { selected => 'b1' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'SET_BRANCH' ) {
            $model->{selected} = $msg->{value};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji TreeView Demo',
            w        => 340,
            h        => 460,
            centered => 1,
            child    => Uji::column(
                padding  => 15,
                spacing  => 12,
                children => [
                    Uji::tree_view(
                        value => $model->{selected},
                        nodes => [
                            {   value    => 'a',
                                label    => 'Alpha',
                                children => [ { value => 'a1', label => 'A-one' }, { value => 'a2', label => 'A-two' }, ]
                            },
                            {   value    => 'b',
                                label    => 'Bravo',
                                children => [
                                    { value => 'b1', label => 'B-one' },
                                    { value => 'b2', label => 'B-two' },
                                    { value => 'b3', label => 'B-three' },
                                ]
                            },
                            { value => 'c', label => 'Charlie', children => [ { value => 'c1', label => 'C-one' }, ] },
                            { value => 'd', label => 'Delta' },
                        ],
                        expanded  => ['a'],
                        on_select => sub ($v) { { type => 'SET_BRANCH', value => $v } }
                    ),
                    Uji::text( 'Selected: ' . ( $model->{selected} // 'none' ) )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
