use v5.40;
use experimental 'class';

class MockDriver {

    # Headless stand-in for Uji::Driver::Win32. Records every set_prop/move_widget call and keeps a
    # small "native control state" so we can emulate BM_GETCHECK / BM_SETCHECK round-trips.
    field $channel  : writer(init);
    field $resize   : writer(set_resize_handler);
    field $close_req : writer(set_close_request_handler);
    field $dark      : param = 0;    # simulated colour scheme (0 = light, 1 = dark)
    field $registry : reader = {};    # id => { hwnd => id, node => $node }
    field $calls    : reader = [];    # [ $method, @args ]
    field $checks   : reader = {};    # id => checked state (0/1)
    field $mounted  : reader = 0;
    field $mounts   : reader = {};
    field $unmounts : reader = {};
    field $vtree;
    field $dialog : writer(retain_dialog) = {};    # { message => result, open => path, save => path, color => hex, prompt => text }

    #
    method poll_events {1}
    method uses_dark_mode { $dark ? 1 : 0 }
    method mount   ($t) { $mounted = 1; $vtree = $t; $t->set_bounds( 0, 0, 360, 400 ); $mounts->{ $t->id } = 1; 1 }
    method unmount ($t) { $unmounts->{ $t->id } = 1; delete $mounts->{ $t->id }; 1 }
    method mount_children ($t) { $self->_register($t); 1 }
    method _is_mounted { $mounted ? 1 : 0 }

    method sync_window_bounds ($t) {
        return 1 unless $mounts->{ $t->id };    # real driver: no surface record for a fresh id
        $t->set_bounds( 0, 0, 360, 400 );
        1;
    }
    method measure_text ($text) { return ( length( $text // '' ) * 8, 16 ) }

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

    # Mirror the Win32 recreate_node: destroy the native control and remount the same id with a
    # fresh node. In the mock, "destroy" just re-points the registry record and re-applies the
    # mount-time checks as if the control were brand new.
    method recreate_node ( $old_id, $new_node ) {
        push @$calls, [ 'recreate_node', $old_id, $new_node->id ];
        $new_node->set_id($old_id);
        my $rec = $registry->{$old_id} or return 1;
        $rec->{node} = $new_node;
        delete $checks->{$old_id};
        if ( $new_node->type eq 'checkbox' || $new_node->type eq 'toggle_switch' || $new_node->type eq 'toggle_button' ) {
            $checks->{$old_id} = $new_node->checked ? 1 : 0;
        }
        elsif ( $new_node->type eq 'radio' ) {
            $checks->{$old_id} = $new_node->selected ? 1 : 0;
        }
        1;
    }

    method _register ($node) {
        $registry->{ $node->id } = { hwnd => $node->id, node => $node };

        # Mirror the real driver's initial BM_SETCHECK/BM_SETPOS at mount time.
        if ( $node->type eq 'checkbox' || $node->type eq 'toggle_switch' || $node->type eq 'toggle_button' ) {
            $checks->{ $node->id } = $node->checked ? 1 : 0;
        }
        elsif ( $node->type eq 'radio' ) { $checks->{ $node->id } = $node->selected ? 1 : 0 }
        $self->_register($_) for @{ $node->children };
    }

    # Dialog stubs for App/Mock parity: canned results are injected via set-dialog mocks.
    method message_box      (%o) { $dialog->{message} // 'ok' }
    method file_open_dialog (%o) { $dialog->{open}    // undef }
    method file_save_dialog (%o) { $dialog->{save}    // undef }
    method color_picker     (%o) { $dialog->{color}   // undef }
    method prompt_dialog    (%o) { defined $dialog->{prompt} ? $dialog->{prompt} : $o{default} }
}
1;
