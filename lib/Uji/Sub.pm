use v5.40;
use experimental 'class';
class Uji::Sub v0.0.1 {
    use Acme::Parataxis qw[fiber await_sleep];
    field $key   : param : reader;
    field $start : param : reader;    # sub ($channel) -> $cancel_callback

    # Execute the subscription's start handler and return the cancellation callback
    method run ($channel) {
        return $start->($channel);
    }

    # Factory: Interval timer subscription
    sub every ( $ms, $action, %args ) {
        my $key = $args{key} // ( "every:" . $ms . ":" . ( ref $action eq 'CODE' ? "$action" : ( $action->{type} // 'anon' ) ) );
        return Uji::Sub->new(
            key   => $key,
            start => sub ($channel) {
                my $active = 1;
                fiber {
                    while ($active) {
                        await_sleep($ms);
                        last unless $active;
                        my $msg = ref $action eq 'CODE' ? $action->( time() ) : $action;
                        $channel->put($msg) if $msg;
                    }
                };

                # Return cooperative cancellation handle
                return sub { $active = 0 };
            }
        );
    }

    # Factory: Combine multiple subscriptions
    sub batch (@subs) {
        return \@subs;
    }

    # Factory: No active subscriptions
    sub none () {
        return ();
    }
};
1;
