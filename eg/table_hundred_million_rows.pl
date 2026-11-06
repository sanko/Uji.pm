use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $TOTAL_ROWS = 100_000_000;

# Sparse state storage: only stores rows the user explicitly modifies!
my %edited_overrides;
my %checked_set;
my $init = sub () {
    return (
        {   total_items    => $TOTAL_ROWS,
            scroll_target  => -1,
            selected_pids  => [],
            sort_column    => 'id',
            sort_direction => 'asc',
            status_text    => 'Ready. 100,000,000 virtual rows loaded.'
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = { %$model, selected_pids => [ @{ $model->{selected_pids} } ] };
    $m->{scroll_target} = -1;    # Clear jump target so user can scroll freely afterwards
    my $t = $msg->{type};
    if ( $t eq 'SORT' ) {
        $m->{sort_column}    = $msg->{col};
        $m->{sort_direction} = $msg->{dir};
        $m->{scroll_target}  = 0;                                                          # Force jump back to top when sorting
        $m->{status_text}    = sprintf( "Sorted by %s (%s)", $msg->{col}, $msg->{dir} );
    }
    elsif ( $t eq 'JUMP_TO' ) {
        $m->{scroll_target} = $msg->{idx};
        $m->{status_text}   = sprintf( "Jumped to row index #%d", $msg->{idx} );
    }
    elsif ( $t eq 'SELECT_MULTI' ) {
        my @rows = ref $msg->{rows} eq 'ARRAY' ? @{ $msg->{rows} } : ( $msg->{rows} ? ( $msg->{rows} ) : () );
        $m->{selected_pids} = [ map { $_->{id} } @rows ];
        my $count = scalar(@rows);
        $m->{status_text}
            = $count == 0 ? "No items selected" : $count == 1 ? "Selected item #$rows[0]{id} ($rows[0]{name})" : "Selected $count items";
    }
    elsif ( $t eq 'TOGGLE_CHECK' ) {
        my $id = $msg->{row}{id};
        if ( $msg->{checked} ) { $checked_set{$id} = 1; }
        else                   { delete $checked_set{$id}; }
        $m->{status_text} = sprintf( "%s item #%d (Checked total: %d)", $msg->{checked} ? 'Checked' : 'Unchecked', $id, scalar( keys %checked_set ) );
    }
    elsif ( $t eq 'EDIT_CELL' ) {
        my $id = $msg->{row};    # We capture the true ID inside on_edit via closure mapping
        $edited_overrides{$id} = $msg->{val};
        $m->{status_text} = sprintf( "Edited item #%d -> '%s'", $id, $msg->{val} );
    }
    elsif ( $t eq 'CLEAR_ALL_CHECKS' ) {
        %checked_set = ();
        $m->{status_text} = "Cleared all checkmarks";
    }
    elsif ( $t eq 'INSPECT' ) {
        my $row = $msg->{row};
        return (
            $m,
            message_box(
                title   => "Virtual Item Inspector - Item #$row->{id}",
                message => sprintf(
                    "ID: %s\nName: %s\nProgress: %s%%\nMemory: %s\nStatus: %s\nChecked: %s",
                    $row->{id}, $row->{name}, $row->{progress}, $row->{memory}, $row->{status}, $checked_set{ $row->{id} } ? 'Yes' : 'No'
                ),
                type => 'ok',
                icon => 'info'
            )
        );
    }
    return ( $m, undef );
};

# True Bijective Virtual Row Generator: O(1) mapping with 3-Partition Alphabetical Sorting
my $get_virtual_row = sub ( $idx, $model ) {
    my $col     = $model->{sort_column} // 'id';
    my $is_desc = ( $model->{sort_direction} // 'asc' ) eq 'desc';
    my $v_id;
    my $id;
    if ( $col eq 'name' ) {

        # Partition edits into "Before" and "After" the default block
        my @before;
        my @after;
        for my $eid ( keys %edited_overrides ) {
            my $name = $edited_overrides{$eid};
            if ( ( lc($name) cmp 'mission_payload_0' ) < 0 ) {
                push @before, $eid;
            }
            else {
                push @after, $eid;
            }
        }

        # Sort the partitions alphabetically
        my $cmp_fn = sub { lc( $edited_overrides{$a} ) cmp lc( $edited_overrides{$b} ) };
        @before = sort $cmp_fn @before;
        @after  = sort $cmp_fn @after;

        # Reverse if descending
        if ($is_desc) {
            my @temp = reverse @before;
            @before = reverse @after;
            @after  = @temp;
        }

        # Route the index to the correct partition
        if ( $idx < @before ) {
            $id   = $before[$idx];
            $v_id = $id - 1;
        }
        elsif ( $idx >= $TOTAL_ROWS - @after ) {
            $id   = $after[ $idx - ( $TOTAL_ROWS - @after ) ];
            $v_id = $id - 1;
        }
        else {
            # Middle block: we want the K-th unedited item
            my $K = $idx - scalar(@before);

            # Gather where the edited items originally lived so we can skip them
            my @hole_indices;
            for my $eid ( keys %edited_overrides ) {
                my $evid = $eid - 1;
                push @hole_indices, $is_desc ? ( ( $TOTAL_ROWS - 1 ) - $evid ) : $evid;
            }
            @hole_indices = sort { $a <=> $b } @hole_indices;

            # Fast-forward target index to skip holes
            my $target = $K;
            for my $hole_idx (@hole_indices) {
                if ( $hole_idx <= $target ) {
                    $target++;
                }
                else {
                    last;
                }
            }
            $v_id = $is_desc ? ( ( $TOTAL_ROWS - 1 ) - $target ) : $target;
        }
    }
    elsif ( $col eq 'progress' ) {
        my $bucket_size = int( $TOTAL_ROWS / 101 );
        my $P           = int( $idx / $bucket_size );
        $P = 100      if $P > 100;
        $P = 100 - $P if $is_desc;
        my $K = $idx % $bucket_size;
        $v_id = ( ( $P * 6 ) % 101 ) + ( $K * 101 );
    }
    elsif ( $col eq 'memory' ) {
        my $bucket_size = int( $TOTAL_ROWS / 800 );
        my $M           = int( $idx / $bucket_size );
        $M = 799      if $M > 799;
        $M = 799 - $M if $is_desc;
        my $K = $idx % $bucket_size;
        $v_id = ( ( $M * 671 ) % 800 ) + ( $K * 800 );
    }
    elsif ( $col eq 'status' ) {
        my $bucket_size = int( $TOTAL_ROWS / 4 );
        my $S           = int( $idx / $bucket_size );
        $S = 3      if $S > 3;
        $S = 3 - $S if $is_desc;
        my $K = $idx % $bucket_size;
        $v_id = $S + ( $K * 4 );
    }
    else {
        # Fallback to ID sorting
        $v_id = $is_desc ? ( ( $TOTAL_ROWS - 1 ) - $idx ) : $idx;
    }

    # Generate properties permanently locked to $v_id
    $id //= $v_id + 1;
    my $name     = $edited_overrides{$id} // sprintf( "Mission_Payload_%09d.tar", $id );
    my $prog_val = ( $v_id * 17 ) % 101;
    my $mem_val  = ( $v_id * 31 ) % 800;
    my $stat_val = $v_id % 4;
    my $status   = $stat_val == 0 ? 'Active' : $stat_val == 1 ? 'Done' : $stat_val == 2 ? 'Idle' : 'Suspended';
    return {
        id       => $id,
        name     => $name,
        progress => $prog_val,
        memory   => sprintf( '%.1f MB', $mem_val + 12.5 ),
        status   => $status,
        checked  => $checked_set{$id} // 0
    };
};
my $view = sub ($model) {
    my $chk_count            = scalar( keys %checked_set );
    my $context_menu_builder = sub ( $indices, $rows ) {
        my @sel_rows = ref $rows eq 'ARRAY' ? @$rows : ( $rows ? ($rows) : () );
        my $count    = scalar(@sel_rows);
        my @items;
        if ( $count > 0 ) {
            push @items,
                menu_item(
                label    => ( $count == 1 ? "Inspect ($sel_rows[0]{name})" : "Inspect First ($sel_rows[0]{name})" ),
                on_click => { type => 'INSPECT', row => $sel_rows[0] }
                );
            push @items, menu_separator();
        }
        push @items, menu_item( label => 'Clear All Checkmarks', on_click => { type => 'CLEAR_ALL_CHECKS' }, enabled => ( $chk_count > 0 ? 1 : 0 ) );
        return menu( items => \@items );
    };
    window(
        title    => 'Uji 100,000,000 Virtual Rows Table Demo',
        w        => 760,
        h        => 560,
        centered => 1,
        child    => column(
            padding  => 12,
            spacing  => 8,
            children => [
                row(
                    spacing  => 8,
                    children => [
                        text('Jump to:'),
                        button( label => 'Row 1',    on_click => { type => 'JUMP_TO', idx => 0 } ),
                        button( label => 'Row 50M',  on_click => { type => 'JUMP_TO', idx => 50_000_000 } ),
                        button( label => 'Row 100M', on_click => { type => 'JUMP_TO', idx => 99_999_999 } ),
                        spacer(),
                        button( label => 'Clear Checks', on_click => { type => 'CLEAR_ALL_CHECKS' } )
                    ]
                ),
                list_view(
                    flex           => 1,
                    virtual        => 1,
                    multiselect    => 1,
                    checkboxes     => 1,
                    column_reorder => 1,
                    gridlines      => 1,
                    row_count      => $model->{total_items},
                    scroll_to_row  => $model->{scroll_target},
                    sort_column    => $model->{sort_column},
                    sort_direction => $model->{sort_direction},
                    on_row         => sub ($idx) { $get_virtual_row->( $idx, $model ) },
                    on_sort        => sub ( $col_id, $dir ) {
                        { type => 'SORT', col => $col_id, dir => $dir }
                    },
                    on_activate => sub ( $idx, $row ) {
                        { type => 'INSPECT', row => $row }
                    },
                    on_check => sub ( $idx, $row, $checked ) {
                        { type => 'TOGGLE_CHECK', row => $row, checked => $checked }
                    },
                    on_edit => sub ( $r_idx, $col_id, $new_txt ) {
                        my $row = $get_virtual_row->( $r_idx, $model );
                        { type => 'EDIT_CELL', row => $row->{id}, col => $col_id, val => $new_txt };
                    },
                    context_menu => $context_menu_builder,
                    columns      => [
                        { id => 'id',       text => 'ID',                  width => 95,  align => 'right' },
                        { id => 'name',     text => 'Payload Name (Edit)', width => 230, align => 'left',   editable => 1 },
                        { id => 'progress', text => 'Load %',              width => 125, align => 'center', type     => 'progress_bar' },
                        { id => 'memory',   text => 'Allocated',           width => 105, align => 'right' },
                        { id => 'status',   text => 'Status',              width => 110, align => 'center', type => 'badge' }
                    ],
                    on_select => sub ( $indices, $rows ) {
                        { type => 'SELECT_MULTI', rows => $rows }
                    }
                ),
                row(
                    children => [
                        text("Status: $model->{status_text}"), spacer(),
                        text( sprintf( "Checked: %d | Dataset: %s rows", $chk_count, "100,000,000" ) )
                    ]
                )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
