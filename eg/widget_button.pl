use v5.40;
use blib;
use Uji qw[:all];
#
app(
    init => sub () {
        return ( { count => 0 }, undef );
    },
    update => sub ( $msg, $model ) {
        $model->{count} = $msg->{value} if $msg->{type} eq 'SET_COUNT';
        return ( $model, undef );
    },
    view => sub ($model) {
        window(
            title    => 'Uji Button Demo',
            w        => 360,
            h        => 200,
            centered => 1,
            child    => column(
                padding  => 15,
                spacing  => 12,
                children => [
                    text( 'Count: ' . $model->{count} ),

                    # on_click can be a static message hashref or a callback.
                    row(
                        spacing  => 10,
                        children => [
                            button( label => '-1',    on_click => { type => 'SET_COUNT', value => $model->{count} - 1 } ),
                            button( label => '+1',    flex     => 1, on_click => { type => 'SET_COUNT', value => $model->{count} + 1 } ),
                            button( label => 'Reset', on_click => sub { { type => 'SET_COUNT', value => 0 } } )
                        ]
                    ),
                    button( label => 'Tooltip button', tooltip => 'Hover me for a hint' )
                ]
            )
        );
    }
)->run();
