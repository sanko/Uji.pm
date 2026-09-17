use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

package main {

    sub init () {
        return ( { tab => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'TAB' ) {    # user switched tabs -> updates the model index
            $model->{tab} = $msg->{i};
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji TabPanel Demo',
            w        => 420,
            h        => 300,
            centered => 1,
            child    => Uji::tab_panel(
                panels => [
                    {   title => 'General',
                        child => Uji::column(
                            spacing  => 6,
                            padding  => 8,
                            children => [
                                Uji::text('Name'),
                                Uji::text_input( placeholder => 'Your name' ),
                                Uji::text('Colour'),
                                Uji::combo_box(
                                    options => [
                                        { value => 'Red',   label => 'Red' },
                                        { value => 'Green', label => 'Green' },
                                        { value => 'Blue',  label => 'Blue' }
                                    ],
                                    value => 'Red'
                                ),
                            ]
                        )
                    },
                    {   title => 'Advanced',
                        child => Uji::column(
                            spacing  => 8,
                            padding  => 8,
                            children => [
                                Uji::text('Verbose logging'),
                                Uji::checkbox( label => 'Enable diagnostics', checked => 0 ),
                                Uji::button( label => 'Reset to defaults' )
                            ]
                        )
                    },
                    {   title => 'About',
                        child => Uji::column(
                            spacing  => 6,
                            padding  => 8,
                            children => [ Uji::text('Uji TabPanel demo'), Uji::progress_bar( value => 40, max => 100 ), Uji::button( label => 'OK' ) ]
                        )
                    },
                ],
                index     => $model->{tab},
                on_select => sub ($i) { { type => 'TAB', i => $i } }
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
