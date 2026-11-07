use v5.40;
use experimental 'class';
class Uji::Reconciler v0.0.1 {    # VDOM diffing and patching engine

    method patch_windows ( $old_vtrees, $new_vtrees, $driver ) {
        my @old = @$old_vtrees;
        my @paired;
        for my $new_vtree (@$new_vtrees) {
            my $old_idx;
            for my $i ( 0 .. $#old ) {
                next if $paired[$i];
                if ( $old[$i]->id eq $new_vtree->id ) {
                    $old_idx = $i;
                    last;
                }
            }
            unless ( defined $old_idx ) {
                for my $i ( 0 .. $#old ) {
                    next if $paired[$i];
                    $old_idx = $i;
                    last;
                }
            }
            if ( defined $old_idx ) {
                $paired[$old_idx] = 1;
                $self->patch( $old[$old_idx], $new_vtree, $driver, $new_vtree );
            }
            else {
                $driver->mount($new_vtree);
                $driver->mount_children($new_vtree);
            }
        }
        for my $i ( 0 .. $#old ) {
            next                         if $paired[$i];
            $driver->unmount( $old[$i] ) if $driver->can('unmount');
        }
    }

    method patch ( $old_node, $new_node, $driver, $ctx = undef ) {
        return unless $old_node && $new_node;
        $new_node->set_id( $old_node->id );
        $driver->update_registry($new_node);

        # Composed Calendar grid check: remount subtree if month/value/bounds changed
        if ( $old_node->type eq 'calendar' && $new_node->type eq 'calendar' && $self->_calendar_key($old_node) ne $self->_calendar_key($new_node) ) {
            $driver->unmount_subtree($_) for @{ $old_node->children };
            for my $row ( @{ $new_node->children } ) {
                $driver->mount_subtree( $row, $ctx ) if $driver->can('mount_subtree');
            }
            return;
        }

        # Mount-only props recreation check
        if ( $old_node->can('_mount_only_props') ) {
            for my $prop ( @{ $old_node->_mount_only_props } ) {
                if ( ( $old_node->$prop // '' ) ne ( $new_node->$prop // '' ) ) {
                    $driver->recreate_node( $old_node->id, $new_node );
                    last;
                }
            }
        }
        if ( $old_node->can('title') && $new_node->can('title') ) {
            if ( $old_node->title ne $new_node->title ) {
                $driver->set_prop( $new_node->id, 'title', $new_node->title );
            }
        }
        if ( $old_node->can('label') && $new_node->can('label') ) {
            if ( $old_node->label ne $new_node->label ) {
                $driver->set_prop( $new_node->id, 'label', $new_node->label );
            }
        }
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type ne 'radio_group' ) {
            if ( $self->_value_key( $old_node->value ) ne $self->_value_key( $new_node->value ) ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }
        if ( ( $new_node->type eq 'combo_box' || $new_node->type eq 'list_box' ) && $self->_opts_key($old_node) ne $self->_opts_key($new_node) ) {
            $driver->set_prop( $new_node->id, 'options', $new_node->options );
        }
        if ( $new_node->type eq 'tree_view' ) {
            if ( $self->_tree_key($old_node) ne $self->_tree_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'nodes', $new_node->nodes );
            }
            elsif (
                join( "\0", map { '' . ( $_ // '' ) } @{ $old_node->expanded // [] } ) ne
                join( "\0", map { '' . ( $_ // '' ) } @{ $new_node->expanded // [] } ) ) {
                $driver->set_prop( $new_node->id, 'expanded', $new_node->expanded );
            }
        }
        if ( $new_node->type eq 'list_view' ) {
            if ( $self->_columns_key($old_node) ne $self->_columns_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'columns', $new_node->columns );
            }
            elsif ( $self->_rows_key($old_node) ne $self->_rows_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'rows', $new_node->rows );
            }
        }
        if ( $old_node->can('panels') && $new_node->can('panels') && join( "\0", @{ $old_node->panels } ) ne join( "\0", @{ $new_node->panels } ) ) {
            $driver->set_prop( $new_node->id, 'panels', $new_node->panels );
        }
        if ( $new_node->type eq 'toolbar' ) {
            if ( $self->_buttons_key($old_node) ne $self->_buttons_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'buttons', $new_node->buttons );
            }
        }
        if ( $old_node->can('menu_bar') && $new_node->can('menu_bar') ) {
            if ( $self->_menu_key( $old_node->menu_bar ) ne $self->_menu_key( $new_node->menu_bar ) ) {
                $driver->set_prop( $new_node->id, 'menu_bar', $new_node->menu_bar );
            }
        }
        for my $p (qw[ scroll_x scroll_y ]) {
            if ( $old_node->can($p) && ( $old_node->$p // 0 ) != ( $new_node->$p // 0 ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }
        if ( $new_node->type eq 'split_view' ) {
            if ( ( $old_node->orientation // '' ) ne ( $new_node->orientation // '' ) ) {
                $driver->set_prop( $new_node->id, 'orientation', $new_node->orientation );
            }
            if ( ( $old_node->divider // '' ) ne ( $new_node->divider // '' ) ) {
                $driver->set_prop( $new_node->id, 'divider', $new_node->divider );
            }
        }
        if ( $old_node->can('min') && $old_node->can('max') ) {
            if ( $old_node->min ne $new_node->min ) {
                $driver->set_prop( $new_node->id, 'min', $new_node->min );
            }
            if ( $old_node->max ne $new_node->max ) {
                $driver->set_prop( $new_node->id, 'max', $new_node->max );
            }
        }
        if ( $old_node->can('step') && $old_node->step ne $new_node->step ) {
            $driver->set_prop( $new_node->id, 'step', $new_node->step );
        }
        if ( $old_node->can('enabled') && ( $old_node->enabled // 0 ) != ( $new_node->enabled // 0 ) ) {
            $driver->set_prop( $new_node->id, 'enabled', $new_node->enabled );
        }
        if ( $new_node->type eq 'spinner' ) {
            for my $p (qw[ running speed size color ]) {
                if ( ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                    $driver->set_prop( $new_node->id, $p, $new_node->$p );
                }
            }
        }
        if ( $new_node->type eq 'image' ) {
            for my $p (qw[ src object_fit ]) {
                if ( ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                    $driver->set_prop( $new_node->id, $p, $new_node->$p );
                }
            }
        }
        if ( $new_node->type eq 'canvas' ) {
            if ( ( $old_node->on_draw // '' ) ne ( $new_node->on_draw // '' ) ) {
                $driver->set_prop( $new_node->id, 'on_draw', $new_node->on_draw );
            }
            if ( ( $old_node->redraw // 0 ) != ( $new_node->redraw // 0 ) ) {
                $driver->set_prop( $new_node->id, 'redraw', $new_node->redraw );
            }
        }
        if ( $new_node->type eq 'color_button' ) {
            for my $p (qw[ color show_hex ]) {
                if ( ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                    $driver->set_prop( $new_node->id, $p, $new_node->$p );
                }
            }
        }
        if ( $old_node->can('visible') && ( $old_node->visible // 0 ) != ( $new_node->visible // 0 ) ) {
            $driver->set_prop( $new_node->id, 'visible', $new_node->visible );
        }
        if ( $old_node->can('focused') && ( $old_node->focused // 0 ) != ( $new_node->focused // 0 ) ) {
            $driver->set_prop( $new_node->id, 'focused', $new_node->focused );
        }
        if ( $old_node->can('tooltip') && ( $old_node->tooltip // '' ) ne ( $new_node->tooltip // '' ) ) {
            $driver->set_prop( $new_node->id, 'tooltip', $new_node->tooltip );
        }
        if ( $old_node->can('checked') && ( $old_node->checked // 0 ) != ( $new_node->checked // 0 ) ) {
            $driver->set_prop( $new_node->id, 'checked', $new_node->checked );
        }
        if ( $old_node->can('readonly') && ( $old_node->readonly // 0 ) != ( $new_node->readonly // 0 ) ) {
            $driver->set_prop( $new_node->id, 'readonly', $new_node->readonly );
        }
        if ( $old_node->can('maxlength') && $old_node->maxlength ne $new_node->maxlength ) {
            $driver->set_prop( $new_node->id, 'maxlength', $new_node->maxlength );
        }
        if ( $old_node->can('placeholder') && ( $old_node->placeholder // '' ) ne ( $new_node->placeholder // '' ) ) {
            $driver->set_prop( $new_node->id, 'placeholder', $new_node->placeholder );
        }
        if ( $old_node->can('password_char') && ( $old_node->password_char // '' ) ne ( $new_node->password_char // '' ) ) {
            $driver->set_prop( $new_node->id, 'password_char', $new_node->password_char );
        }
        for my $p (qw[ color background ]) {
            if ( $old_node->can($p) && ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }
        for my $p (qw[ font font_size ]) {
            if ( $old_node->can($p) && ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }
        if ( $old_node->can('topmost') && ( $old_node->topmost // 0 ) != ( $new_node->topmost // 0 ) ) {
            $driver->set_prop( $new_node->id, 'topmost', $new_node->topmost );
        }
        for my $p (qw[ minimized maximized ]) {
            if ( $old_node->can($p) && ( $old_node->$p // 0 ) != ( $new_node->$p // 0 ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }
        for my $p (qw[ min_w min_h max_w max_h ]) {
            if ( $old_node->type eq 'window' && $old_node->$p ne $new_node->$p ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }
        if ( $old_node->type ne 'window' ) {
            if ( $old_node->bx != $new_node->bx ||
                $old_node->by != $new_node->by ||
                $old_node->bw != $new_node->bw ||
                $old_node->bh != $new_node->bh ) {
                $driver->move_widget( $new_node->id, $new_node->bx, $new_node->by, $new_node->bw, $new_node->bh );
            }
        }
        my $old_children = $old_node->children;
        my $new_children = $new_node->children;
        my $max          = @$old_children > @$new_children ? @$old_children : @$new_children;
        my $child_ctx
            = ( $new_node->type eq 'window' || $new_node->type eq 'scroll_view' || $new_node->type eq 'group_box' || $new_node->type eq 'tab_panel' )
            ? $new_node :
            $ctx;
        for my $i ( 0 .. $max - 1 ) {
            my $old_child = $old_children->[$i];
            my $new_child = $new_children->[$i];
            if ( $old_child && $new_child ) {
                $self->patch( $old_child, $new_child, $driver, $child_ctx );
            }
            elsif ($new_child) {
                my ( $parent_hwnd, $store );
                for my $cand ( @$new_children, @$old_children ) {
                    my $r = $driver->_get_registry_record( $cand->id );
                    if ( $r && $r->{parent_hwnd} ) {
                        $parent_hwnd = $r->{parent_hwnd};
                        $store       = $r->{scroll};
                        last;
                    }
                }
                $driver->mount_subtree( $new_child, $child_ctx, $parent_hwnd, $store );
            }
            elsif ($old_child) {
                $driver->unmount_subtree($old_child) if $driver->can('unmount_subtree');
            }
        }
        if ( $new_node->type eq 'overlay' && $driver->can('_apply_overlay') ) {
            $driver->_apply_overlay($new_node);
        }
        if ( $new_node->type eq 'scroll_view' && $driver->can('_place_scrollbars') ) {
            $driver->_place_scrollbars( $new_node->id );
            $driver->_apply_scroll( $new_node->id ) if $driver->can('_apply_scroll');
        }
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type eq 'radio_group' ) {
            if ( $old_node->value ne $new_node->value ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }
        if ( $new_node->type eq 'tab_panel' && $new_node->can('index') ) {
            if ( ( $old_node->index // 0 ) != ( $new_node->index // 0 ) ) {
                $driver->set_prop( $new_node->id, 'index', $new_node->index );
            }
            my $okey = join "\0", map { ref $_ eq 'HASH' ? ( $_->{title} // $_->{label} // '' ) : ( $_->[0] // '' ) } @{ $old_node->panels };
            my $nkey = join "\0", map { ref $_ eq 'HASH' ? ( $_->{title} // $_->{label} // '' ) : ( $_->[0] // '' ) } @{ $new_node->panels };
            if ( $old_node->can('panels') && $okey ne $nkey ) {
                $driver->set_prop( $new_node->id, 'panels', $new_node->panels );
            }
        }
    }

    method _calendar_key ($node) {
        my $k = join "\0", ( $node->month // '' ), ( $node->value // '' ), ( $node->min // '' ), ( $node->max // '' );
        for my $row ( @{ $node->children } ) {
            $k .= "\0[";
            for my $cell ( @{ $row->children } ) {
                $k
                    .= "\0" .
                    $cell->type . '|' .
                    ( $cell->can('label') ? ( $cell->label // '' ) : '' ) . '|' .
                    ( $cell->enabled    // '' ) . '|' .
                    ( $cell->background // '' );
            }
        }
        return $k;
    }

    method _opts_key ($node) {
        return join "\0", map { ( $_->{value} // '' ) . '|' . ( $_->{label} // '' ) } @{ $node->options // [] };
    }

    method _tree_key ($node) {
        my $s = '';
        my $walk;
        $walk = sub {
            for my $it ( @{ $_[0] // [] } ) {
                $s .= '[' . ( $it->{value} // '' ) . '|' . ( $it->{label} // '' );
                $walk->( $it->{children} ) if $it->{children};
                $s .= ']';
            }
        };
        $walk->( $node->nodes );
        return $s;
    }

    method _columns_key ($node) {
        return join "\0",
            map { join( '|', ( $_->{label} // '' ), ( $_->{width} // '' ), ( $_->{sort} // '' ), ( $_->{format} // '' ), ( $_->{align} // '' ) ) }
            @{ $node->columns // [] };
    }

    method _rows_key ($node) {
        my $s = '';
        for my $r ( @{ $node->rows // [] } ) {
            my $cells = ref $r eq 'HASH' ? $r->{columns} : $r;
            $s .= ';r' . ( ref $r eq 'HASH' ? ( $r->{value} // '' ) : '' ) . '|' . join( ',', map { '' . ( $_ // '' ) } @{ $cells // [] } );
        }
        return $s;
    }

    method _value_key ($value) {
        return ref $value eq 'ARRAY' ? join "\0", map { '' . ( $_ // '' ) } @$value : '' . ( $value // '' );
    }

    method _buttons_key ($node) {
        return join "\0", map {
            ref $_ eq 'HASH' ?
                join( '|',
                ( $_->{label} // '' ),
                ( $_->{id}    // '' ),
                ( $_->{separator}       ? 's'                           : '' ),
                ( $_->{checked}         ? 'c'                           : '' ),
                ( defined $_->{enabled} ? ( $_->{enabled} ? 'e' : 'd' ) : '' ),
                ( $_->{width} // '' ),
                ( $_->{icon}  // '' ) ) :
                ''
        } @{ $node->buttons // [] };
    }

    method _menu_key ($mb) {
        my $s = '';
        my $walk;
        $walk = sub {
            for my $it ( @{ $_[0] // [] } ) {
                $s
                    .= '(' .
                    ( $it->{label} // '' ) . '|' .
                    ( $it->{id}    // '' ) .
                    ( $it->{separator}       ? '|s'                             : '' ) .
                    ( $it->{checked}         ? '|c'                             : '' ) .
                    ( defined $it->{enabled} ? ( $it->{enabled} ? '|e' : '|d' ) : '' );
                $walk->( $it->{children} ) if $it->{children};
                $s .= ')';
            }
        };
        $walk->( $mb && $mb->can('items') ? $mb->items : [] );
        return $s;
    }
};
1;
