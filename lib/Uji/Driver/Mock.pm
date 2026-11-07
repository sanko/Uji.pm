use v5.40;
use experimental 'class';

class Uji::Driver::Mock {
    field $channel   : writer(init);
    field $resize    : reader : writer(set_resize_handler);
    field $close_req : writer(set_close_request_handler);
    field $dark      : param  = 0;
    field $registry  : reader = {};
    field $calls     : reader = [];
    field $checks    : reader = {};
    field $mounted   : reader = 0;
    field $mounts    : reader = {};
    field $unmounts  : reader = {};
    field $vtree;
    field $dialog    : writer(retain_dialog) = {};
    field $sim_size  : reader                = {};
    field $win_nodes : reader                = {};
    method poll_events    {1}
    method uses_dark_mode { $dark ? 1 : 0 }

    method mount ($t) {
        $mounted               = 1;
        $vtree                 = $t;
        $sim_size->{ $t->id }  = { cw => 360, ch => 400 };
        $win_nodes->{ $t->id } = $t;
        $t->set_bounds( 0, 0, 360, 400 );
        $mounts->{ $t->id } = 1;
        return 1;
    }

    method unmount ($t) {
        $unmounts->{ $t->id } = 1;
        delete $mounts->{ $t->id };
        delete $sim_size->{ $t->id };
        delete $win_nodes->{ $t->id };
        return 1;
    }

    method mount_children ($t) {
        $self->_register($t);
        return 1;
    }
    method _is_mounted { $mounted ? 1 : 0 }

    method sync_window_bounds ($t) {
        return 1 unless $mounts->{ $t->id };
        my $s = $sim_size->{ $t->id } || { cw => 360, ch => 400 };
        $t->set_bounds( 0, 0, $s->{cw}, $s->{ch} );
        return 1;
    }

    method measure_text ($text) {
        return ( length( $text // '' ) * 8, 16 );
    }

    method update_registry ($node) {
        $registry->{ $node->id }{node} = $node if exists $registry->{ $node->id };
        $win_nodes->{ $node->id }      = $node if $node->type eq 'window';
        return 1;
    }

    method _clamp_v ( $v, $min, $max ) {
        $v = $min if $min && $v < $min;
        $v = $max if $max && $v > $max;
        return $v;
    }

    method set_prop ( $vnode_id, $prop, $value ) {
        push @{$calls}, [ 'set_prop', $vnode_id, $prop, $value ];
        my $r = $registry->{$vnode_id} or return 1;
        if ( $prop eq 'checked' ) {
            $checks->{$vnode_id} = $value ? 1 : 0;
        }
        elsif ( $prop =~ /^(min|max)_[wh]$/ ) {
            my $w  = $win_nodes->{$vnode_id} or return 1;
            my $s  = $sim_size->{$vnode_id}  or return 1;
            my $cw = $self->_clamp_v( $s->{cw}, $w->min_w, $w->max_w );
            my $ch = $self->_clamp_v( $s->{ch}, $w->min_h, $w->max_h );
            return 1 if $cw == $s->{cw} && $ch == $s->{ch};
            $s->{cw} = $cw;
            $s->{ch} = $ch;
            my $rb = $self->resize;
            $rb->( $vnode_id, $cw, $ch ) if $rb;
        }
        elsif ( $prop eq 'value' && $r->{node}->type eq 'radio_group' ) {
            my $selected = $value;
            for my $ch ( @{ $r->{node}->children } ) {
                $checks->{ $ch->id } = ( $ch->id eq $selected ) ? 1 : 0;
            }
        }
        else {
            $checks->{$vnode_id} = $value;
        }
        return 1;
    }

    method move_widget ( $vnode_id, $x, $y, $w, $h ) {
        push @{$calls}, [ 'move_widget', $vnode_id, $x, $y, $w, $h ];
        return 1;
    }

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
        return 1;
    }

    method mount_subtree ( $vnode, $ctx = undef, $parent_hwnd = undef, $store = undef ) {
        $self->_register($vnode);
        return 1;
    }

    method unmount_subtree ($node) {
        delete $registry->{ $node->id };
        delete $checks->{ $node->id };
        $self->unmount_subtree($_) for @{ $node->children };
        return 1;
    }

    method _get_registry_record ($id) {
        return $registry->{$id};
    }

    method _register ($node) {
        $registry->{ $node->id } = { hwnd => $node->id, node => $node };
        if ( $node->type eq 'checkbox' || $node->type eq 'toggle_switch' || $node->type eq 'toggle_button' ) {
            $checks->{ $node->id } = $node->checked ? 1 : 0;
        }
        elsif ( $node->type eq 'radio' ) {
            $checks->{ $node->id } = $node->selected ? 1 : 0;
        }
        $self->_register($_) for @{ $node->children };
    }
    method message_box      (%o) { $dialog->{message} // 'ok' }
    method file_open_dialog (%o) { $dialog->{open}    // undef }
    method file_save_dialog (%o) { $dialog->{save}    // undef }
    method color_picker     (%o) { $dialog->{color}   // undef }
    method prompt_dialog    (%o) { defined $dialog->{prompt} ? $dialog->{prompt} : $o{default} }
}
1;
