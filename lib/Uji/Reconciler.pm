use v5.40;
use experimental 'class';
class Uji::Reconciler v0.0.1 {    # VDOM diffing and patching engine

    method patch ( $old_node, $new_node, $driver ) {
        return unless $old_node && $new_node;
        $new_node->set_id( $old_node->id );
        $driver->update_registry($new_node);

        # Check title (Window)
        if ( $old_node->can('title') && $new_node->can('title') ) {
            if ( $old_node->title ne $new_node->title ) {
                $driver->set_prop( $new_node->id, 'title', $new_node->title );
            }
        }

        # Check label (Text/Buttons)
        if ( $old_node->can('label') && $new_node->can('label') ) {
            if ( $old_node->label ne $new_node->label ) {
                $driver->set_prop( $new_node->id, 'label', $new_node->label );
            }
        }

        # Check value (TextInput, Slider) -- radio_group is handled after the child loop
        # so its radio children have stable, transferred IDs.
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type ne 'radio_group' ) {
            if ( $old_node->value ne $new_node->value ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }

        # Check range (Slider)
        if ( $old_node->can('min') && $old_node->can('max') ) {
            if ( $old_node->min ne $new_node->min ) {
                $driver->set_prop( $new_node->id, 'min', $new_node->min );
            }
            if ( $old_node->max ne $new_node->max ) {
                $driver->set_prop( $new_node->id, 'max', $new_node->max );
            }
        }

        # Check step (Slider)
        if ( $old_node->can('step') && $old_node->step ne $new_node->step ) {
            $driver->set_prop( $new_node->id, 'step', $new_node->step );
        }

        # Check enabled (all widgets)
        if ( $old_node->can('enabled') && $old_node->enabled != $new_node->enabled ) {
            $driver->set_prop( $new_node->id, 'enabled', $new_node->enabled );
        }

        # Check visible (all widgets)
        if ( $old_node->can('visible') && $old_node->visible != $new_node->visible ) {
            $driver->set_prop( $new_node->id, 'visible', $new_node->visible );
        }

        # Check focused (TextInput, Password)
        if ( $old_node->can('focused') && $old_node->focused != $new_node->focused ) {
            $driver->set_prop( $new_node->id, 'focused', $new_node->focused );
        }

        # Check tooltip (all widgets)
        if ( $old_node->can('tooltip') && ( $old_node->tooltip // '' ) ne ( $new_node->tooltip // '' ) ) {
            $driver->set_prop( $new_node->id, 'tooltip', $new_node->tooltip );
        }

        # Check checked (Checkbox)
        if ( $old_node->can('checked') && $old_node->checked != $new_node->checked ) {
            $driver->set_prop( $new_node->id, 'checked', $new_node->checked );
        }

        # Check readonly / maxlength (TextInput, Password)
        if ( $old_node->can('readonly') && $old_node->readonly != $new_node->readonly ) {
            $driver->set_prop( $new_node->id, 'readonly', $new_node->readonly );
        }
        if ( $old_node->can('maxlength') && $old_node->maxlength ne $new_node->maxlength ) {
            $driver->set_prop( $new_node->id, 'maxlength', $new_node->maxlength );
        }

        # Window geometry / state (topmost, min/max, minimized, maximized)
        if ( $old_node->can('topmost') && $old_node->topmost != $new_node->topmost ) {
            $driver->set_prop( $new_node->id, 'topmost', $new_node->topmost );
        }
        for my $p (qw[ minimized maximized ]) {
            if ( $old_node->can($p) && $old_node->$p != $new_node->$p ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }
        for my $p (qw[ min_w min_h max_w max_h ]) {
            if ( $old_node->can($p) && $old_node->$p ne $new_node->$p ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
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
        my $old_children = $old_node->children;
        my $new_children = $new_node->children;
        my $max          = @$old_children > @$new_children ? @$old_children : @$new_children;
        for my $i ( 0 .. $max - 1 ) {
            my $old_child = $old_children->[$i];
            my $new_child = $new_children->[$i];
            if ( $old_child && $new_child ) {
                $self->patch( $old_child, $new_child, $driver );
            }
        }

        # RadioGroup selection: diff AFTER the child loop so the radio children carry their
        # transferred IDs and set_prop can route BM_SETCHECK updates to them.
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type eq 'radio_group' ) {
            if ( $old_node->value ne $new_node->value ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }
    }
};
1;
