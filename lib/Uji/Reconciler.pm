use v5.40;
use experimental 'class';
class Uji::Reconciler v0.0.1 {    # VDOM diffing and patching engine

    method patch_windows ( $old_vtrees, $new_vtrees, $driver ) {

        # view() rebuilds the window nodes from scratch on every render, so auto-generated ids
        # (Uji::Node's monotonic counter) never match between passes. Pair each new window with
        # an old one: prefer a stable explicit id, otherwise fall back to position (the order of
        # the window list is the app's own). patch() transfers the old id to the new node, so the
        # top-level HWND is preserved and the window is NOT recreated when nothing structural
        # changed.
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

        # Destroy windows that are no longer present.
        for my $i ( 0 .. $#old ) {
            next                         if $paired[$i];
            $driver->unmount( $old[$i] ) if $driver->can('unmount');
        }
    }

    method patch ( $old_node, $new_node, $driver, $ctx = undef ) {
        return unless $old_node && $new_node;
        $new_node->set_id( $old_node->id );
        $driver->update_registry($new_node);

        # Mount-only props (multiline, orientation, align): if any changed, the native control
        # must be destroyed and recreated from scratch. The ID is transferred so the registry
        # entry is updated. We do NOT return here: the remaining prop diffs are idempotent
        # re-applies against the freshly-mounted control, and the child loop below transfers the
        # children's IDs so their existing HWNDs keep working.
        if ( $old_node->can('_mount_only_props') ) {
            for my $prop ( @{ $old_node->_mount_only_props } ) {
                if ( ( $old_node->$prop // '' ) ne ( $new_node->$prop // '' ) ) {
                    $driver->recreate_node( $old_node->id, $new_node );
                    last;
                }
            }
        }

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

        # Check value (TextInput, Slider, ComboBox, ListBox) -- radio_group is handled after the
        # child loop so its radio children have stable, transferred IDs.
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type ne 'radio_group' ) {
            if ( $self->_value_key( $old_node->value ) ne $self->_value_key( $new_node->value ) ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }

        # Check options (ComboBox, ListBox) -- rebuild the item strings when they change.
        # Deliberately a semantic compare (value|label pairs), not arrayref stringification.
        if ( ( $new_node->type eq 'combo_box' || $new_node->type eq 'list_box' ) && $self->_opts_key($old_node) ne $self->_opts_key($new_node) ) {
            $driver->set_prop( $new_node->id, 'options', $new_node->options );
        }

        # Check nodes/expanded (TreeView) -- rebuild the tree items when either changes.
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

        # Check columns/rows (ListView) -- a columns change recreates the header (which resets widths
        # and any drag-reordered order), so it is reconciled separately from a rows-only change, which
        # refills the cells and leaves the user's columns alone.
        if ( $new_node->type eq 'list_view' ) {
            if ( $self->_columns_key($old_node) ne $self->_columns_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'columns', $new_node->columns );
            }
            elsif ( $self->_rows_key($old_node) ne $self->_rows_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'rows', $new_node->rows );
            }
        }

        # Check panels (StatusBar) -- SB_SETPARTS + per-pane SB_SETTEXT
        if ( $old_node->can('panels') && $new_node->can('panels') && join( "\0", @{ $old_node->panels } ) ne join( "\0", @{ $new_node->panels } ) ) {
            $driver->set_prop( $new_node->id, 'panels', $new_node->panels );
        }

        # Check buttons (Toolbar) -- rebuild the button set when any label/id/state changes.
        if ( $new_node->type eq 'toolbar' ) {
            if ( $self->_buttons_key($old_node) ne $self->_buttons_key($new_node) ) {
                $driver->set_prop( $new_node->id, 'buttons', $new_node->buttons );
            }
        }

        # Check menu_bar (Window) -- rebuild the native menu when any item/label/id/state changes.
        if ( $old_node->can('menu_bar') && $new_node->can('menu_bar') ) {
            if ( $self->_menu_key( $old_node->menu_bar ) ne $self->_menu_key( $new_node->menu_bar ) ) {
                $driver->set_prop( $new_node->id, 'menu_bar', $new_node->menu_bar );
            }
        }

        # Check scroll offsets (ScrollView) -- re-apply to the shared scroll store
        for my $p (qw[ scroll_x scroll_y ]) {
            if ( $old_node->can($p) && ( $old_node->$p // 0 ) != ( $new_node->$p // 0 ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }

        # Check divider / orientation (SplitView) -- move the divider strip (Layout re-lays-out the
        # panes on every render, so the driver only needs to track the strip itself).
        if ( $new_node->type eq 'split_view' ) {
            if ( ( $old_node->orientation // '' ) ne ( $new_node->orientation // '' ) ) {
                $driver->set_prop( $new_node->id, 'orientation', $new_node->orientation );
            }
            if ( ( $old_node->divider // '' ) ne ( $new_node->divider // '' ) ) {
                $driver->set_prop( $new_node->id, 'divider', $new_node->divider );
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
        if ( $old_node->can('enabled') && ( $old_node->enabled // 0 ) != ( $new_node->enabled // 0 ) ) {
            $driver->set_prop( $new_node->id, 'enabled', $new_node->enabled );
        }

        # Check visible (all widgets)
        if ( $old_node->can('visible') && ( $old_node->visible // 0 ) != ( $new_node->visible // 0 ) ) {
            $driver->set_prop( $new_node->id, 'visible', $new_node->visible );
        }

        # Check focused (TextInput, Password)
        if ( $old_node->can('focused') && ( $old_node->focused // 0 ) != ( $new_node->focused // 0 ) ) {
            $driver->set_prop( $new_node->id, 'focused', $new_node->focused );
        }

        # Check tooltip (all widgets)
        if ( $old_node->can('tooltip') && ( $old_node->tooltip // '' ) ne ( $new_node->tooltip // '' ) ) {
            $driver->set_prop( $new_node->id, 'tooltip', $new_node->tooltip );
        }

        # Check checked (Checkbox)
        if ( $old_node->can('checked') && ( $old_node->checked // 0 ) != ( $new_node->checked // 0 ) ) {
            $driver->set_prop( $new_node->id, 'checked', $new_node->checked );
        }

        # Check readonly / maxlength (TextInput, Password)
        if ( $old_node->can('readonly') && ( $old_node->readonly // 0 ) != ( $new_node->readonly // 0 ) ) {
            $driver->set_prop( $new_node->id, 'readonly', $new_node->readonly );
        }
        if ( $old_node->can('maxlength') && $old_node->maxlength ne $new_node->maxlength ) {
            $driver->set_prop( $new_node->id, 'maxlength', $new_node->maxlength );
        }

        # Check placeholder (TextInput/Password) -- EM_SETCUEBANNER
        if ( $old_node->can('placeholder') && ( $old_node->placeholder // '' ) ne ( $new_node->placeholder // '' ) ) {
            $driver->set_prop( $new_node->id, 'placeholder', $new_node->placeholder );
        }

        # Check password_char (Password) -- EM_SETPASSWORDCHAR
        if ( $old_node->can('password_char') && ( $old_node->password_char // '' ) ne ( $new_node->password_char // '' ) ) {
            $driver->set_prop( $new_node->id, 'password_char', $new_node->password_char );
        }

        # Check colour / background (all widgets) -- WM_CTLCOLOR*
        for my $p (qw[ color background ]) {
            if ( $old_node->can($p) && ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }

        # Check font / font_size (all widgets) -- WM_SETFONT
        for my $p (qw[ font font_size ]) {
            if ( $old_node->can($p) && ( $old_node->$p // '' ) ne ( $new_node->$p // '' ) ) {
                $driver->set_prop( $new_node->id, $p, $new_node->$p );
            }
        }

        # Window geometry / state (topmost, min/max, minimized, maximized)
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

        # Anchors: the nearest ancestor that owns real HWND placement. Children added under a
        # window parent to the window; under a scroll_view they must parent to its viewport HWND
        # and inherit its scroll store; under a group_box / tab_panel they are host-window siblings.
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

                # Added child: mount it under the same HWND as its mounted siblings and inherit
                # their scroll store, so rows appended inside a ScrollView content column land
                # inside the viewport and offset with it (the scroll_view mount branch does this
                # for its initial content; the sibling record carries the same parent/store).
                # When the content column was EMPTY there is no sibling, so the anchor context
                # ($child_ctx) supplies parent hwnd + store structurally instead.
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

        # ScrollView: rows added/removed during this render change the content rect, but the
        # scroll_view itself FILLS its parent, so its own bounds are unchanged and the generic
        # bounds diff above never re-drives move_widget. Only a window resize did (WM_SIZE ->
        # _relayout_now runs on the LIVE tree), which is why added rows were not accounted for
        # until the user resized the window. Refresh placement/scrollbars after the child loop so
        # the range tracks the new content immediately (idempotent when nothing changed).
        if ( $new_node->type eq 'scroll_view' && $driver->can('_place_scrollbars') ) {
            $driver->_place_scrollbars( $new_node->id );
            $driver->_apply_scroll( $new_node->id ) if $driver->can('_apply_scroll');
        }

        # RadioGroup selection: diff AFTER the child loop so the radio children carry their
        # transferred IDs and set_prop can route BM_SETCHECK updates to them.
        if ( $old_node->can('value') && $new_node->can('value') && $new_node->type eq 'radio_group' ) {
            if ( $old_node->value ne $new_node->value ) {
                $driver->set_prop( $new_node->id, 'value', $new_node->value );
            }
        }

        # TabPanel selection / strip: diff AFTER the child loop so any NEW panel contents are
        # mounted before the driver applies visibility (set_prop index -> _apply_tab shows the
        # active subtree and hides the rest).
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

    # Canonical form of a node's options (value|label pairs joined by NUL).
    method _opts_key ($node) {
        return join "\0", map { ( $_->{value} // '' ) . '|' . ( $_->{label} // '' ) } @{ $node->options // [] };
    }

    # Canonical form of a tree_view node's items (recursive value|label with bracketed children).
    method _tree_key ($node) {
        my $s;
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

    # Canonical form of a list_view node's column definitions (label, width, sort mode, display format,
    # alignment). Header-only definitions distinct from the row cells.
    method _columns_key ($node) {
        return join "\0", map {
            join( '|',
                ( $_->{label}  // '' ),
                ( $_->{width}  // '' ),
                ( $_->{sort}   // '' ),
                ( $_->{format} // '' ),
                ( $_->{align}  // '' ) )
        } @{ $node->columns // [] };
    }

    # Canonical form of a list_view node's rows (value + every cell), so a pure rows change can be
    # reconciled without recreating the columns.
    method _rows_key ($node) {
        my $s = '';
        for my $r ( @{ $node->rows // [] } ) {
            my $cells = ref $r eq 'HASH' ? $r->{columns} : $r;
            $s .= ';r' . ( ref $r eq 'HASH' ? ( $r->{value} // '' ) : '' ) . '|' . join( ',', map { '' . ( $_ // '' ) } @{ $cells // [] } );
        }
        return $s;
    }

    # Canonical form of a node's value: arrayref multi-selections are compared element-wise.
    method _value_key ($value) {
        return ref $value eq 'ARRAY' ? join "\0", map { '' . ( $_ // '' ) } @$value : '' . ( $value // '' );
    }

    # Canonical form of a toolbar node's buttons list (label|id|separator|checked|enabled).
    method _buttons_key ($node) {
        return join "\0", map {
            ref $_ eq 'HASH' ?
                join( '|',
                ( $_->{label} // '' ),
                ( $_->{id}    // '' ),
                ( $_->{separator}       ? 's'                           : '' ),
                ( $_->{checked}         ? 'c'                           : '' ),
                ( defined $_->{enabled} ? ( $_->{enabled} ? 'e' : 'd' ) : '' ),
                ( $_->{width} // '' ) ) :
                ''
        } @{ $node->buttons // [] };
    }

    # Canonical form of a window's menu_bar items (recursive label|id|separator|checked|enabled).
    # Assigned to the WINDOW node (not the MenuBar node) since that is what patch() diffds.
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
