use v5.40;
use experimental 'class';
class Uji::App v0.0.1 {    # The TEA Runtime (Parataxis fibers & message loop)
    use Acme::Parataxis          qw[async fiber await_sleep];
    use Acme::Parataxis::Channel qw[];
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::Layout;
    #
    field $init       : param;
    field $update     : param;
    field $view       : param;
    field $model      : reader;
    field $vtree      : reader;
    field $channel    : param //= Acme::Parataxis::Channel->new( capacity => 1024 );
    field $driver     : param //= Uji::Driver::detect();
    field $reconciler : param //= Uji::Reconciler->new();
    field $layout     : param //= Uji::Layout->new( driver => $driver );

    # Clamp a client-area size against the window node's min/max constraints.
    # (min/max live on the root window node so the layout has a single source of truth.)
    method _clamp_size ( $cw, $ch ) {
        $cw = $vtree->min_w if $vtree->min_w && $cw < $vtree->min_w;
        $ch = $vtree->min_h if $vtree->min_h && $ch < $vtree->min_h;
        $cw = $vtree->max_w if $vtree->max_w && $cw > $vtree->max_w;
        $ch = $vtree->max_h if $vtree->max_h && $ch > $vtree->max_h;
        return ( $cw, $ch );
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

    method _boot () {
        ( $model, my $cmd ) = $init->();
        $self->_mount;
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
