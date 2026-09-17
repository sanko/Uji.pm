use v5.40;
use blib;
use Uji qw[:all];
#
# A stopwatch driven by a 100ms interval subscription, plus a resize counter.
# Neither is started by hand: the subscriptions callback declares what the
# current model wants, and the runtime starts / stops timers to match.
#
app(
    init => sub () {
        return ( { running => 1, ms => 0, resizes => 0 }, undef );
    },
    update => sub ( $msg, $model ) {
        if    ( $msg->{type} eq 'TICK' )    { $model->{ms} += 100 }
        elsif ( $msg->{type} eq 'START' )   { $model->{running} = 1 }
        elsif ( $msg->{type} eq 'STOP' )    { $model->{running} = 0 }
        elsif ( $msg->{type} eq 'RESET' )   { $model->{ms} = 0 }
        elsif ( $msg->{type} eq 'RESIZED' ) { $model->{resizes} += 1 }
        return ( $model, undef );
    },
    subscriptions => sub ($model) {
        my @subs = ( sub_on_resize( { type => 'RESIZED' } ) );
        push @subs, sub_interval( 100, { type => 'TICK' } ) if $model->{running};
        return \@subs;
    },
    view => sub ($model) {
        my $seconds = sprintf '%.1f', $model->{ms} / 1000;
        window(
            title    => 'Uji Subscriptions Demo',
            w        => 360,
            h        => 220,
            centered => 1,
            child    => column(
                padding  => 15,
                spacing  => 12,
                children => [
                    text( "Elapsed: ${seconds}s" ),
                    text( 'Window resizes seen: ' . $model->{resizes} ),
                    row(
                        spacing  => 10,
                        children => [
                            button( label => 'Start', on_click => { type => 'START' } ),
                            button( label => 'Stop',  on_click => { type => 'STOP' } ),
                            button( label => 'Reset', on_click => { type => 'RESET' } )
                        ]
                    )
                ]
            )
        );
    }
)->run();
