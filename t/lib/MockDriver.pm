use v5.40;
use experimental 'class';

class MockDriver {

    # Headless stand-in for Uji::Driver::Win32. Records every set_prop/move_widget call and keeps a
    # small "native control state" so we can emulate BM_GETCHECK / BM_SETCHECK round-trips.
    field $channel  : writer(init);
    field $resize   : writer(set_resize_handler);
    field $registry : reader = {};    # id => { hwnd => id, node => $node }
    field $calls    : reader = [];    # [ $method, @args ]
    field $checks   : reader = {};    # id => checked state (0/1)
    field $mounted  : reader = 0;
    field $vtree;
    #
    method poll_events {1}
    method mount ($t) { $mounted = 1; $vtree = $t; $t->set_bounds( 0, 0, 360, 400 ); 1 }
    method mount_children ($t) { $self->_register($t); 1 }
    method _is_mounted { $mounted ? 1 : 0 }
    method sync_window_bounds ($t)    { $t->set_bounds( 0, 0, 360, 400 ); 1 }
    method measure_text       ($text) { return ( length( $text // '' ) * 8, 16 ) }

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };
        1;
    }

    method set_prop ( $vnode_id, $prop, $value ) {
        push @{$calls}, [ 'set_prop', $vnode_id, $prop, $value ];
        my $r = $registry->{$vnode_id} or return 1;
        if ( $prop eq 'checked' ) {
            $checks->{$vnode_id} = $value ? 1 : 0;
        }
        elsif ( $prop eq 'value' && $r->{node}->type eq 'radio_group' ) {

            # Mirror the Win32 branch: find the child whose value matches, BM_SETCHECK each child.
            my $selected = '';
            for my $ch ( @{ $r->{node}->children } ) {
                $selected = $ch->id if $ch->value eq $value;
            }
            for my $ch ( @{ $r->{node}->children } ) {
                my $cr = $registry->{ $ch->id } or next;
                $checks->{ $ch->id } = ( $ch->id eq $selected ) ? 1 : 0;
            }
        }
        else {
            $checks->{$vnode_id} = $value;
        }
        1;
    }

    method move_widget (@args) {
        push @$calls, [ 'move_widget', @args ];
        return 1;
    }

    method _register ($node) {
        $registry->{ $node->id } = { hwnd => $node->id, node => $node };

        # Mirror the real driver's initial BM_SETCHECK/BM_SETPOS at mount time.
        if    ( $node->type eq 'checkbox' ) { $checks->{ $node->id } = $node->checked  ? 1 : 0 }
        elsif ( $node->type eq 'radio' )    { $checks->{ $node->id } = $node->selected ? 1 : 0 }
        $self->_register($_) for @{ $node->children };
    }
}
1;
