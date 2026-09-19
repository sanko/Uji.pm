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
            w        => 420,
            h        => 150,
            centered => 1,
            child    => Uji::column(
                padding  => 10,
                spacing  => 10,
                children => [
                    Uji::toolbar(
                        icon_size => 16,
                        buttons   => [
                            { label => 'New',    id => 'new',    checked => 1, icon => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGP8z8Dwn4EIwERQxQwwAAAoWgHJi0x4WQAAAABJRU5ErkJggg==' },
                            { label => 'Open',   id => 'open',   icon => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGP8z8Dwn4EIwERQxQwwAAAoWgHJi0x4WQAAAABJRU5ErkJggg==' },
                            { label => '',       id => 'sep',    separator => 1 },
                            { label => 'Save',   id => 'save',   icon => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGP8z8Dwn4EIwERQxQwwAAAoWgHJi0x4WQAAAABJRU5ErkJggg==' },
                            { label => 'Delete', id => 'del' }
                        ],
                        on_click => sub ($id) { { type => 'TB_CLICK', id => $id } }
                    ),
                    Uji::text( 'Last action: ' . $model->{last_clicked} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
