use v5.40;
use experimental 'class';
class Uji::Reconciler v0.0.1 {    # VDOM diffing and patching engine

    # Options are rebuilt as fresh arrayrefs on every render, so compare their contents rather
    # than their identity. Used for combo/list boxes, whose option lists are native state.
    method _options_changed ( $old, $new ) {
        return 1 unless @$old == @$new;
        for my $i ( 0 .. $#$old ) {
            my $a = $old->[$i];
            my $b = $new->[$i];
            return 1 if ( $a->{value} // '' ) ne ( $b->{value} // '' );
            return 1 if ( $a->{label} // $a->{value} // '' ) ne ( $b->{label} // $b->{value} // '' );
        }
        return 0;
    }

    method _destroy_subtree ( $node, $driver ) {
        return unless $node;
        $self->_destroy_subtree( $_, $driver ) for @{ $node->children };
        $driver->destroy_widget( $node->id );
    }

    method patch ( $old_node, $new_node, $driver ) {
        return unless $old_node && $new_node;

        # If types differ or keys differ, replace the subtree
        if ( $old_node->type ne $new_node->type || ( defined $old_node->key && defined $new_node->key && $old_node->key ne $new_node->key ) ) {
            $self->_destroy_subtree( $old_node, $driver );
            $driver->mount_widget($new_node);
            return;
        }
        #
        $new_node->set_id( $old_node->id );
        $driver->update_registry($new_node);

        # Check options before value/selection: repopulating a combo/list resets the native
        # selection, so the value diff that follows re-applies the model's choice.
        if ( $new_node->type eq 'combo_box' || $new_node->type eq 'list_box' ) {
            if ( $self->_options_changed( $old_node->options, $new_node->options ) ) {
                $driver->set_prop( $new_node->id, 'options', $new_node->options );
            }
        }

        # Check title (Window)
        if ( $old_node->can('title') && $new_node->can('title') ) {
            if ( $old_node->title // '' ne $new_node->title // '' ) {
                $driver->set_prop( $new_node->id, 'title', $new_node->title );
            }
        }

        # Check label (Text/Buttons/Checkbox/Radio/ToggleSwitch)
        if ( $old_node->can('label') && $new_node->can('label') ) {
            if ( $old_node->label // '' ne $new_node->label // '' ) {
                $driver->set_prop( $new_node->id, 'label', $new_node->label );
            }
        }

        # Check value (TextInput/Password/MulilineText/Slider/DatePicker/Spinbox)
        # radio_group is handled after the child loop so its radio children have stable, transferred IDs.
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type ne 'radio_group' ) {
            if ( $old_node->value // '' ne $new_node->value // '' ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }

        # Check selection (ListBox)
        if ( $old_node->can('selection') && $new_node->can('selection') ) {
            if ( $old_node->selection // '' ne $new_node->selection // '' ) {
                $driver->set_prop( $new_node->id, 'selection', $new_node->selection );
            }
        }

        # Check range (Slider/Spinbox)
        if ( $old_node->can('min') && $new_node->can('min') ) {
            if ( $old_node->min // '' ne $new_node->min // '' ) {
                $driver->set_prop( $new_node->id, 'min', $new_node->min );
            }
        }
        if ( $old_node->can('max') && $new_node->can('max') ) {
            if ( $old_node->max // '' ne $new_node->max // '' ) {
                $driver->set_prop( $new_node->id, 'max', $new_node->max );
            }
        }

        # Check step (Slider/Spinbox)
        if ( $old_node->can('step') && $new_node->can('step') ) {
            if ( $old_node->step // '' ne $new_node->step // '' ) {
                $driver->set_prop( $new_node->id, 'step', $new_node->step );
            }
        }

        # Check enabled (all widgets)
        if ( $old_node->can('enabled') && $new_node->can('enabled') ) {
            if ( $old_node->enabled // 1 != $new_node->enabled // 1 ) {
                $driver->set_prop( $new_node->id, 'enabled', $new_node->enabled );
            }
        }

        # Check visible (all widgets)
        if ( $old_node->can('visible') && $new_node->can('visible') ) {
            if ( $old_node->visible // 1 != $new_node->visible // 1 ) {
                $driver->set_prop( $new_node->id, 'visible', $new_node->visible );
            }
        }

        # Check focused (TextInput/Password)
        if ( $old_node->can('focused') && $new_node->can('focused') ) {
            if ( ( $old_node->focused // 0 ) != ( $new_node->focused // 0 ) ) {
                $driver->set_prop( $new_node->id, 'focused', $new_node->focused );
            }
        }

        # Check tooltip (all widgets)
        if ( $old_node->can('focused') && $new_node->can('focused') ) {
            if ( ( $old_node->focused // 0 ) != ( $new_node->focused // 0 ) ) {
                $driver->set_prop( $new_node->id, 'focused', $new_node->focused );
            }
        }

        # Check checked (Checkbox, ToggleSwitch)
        if ( $old_node->can('checked') && $new_node->can('checked') ) {
            if ( ( $old_node->checked // 0 ) != ( $new_node->checked // 0 ) ) {
                $driver->set_prop( $new_node->id, 'checked', $new_node->checked );
            }
        }

        # Check readonly / maxlength (TextInput, Password, MultilineText)
        if ( $old_node->can('readonly') && $new_node->can('readonly') ) {
            if ( ( $old_node->readonly // 0 ) != ( $new_node->readonly // 0 ) ) {
                $driver->set_prop( $new_node->id, 'readonly', $new_node->readonly );
            }
        }
        if ( $old_node->can('maxlength') && $new_node->can('maxlength') ) {
            if ( ( $old_node->maxlength // 0 ) != ( $new_node->maxlength // 0 ) ) {
                $driver->set_prop( $new_node->id, 'maxlength', $new_node->maxlength );
            }
        }

        # Check indeterminate (ProgressBar)
        if ( $old_node->can('indeterminate') && $new_node->can('indeterminate') ) {
            if ( ( $old_node->indeterminate // 0 ) != ( $new_node->indeterminate // 0 ) ) {
                $driver->set_prop( $new_node->id, 'indeterminate', $new_node->indeterminate );
            }
        }

        # Window geometry / state (topmost, min/max, minimized, maximized)
        if ( $old_node->can('topmost') && $new_node->can('topmost') ) {
            if ( ( $old_node->topmost // 0 ) != ( $new_node->topmost // 0 ) ) {
                $driver->set_prop( $new_node->id, 'topmost', $new_node->topmost );
            }
        }
        for my $p (qw[ minimized maximized ]) {
            if ( $old_node->can($p) && $new_node->can($p) ) {
                if ( ( $old_node->$p // 0 ) != ( $new_node->$p // 0 ) ) {
                    $driver->set_prop( $new_node->id, $p, $new_node->$p );
                }
            }
        }
        for my $p (qw[ min_w min_h max_w max_h ]) {
            if ( $old_node->can($p) && $new_node->can($p) ) {
                if ( ( $old_node->$p // 0 ) != ( $new_node->$p // 0 ) ) {
                    $driver->set_prop( $new_node->id, $p, $new_node->$p );
                }
            }
        }

        # Check Bounds (skip window its size is managed by the OS)
        if ( $old_node->type ne 'window' ) {
            if ( $old_node->bx != $new_node->bx ||
                $old_node->by != $new_node->by ||
                $old_node->bw != $new_node->bw ||
                $old_node->bh != $new_node->bh ) {
                $driver->move_widget( $new_node->id, $new_node->bx, $new_node->by, $new_node->bw, $new_node->bh );
            }
        }

        # Reconcile child collection
        $self->_patch_children( $old_node, $new_node, $driver );

        # RadioGroup selection: diff AFTER the child loop so the radio children carry their
        # transferred IDs and set_prop can route BM_SETCHECK updates to them.
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type eq 'radio_group' ) {
            if ( ( $old_node->value // '' ) ne ( $new_node->value // '' ) ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }
    }

    method _patch_children ( $old_node, $new_node, $driver ) {
        my $old_children = $old_node->children // [];
        my $new_children = $new_node->children // [];
        return unless @$old_children || @$new_children;
        my %old_by_key;
        my @old_unkeyed;
        for my $child (@$old_children) {
            if ( defined $child->key && $child->key ne '' ) {
                $old_by_key{ $child->key } = $child;
            }
            else {
                push @old_unkeyed, $child;
            }
        }
        my @matched_pairs;
        my @to_mount;
        for my $new_child (@$new_children) {
            my $matched_old = undef;
            if ( defined $new_child->key && $new_child->key ne '' ) {
                if ( exists $old_by_key{ $new_child->key } ) {
                    $matched_old = delete $old_by_key{ $new_child->key };
                }
            }
            else {
                if (@old_unkeyed) {
                    $matched_old = shift @old_unkeyed;
                }
            }
            if ($matched_old) {
                push @matched_pairs, [ $matched_old, $new_child ];
            }
            else {
                push @to_mount, $new_child;
            }
        }

        # Destroy old unreferenced children
        $self->_destroy_subtree( $_, $driver ) for values %old_by_key, @old_unkeyed;

        # Patch matched existing children
        $self->patch( $_->[0], $_->[1], $driver ) for @matched_pairs;

        # Mount brand-new children
        $driver->mount_widget($_) for @to_mount;
    }
};
1;
