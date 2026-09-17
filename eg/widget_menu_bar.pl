use v5.40;
use utf8;    # source is UTF-8: literals are Unicode, per the utf8everywhere convention
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;
$|++;

package main {

    sub init () {
        return (
            {   last_action => 'none',
                items       => [
                    {   label    => 'File',
                        children => [
                            { label => 'New',    id => 'new', checked => 1 },
                            { label => 'Open',   id => 'open' },
                            { label => '',       id => 'sep', separator => 1 },
                            { label => 'Save',   id => 'save' },
                            { label => 'Delete', id => 'del' }
                        ]
                    },
                    {   label    => 'Edit',
                        children => [
                            { label => 'Undo',     id => 'undo' },
                            { label => 'Redo',     id => 'redo' },
                            { label => 'Disabled', id => 'disabled', enabled => 0 }
                        ]
                    },
                    { label => 'View', children => [ { label => 'Zoom In', id => 'zoom_in' }, { label => 'Zoom Out', id => 'zoom_out' } ] }
                ]
            },
            undef
        );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'MENU_CLICK' ) {
            $model->{last_action} = $msg->{id};

            # Toggle a checkmark on the clicked item. The menu is rebuilt from the model
            # every render, so mutating the model here re-drives the native menu bar.
            CORE::state $flip //= sub ( $items, $id ) {
                for my $it ( @{ $items // [] } ) {
                    return 1 if defined $it->{id} && $it->{id} eq $id && ( $it->{checked} = $it->{checked} ? 0 : 1 );
                    return 1 if $flip->( $it->{children}, $id );
                }
                return 0;
            };
            $flip->( $model->{items}, $msg->{id} );
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Menu Bar Demo',
            w        => 460,
            h        => 220,
            centered => 1,
            menu_bar => Uji::menu_bar( items => $model->{items}, on_click => sub ($id) { { type => 'MENU_CLICK', id => $id } } ),
            child    => Uji::column(
                padding  => 16,
                children => [
                    Uji::text( 'Last menu action: ' . $model->{last_action} ), Uji::text('File menu: New (checked), Open, Save, Delete'),
                    Uji::text('Edit menu: Undo, Redo, Disabled (greyed out)'),
                ],
            ),
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
