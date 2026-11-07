use v5.40;
use experimental 'class';
class Uji::App v0.0.1 {    # The TEA Runtime (Parataxis fibers & message loop)
    use Acme::Parataxis          qw[async fiber await_sleep];
    use Acme::Parataxis::Channel qw[];
    use builtin                  qw[blessed];
    use Time::HiRes              ();
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::Layout;
    use Uji::Sub ();
    field $init          : param;
    field $update        : param;
    field $view          : param;
    field $subscriptions : param = undef;    # sub ($model) { ... }
    field $model         : reader;
    field $vtrees        : reader;
    field $active_subs   : reader = {};      # key => live subscription
    field $channel       : param //= Acme::Parataxis::Channel->new( capacity => 1024 );
    field $driver        : param //= Uji::Driver::detect();
    field $reconciler    : param //= Uji::Reconciler->new();
    field $layout        : param //= Uji::Layout->new( driver => $driver );
    field $dark_mode = undef;
    sub _now_ms () { return Time::HiRes::time() * 1000 }

    sub _resolve_msg ( $sub, $now ) {
        my $msg = $sub->{msg};
        $msg = $msg->($now) if ref $msg eq 'CODE';
        return $msg;
    }

    method _clamp_size ( $vtree, $cw, $ch ) {
        $cw = $vtree->min_w if $vtree->min_w && $cw < $vtree->min_w;
        $ch = $vtree->min_h if $vtree->min_h && $ch < $vtree->min_h;
        $cw = $vtree->max_w if $vtree->max_w && $cw > $vtree->max_w;
        $ch = $vtree->max_h if $vtree->max_h && $ch > $vtree->max_h;
        return ( $cw, $ch );
    }

    method _relayout_now ( $arg1 = undef, $arg2 = undef, $arg3 = undef ) {
        return unless $vtrees && $driver->can('_is_mounted') && $driver->_is_mounted();
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
        return if $node->type eq 'scroll_view';
        $self->_move_all( $_, $driver ) for @{ $node->children };
    }

    method _boot () {
        ( $model, my $cmd ) = $init->();
        $dark_mode = $driver->uses_dark_mode() if $driver->can('uses_dark_mode');
        $self->_mount;
        $self->_sync_subscriptions;
        $self->_run_cmd($cmd) if $cmd;
    }

    method _mount () {
        my $res = $view->($model);
        $vtrees = ref $res eq 'ARRAY' ? $res : [$res];
        for my $vtree (@$vtrees) {
            $driver->mount($vtree);
            $layout->compute($vtree);
            $driver->mount_children($vtree);
            $layout->compute($vtree);
            $self->_move_all( $vtree, $driver );
        }
    }

    method _sync_subscriptions () {
        my $now     = _now_ms();
        my $desired = $subscriptions ? $subscriptions->($model) : undef;
        $desired = [] unless defined $desired;
        $desired = [$desired] if ref $desired eq 'HASH';
        my ( %want, @order );
        for my $sub (@$desired) {
            next                               unless ref $sub eq 'HASH' && $sub->{kind};
            $sub = Uji::Sub::_normalize(%$sub) unless $sub->{key};
            next if $want{ $sub->{key} };
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
    }

    method _tick_subscriptions ( $now = undef ) {
        $now //= _now_ms();
        for my $sub ( values %$active_subs ) {
            next unless $sub->{kind} eq 'interval';
            my $guard = 0;
            while ( ( $sub->{next} // 0 ) <= $now ) {
                my $msg = _resolve_msg( $sub, $now );
                $channel->put($msg) if defined $msg;
                $sub->{next} += $sub->{ms};
                last if ++$guard >= 1000;
            }
        }
    }

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

    method _pump_modal () {
        $self->_tick_subscriptions;
        $self->_drain_and_render( $channel->get ) if $channel->size;
    }

    method _render () {
        my $res        = $view->($model);
        my $new_vtrees = ref $res eq 'ARRAY' ? $res : [$res];
        for my $i ( 0 .. $#$new_vtrees ) {
            my $new_vtree = $new_vtrees->[$i];
            my $i_old     = $i < @$vtrees ? $i : 0;
            my $old_vtree = $vtrees->[$i_old];
            $new_vtree->set_bounds( 0, 0, $old_vtree->bw, $old_vtree->bh ) if $old_vtree;
            $driver->sync_window_bounds($new_vtree);
            $layout->compute($new_vtree);
            $self->_move_all( $new_vtree, $driver );
        }
        $reconciler->patch_windows( $vtrees, $new_vtrees, $driver );
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

    method _drain_and_render ($first_msg) {
        exit(0) if ref $first_msg eq 'HASH' && $first_msg->{type} eq 'QUIT';
        my @batch = ($first_msg);
        push @batch, $channel->get() while $channel->size;
        my ( @work, @cmds );
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
            push @cmds, $new_cmd if $new_cmd;
        }
        $self->_render;
        $self->_sync_subscriptions;
        $self->_run_cmd($_) for @cmds;
    }

    method _handle_close_request ( $surface_id = undef ) {
        my @msgs = $self->_event_sub_messages('close_request');
        return 1 unless @msgs;
        my ( $veto, @cmds );
        for my $m (@msgs) {
            ( my $new_model, my $cmd ) = $update->( $m, $model );
            $model = $new_model;
            $veto  = 1 if defined $cmd;
            push @cmds, $cmd if $cmd;
        }
        $self->_render;
        $self->_sync_subscriptions;
        $self->_run_cmd($_) for @cmds;
        return $veto ? 0 : 1;
    }

    method uses_dark_mode () {
        return $dark_mode // 0;
    }

    method _run_cmd ($cmd) {
        return unless $cmd;
        if ( ref $cmd eq 'ARRAY' ) {
            $self->_run_cmd($_) for @$cmd;
            return;
        }
        if ( blessed($cmd) && $cmd->can('run') ) {
            fiber {
                $cmd->run( $channel, $driver );
            };
        }
    }

    method run () {
        $driver->init($channel);
        $driver->set_resize_handler( sub { $self->_relayout_now(@_) } );
        $driver->set_close_request_handler( sub { $self->_handle_close_request( $_[0] ) } ) if $driver->can('set_close_request_handler');
        $driver->set_modal_pump( sub { $self->_pump_modal } )                               if $driver->can('set_modal_pump');
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
