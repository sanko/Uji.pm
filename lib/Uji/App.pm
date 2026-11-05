use v5.40;
use experimental 'class';
class Uji::App v0.0.1 {    # The TEA Runtime (Parataxis fibers & message loop)
    use Acme::Parataxis          qw[async fiber await_sleep];
    use Acme::Parataxis::Channel qw[];
    use builtin                  qw[blessed];
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::Layout;
    field $init          : param;
    field $update        : param;
    field $view          : param;
    field $subscriptions : param //= undef;
    field $model         : reader;
    field $vtree         : reader;
    field $channel       : param //= Acme::Parataxis::Channel->new( capacity => 1024 );
    field $driver        : param //= Uji::Driver::detect();
    field $reconciler    : param //= Uji::Reconciler->new();
    field $layout        : param //= Uji::Layout->new( driver => $driver );
    field $active_subs   : reader = {};    # key => { sub => $sub, cancel => $cancel_fn }

    # Clamp a client-area size against the window node's min/max constraints.
    method _clamp_size ( $cw, $ch ) {
        return $vtree->clamp_size( $cw, $ch );
    }

    method _relayout_now ( $cw = undef, $ch = undef ) {
        return unless $vtree && $driver->can('_is_mounted') && $driver->_is_mounted();

        #~ print $lfh "RELAYOUT cw=$cw ch=$ch vtree=$vtree layout=$layout\n";
        # Use the client size passed by WM_SIZE's lParam; fall back to a fresh measure if it was
        # not supplied. Runs inside the wndproc, so no fiber switch allows live updates during the
        # drag loop.
        if ( defined $cw && defined $ch ) {
            ( $cw, $ch ) = $self->_clamp_size( $cw, $ch );
            $vtree->set_bounds( 0, 0, $cw, $ch );
        }
        else {
            $driver->sync_window_bounds($vtree);
        }
        $layout->compute($vtree);
        $self->_move_all( $vtree, $driver );
    }

    method _move_all ( $node, $driver ) {
        $driver->move_widget( $node->id, $node->bx, $node->by, $node->bw, $node->bh ) unless $node->type eq 'window';
        $self->_move_all( $_, $driver ) for @{ $node->children };
    }

    # Flatten nested arrays and batches of subscriptions into a flat list of Uji::Sub instances
    method _flatten_subs ($raw) {
        return () unless defined $raw;
        my @result;
        my @queue = ref $raw eq 'ARRAY' ? @$raw : ($raw);
        while (@queue) {
            my $item = shift @queue;
            next unless defined $item;
            if ( ref $item eq 'ARRAY' ) {
                unshift @queue, @$item;
            }
            elsif ( blessed($item) && $item->isa('Uji::Sub') ) {
                push @result, $item;
            }
        }
        return @result;
    }

    # Declarative subscription reconciler: starts new fibers, leaves running ones intact, cancels retired ones
    method _sync_subscriptions () {
        return unless $subscriptions;
        my $raw      = $subscriptions->($model);
        my @new_list = $self->_flatten_subs($raw);
        my %new_by_key;
        for my $sub (@new_list) {
            next unless $sub && $sub->can('key');
            $new_by_key{ $sub->key } = $sub;
        }

        # Cancel fibers for subscriptions no longer returned by the model
        for my $key ( keys %$active_subs ) {
            unless ( exists $new_by_key{$key} ) {
                my $record = delete $active_subs->{$key};
                $record->{cancel}->() if $record && $record->{cancel};
            }
        }

        # Spawn fibers for newly requested subscriptions
        for my $key ( keys %new_by_key ) {
            unless ( exists $active_subs->{$key} ) {
                my $sub       = $new_by_key{$key};
                my $cancel_fn = $sub->run($channel);
                $active_subs->{$key} = { sub => $sub, cancel => $cancel_fn };
            }
        }
    }

    method _boot () {
        ( $model, my $cmd ) = $init->();
        $self->_mount;
        $self->_sync_subscriptions;
    }

    # Mount the window, lay out the initial vtree, and create the child widgets.
    method _mount () {
        $vtree = $view->($model);

        # Mount window first so we can measure its real client area,
        # then compute layout against that, then create the child widgets.
        $driver->mount($vtree);
        $layout->compute($vtree);
        $driver->mount_children($vtree);
    }

    # Rebuild the view from the current model and reconcile the diff into the driver.
    method _render () {
        my $new_vtree = $view->($model);
        $driver->sync_window_bounds($new_vtree);
        $layout->compute($new_vtree);
        $reconciler->patch( $vtree, $new_vtree, $driver );
        $vtree = $new_vtree;
    }

    # First message already read off the channel; drain any stragglers, fold every message
    # through update(), then re-render. (Extracted so tests can drive a render synchronously.)
    method _drain_and_render ($first_msg) {
        exit(0) if ref $first_msg eq 'HASH' && $first_msg->{type} eq 'QUIT';
        my @batch = ($first_msg);
        push @batch, $channel->get() while $channel->size;
        for my $m (@batch) {
            exit(0) if ref $m eq 'HASH' && $m->{type} eq 'QUIT';

            # WM_SIZE -> skip the app's update (model unchanged), but fall through so
            # the re-layout below still runs.
            next if $m->{type} eq 'RESIZE';
            ( my $new_model, my $new_cmd ) = $update->( $m, $model );
            $model = $new_model;
        }
        $self->_render;
        $self->_sync_subscriptions;
    }

    method run () {
        $driver->init($channel);
        $driver->set_resize_handler( sub { $self->_relayout_now(@_) } );
        async {
            $self->_boot;
            fiber {
                while (1) {
                    $driver->poll_events();
                    await_sleep(2);
                }
            };
            fiber {
                while ( my $msg = $channel->get() ) {
                    $self->_drain_and_render($msg);
                }
            };
        };
    }
};
1;
