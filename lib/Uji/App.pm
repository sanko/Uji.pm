use v5.40;
use experimental 'class';
class Uji::App v0.0.1 {    # The TEA Runtime (Parataxis fibers & message loop)
    use Acme::Parataxis          qw[async fiber await_sleep];
    use Acme::Parataxis::Channel qw[];
    use Time::HiRes ();
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::Layout;
    use Uji::Sub ();
    #
    field $init          : param;
    field $update        : param;
    field $view          : param;
    field $subscriptions : param = undef;    # sub ($model) { ...subs... }, or undef for none
    field $model         : reader;
    field $vtrees        : reader;
    field $active_subs   : reader = {};      # key => live subscription (introspection/testing)
    field $channel       : param //= Acme::Parataxis::Channel->new( capacity => 1024 );
    field $driver        : param //= Uji::Driver::detect();
    field $reconciler    : param //= Uji::Reconciler->new();
    field $layout        : param //= Uji::Layout->new( driver => $driver );
    field $dark_mode      = undef;    # boot-time snapshot of the driver colour scheme

    sub _now_ms () { return Time::HiRes::time() * 1000 }

    # Turn a subscription's message (a hashref, or a coderef called with the current
    # time in ms) into a concrete message.
    sub _resolve_msg ( $sub, $now ) {
        my $msg = $sub->{msg};
        $msg = $msg->($now) if ref $msg eq 'CODE';
        return $msg;
    }

    # Clamp a client-area size against the window node's min/max constraints.
    # (min/max live on the root window node so the layout has a single source of truth.)
    method _clamp_size ( $vtree, $cw, $ch ) {
        $cw = $vtree->min_w if $vtree->min_w && $cw < $vtree->min_w;
        $ch = $vtree->min_h if $vtree->min_h && $ch < $vtree->min_h;
        $cw = $vtree->max_w if $vtree->max_w && $cw > $vtree->max_w;
        $ch = $vtree->max_h if $vtree->max_h && $ch > $vtree->max_h;
        return ( $cw, $ch );
    }

    method _relayout_now ( $arg1 = undef, $arg2 = undef, $arg3 = undef ) {
        return unless $vtrees && $driver->can('_is_mounted') && $driver->_is_mounted();

        # Backward compatibility with older drivers that just send ($cw, $ch)
        my ( $window_id, $cw, $ch );
        if ( defined $arg3 ) {
            ( $window_id, $cw, $ch ) = ( $arg1, $arg2, $arg3 );
        }
        elsif ( defined $arg1 && defined $arg2 ) {
            ( $cw, $ch ) = ( $arg1, $arg2 );
            $window_id = $vtrees->[0]->id;
        }
        my $vtree = $window_id ? ( grep { $_->id eq $window_id } @$vtrees )[0] : $vtrees->[0];
        return unless $vtree;

        # Use the client size passed by WM_SIZE's lParam; fall back to a fresh measure if it was
        # not supplied. Runs inside the wndproc, so no fiber switch allows live updates during the
        # drag loop.
        if ( defined $cw && defined $ch ) {
            ( $cw, $ch ) = $self->_clamp_size( $vtree, $cw, $ch );
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
        return if $node->type eq 'scroll_view';    # content lives in the viewport; move_widget places it
        $self->_move_all( $_, $driver ) for @{ $node->children };
    }

    method _boot () {
        ( $model, my $cmd ) = $init->();
        $dark_mode = $driver->uses_dark_mode() if $driver->can('uses_dark_mode');
        $self->_mount;
        $self->_sync_subscriptions;
    }

    # Mount the window, lay out the initial vtree, and create the child widgets.
    method _mount () {
        my $res = $view->($model);
        $vtrees = ref $res eq 'ARRAY' ? $res : [$res];
        for my $vtree (@$vtrees) {

            # Mount window first so we can measure its real client area,
            # then compute layout against that, then create the child widgets.
            $driver->mount($vtree);
            $layout->compute($vtree);
            $driver->mount_children($vtree);

            # Second layout pass: scroll_view content is measured at natural size during mount,
            # so its children get placed only once the viewport window is on screen.
            $layout->compute($vtree);
            $self->_move_all( $vtree, $driver );
        }
    }

    # Ask the subscriptions callback for the set the current model requires, then diff it
    # against the running set by key. Removed keys are stopped; new keys are started;
    # surviving interval timers keep their phase (only the message closure is refreshed), so
    # a fast render loop can never starve a slow timer.
    method _sync_subscriptions () {
        my $now     = _now_ms();
        my $desired = $subscriptions ? $subscriptions->($model) : undef;
        $desired = []           unless defined $desired;
        $desired = [$desired]   if ref $desired eq 'HASH';
        my %want;
        my @order;
        for my $sub (@$desired) {
            next unless ref $sub eq 'HASH' && $sub->{kind};
            $sub = Uji::Sub::_normalize(%$sub) unless $sub->{key};
            next if $want{ $sub->{key} };    # identical subs collapse; the first wins
            $want{ $sub->{key} } = $sub;
            push @order, $sub->{key};
        }
        delete $active_subs->{$_} for grep { !$want{$_} } keys %$active_subs;
        for my $key (@order) {
            my $sub = $want{$key};
            if ( my $live = $active_subs->{$key} ) {
                $live->{msg} = $sub->{msg};
            }
            else {
                $sub->{next} = $now + $sub->{ms} if $sub->{kind} eq 'interval';
                $active_subs->{$key} = $sub;
            }
        }
        return;
    }

    # Fire every interval subscription whose due time has passed. Called once per poll tick
    # with an optional explicit clock (tests pass a synthetic time).
    method _tick_subscriptions ( $now = undef ) {
        $now //= _now_ms();
        for my $sub ( values %$active_subs ) {
            next unless $sub->{kind} eq 'interval';
            my $guard = 0;
            while ( ( $sub->{next} // 0 ) <= $now ) {
                my $msg = _resolve_msg( $sub, $now );
                $channel->put($msg) if defined $msg;
                $sub->{next} += $sub->{ms};
                last if ++$guard >= 1000;    # a zero/negative period cannot spin forever
            }
        }
        return;
    }

    # Resolve the messages of every event subscription of one kind ('resize', 'focus', 'blur',
    # 'close_request', 'key_chord'). An optional platform event hashref filters subs carrying a
    # matcher: focus/blur subs granting an C<id> only fire when it matches the event's node id,
    # and key_chord subs only fire when their canonical chord matches the event's.
    method _event_sub_messages ( $kind, $event = undef ) {
        my $now = _now_ms();
        my @out;
        for my $sub ( values %$active_subs ) {
            next unless $sub->{kind} eq $kind;
            if ( defined $event && $kind eq 'focus' ) {
                next if defined $sub->{id} && $sub->{id} ne $event->{focus_id};
            }
            elsif ( defined $event && $kind eq 'blur' ) {
                next if defined $sub->{id} && $sub->{id} ne $event->{blur_id};
            }
            elsif ( defined $event && $kind eq 'key_chord' ) {
                next if $sub->{chord} && $sub->{chord} ne $event->{chord};
            }
            my $msg = _resolve_msg( $sub, $now );
            push @out, $msg if defined $msg;
        }
        return @out;
    }

    # One synchronous pass of the event loop, for use inside a platform modal loop (dragging the
    # window frame, a dialog pump). The poll/render fibers are suspended there, so tick the timers
    # and fold + render any resulting message inline; otherwise the UI freezes until the modal
    # loop exits and then "snaps" to the new state.
    method _pump_modal () {
        $self->_tick_subscriptions;
        $self->_drain_and_render( $channel->get ) if $channel->size;
        return;
    }

    # Rebuild the view from the current model and reconcile the diff into the driver.
    method _render () {
        my $res        = $view->($model);
        my $new_vtrees = ref $res eq 'ARRAY' ? $res : [$res];

        # view() rebuilds the window node from scratch, so its auto-generated id isn't in the
        # driver's surface map yet (patch_windows below transfers the OLD id onto it, too late
        # for sync_window_bounds). Adopt the old window's client bounds so compute() lays out
        # against the real size instead of Layout's 800x600 default -- which made every child
        # ~2.5x too wide and pushed the flex row past the right edge.
        for my $i ( 0 .. $#$new_vtrees ) {
            my $new_vtree = $new_vtrees->[$i];
            my $i_old     = $i < @$vtrees ? $i : 0;
            my $old_vtree = $vtrees->[$i_old];
            $new_vtree->set_bounds( 0, 0, $old_vtree->bw, $old_vtree->bh ) if $old_vtree;
            $driver->sync_window_bounds($new_vtree);    # fresh measure when the id resolves
            $layout->compute($new_vtree);
            $self->_move_all( $new_vtree, $driver );
        }
        $reconciler->patch_windows( $vtrees, $new_vtrees, $driver );

        # patch_windows can RESIZE a window live: a min/max constraint applied at runtime pushes the
        # frame to the clamped size synchronously (set_prop -> _set_window_outer -> WM_SIZE). The
        # pre-patch compute above had to adopt the OLD bounds because the fresh id was not yet in the
        # driver's surface map (sync_window_bounds was a no-op), so every slot was laid out at the
        # pre-resize size -- and the child diff then moved the real controls to those stale slots. Now
        # that ids are transferred, re-measure each window and re-flow the whole tree when the REAL
        # client box differs from what we computed. A normal render (no size change) skips this pass.
        for my $new_vtree (@$new_vtrees) {
            my $before_w = $new_vtree->bw;
            my $before_h = $new_vtree->bh;
            $driver->sync_window_bounds($new_vtree);
            if ( $new_vtree->bw != $before_w || $new_vtree->bh != $before_h ) {
                $layout->compute($new_vtree);
                $self->_move_all( $new_vtree, $driver );
            }
        }
        $vtrees = $new_vtrees;
    }

    # First message already read off the channel; drain any stragglers, fold every message
    # through update(), then re-render. (Extracted so tests can drive a render synchronously.)
    method _drain_and_render ($first_msg) {
        exit(0) if ref $first_msg eq 'HASH' && $first_msg->{type} eq 'QUIT';
        my @batch = ($first_msg);
        push @batch, $channel->get() while $channel->size;

        # WM_SIZE is reserved: the resize handler has already re-laid-out the tree, so the app
        # itself has no update() for it. The same applies to FOCUS/BLUR/KEY_CHORD: those are
        # translated into the matching subscriptions' messages directly (an app update() never sees
        # the raw platform event). CLOSE_REQUEST stays on the driver seam (see
        # _handle_close_request).
        my @work;
        for my $m (@batch) {
            exit(0) if ref $m eq 'HASH' && $m->{type} eq 'QUIT';
            if ( ref $m eq 'HASH' && $m->{type} eq 'RESIZE' ) {
                push @work, $self->_event_sub_messages('resize');
                next;
            }
            if ( ref $m eq 'HASH' && $m->{type} eq 'FOCUS' ) {
                push @work, $self->_event_sub_messages( 'focus', $m );
                next;
            }
            if ( ref $m eq 'HASH' && $m->{type} eq 'BLUR' ) {
                push @work, $self->_event_sub_messages( 'blur', $m );
                next;
            }
            if ( ref $m eq 'HASH' && $m->{type} eq 'KEY_CHORD' ) {
                push @work, $self->_event_sub_messages( 'key_chord', $m );
                next;
            }
            push @work, $m;
        }
        for my $m (@work) {
            exit(0) if ref $m eq 'HASH' && $m->{type} eq 'QUIT';
            ( my $new_model, my $new_cmd ) = $update->( $m, $model );
            $model = $new_model;
        }
        $self->_render;
        $self->_sync_subscriptions;
    }

    # A close gesture (title-bar X, Alt+F4, WM_CLOSE) asks the app whether it may close. Every
    # close_request subscription gets a synchronous pass through update(); a message handled with
    # an undef command is consent (the window closes), while ANY defined return value vetoes the
    # close and the window stays open. $surface_id is reserved for multi-window suites. Returns
    # a truthful veto flag for the driver's CW_CLOSE guard: 1 = may close, 0 = veto.
    method _handle_close_request ( $surface_id = undef ) {
        my @msgs = $self->_event_sub_messages('close_request');
        return 1 unless @msgs;
        my $veto = 0;
        for my $m (@msgs) {
            ( my $new_model, my $cmd ) = $update->( $m, $model );
            $model = $new_model;
            $veto = 1 if defined $cmd;
        }
        $self->_render;
        $self->_sync_subscriptions;
        return $veto ? 0 : 1;
    }

    # The platform colour scheme at boot: true when the driver reports dark mode (auto-detected
    # from the OS, or forced via the driver's dark_mode option). Snapshotted by _boot so a
    # mid-run OS theme toggle does not flip already-painted windows.
    method uses_dark_mode () {
        return $dark_mode // 0;
    }

    method run () {
        $driver->init($channel);
        $driver->set_resize_handler( sub { $self->_relayout_now(@_) } );
        $driver->set_close_request_handler( sub { $self->_handle_close_request($_[0]) } )
            if $driver->can('set_close_request_handler');
        $driver->set_modal_pump( sub { $self->_pump_modal } ) if $driver->can('set_modal_pump');
        async {
            $self->_boot;
            fiber {
                while (1) {
                    $driver->poll_events();
                    $self->_tick_subscriptions;
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
