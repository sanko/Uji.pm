use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { last_clicked => 'none' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'TB_CLICK' ) {
            $model->{last_clicked} = $msg->{id};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Toolbar Demo',
            w        => 380,
            h        => 140,
            centered => 1,
            child    => Uji::column(
                padding  => 10,
                spacing  => 10,
                children => [
                    Uji::toolbar(
                        buttons => [
                            { label => 'New',    id => 'new', checked => 1, },
                            { label => 'Open',   id => 'open' },
                            { label => '',       id => 'sep', separator => 1 },
                            { label => 'Save',   id => 'save' },
                            { label => 'Delete', id => 'del' },
                        ],
                        on_click => sub ($id) { { type => 'TB_CLICK', id => $id } },
                    ),
                    Uji::text( 'Last action: ' . $model->{last_clicked} ),
                ],
            ),
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
