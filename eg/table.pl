use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];

sub sort_processes ( $rows, $col, $dir ) {
    return $rows unless $col;
    my $is_desc = ( $dir eq 'desc' );
    my $cmp;
    if ( $col eq 'pid' ) {
        $cmp = sub ( $a, $b ) { ( $a->{pid} // 0 ) <=> ( $b->{pid} // 0 ) };
    }
    elsif ( $col eq 'cpu' ) {
        $cmp = sub ( $a, $b ) {
            my ($av) = ( $a->{cpu} // '' ) =~ /([\d.]+)/;
            my ($bv) = ( $b->{cpu} // '' ) =~ /([\d.]+)/;
            ( $av // 0 ) <=> ( $bv // 0 );
        };
    }
    elsif ( $col eq 'mem' ) {
        $cmp = sub ( $a, $b ) {
            my ($av) = ( $a->{mem} // '' ) =~ /([\d.]+)/;
            my ($bv) = ( $b->{mem} // '' ) =~ /([\d.]+)/;
            ( $av // 0 ) <=> ( $bv // 0 );
        };
    }
    else {
        $cmp = sub ( $a, $b ) {
            lc( $a->{$col} // '' ) cmp lc( $b->{$col} // '' );
        };
    }
    my @sorted = sort { $is_desc ? $cmp->( $b, $a ) : $cmp->( $a, $b ) } @$rows;
    return \@sorted;
}
my $subscriptions = sub ($model) {
    return every( 1000, sub { { type => 'TICK' } }, key => 'fake_process_activity_timer' );
};
my $init = sub () {
    my @initial_processes = (
        { pid => '1048', name => 'perl.exe',         cpu => 14.2, mem => 48.2,  status => 'Running',   checked => 1 },
        { pid => '2104', name => 'chrome.exe',       cpu => 28.5, mem => 342.1, status => 'Running',   checked => 1 },
        { pid => '3840', name => 'code.exe',         cpu => 4.1,  mem => 215.8, status => 'Running',   checked => 0 },
        { pid => '4192', name => 'explorer.exe',     cpu => 0.8,  mem => 94.5,  status => 'Running',   checked => 0 },
        { pid => '5216', name => 'discord.exe',      cpu => 0,    mem => 138.0, status => 'Idle',      checked => 0 },
        { pid => '6844', name => 'spotify.exe',      cpu => 2.0,  mem => 112.4, status => 'Running',   checked => 0 },
        { pid => '7412', name => 'terminal.exe',     cpu => 0.1,  mem => 32.6,  status => 'Running',   checked => 1 },
        { pid => '8920', name => 'postgres.exe',     cpu => 3.4,  mem => 82.1,  status => 'Running',   checked => 1 },
        { pid => '9100', name => 'sublime_text.exe', cpu => 0.0,  mem => 44.0,  status => 'Suspended', checked => 0 }
    );
    return (
        {   search_query   => '',
            processes      => \@initial_processes,
            selected_pids  => [],
            sort_column    => 'cpu',
            sort_direction => 'desc',
            status_text    => 'Ready. Multi-select enabled. Right-click for menu.'
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = {
        %$model,
        processes => [
            map {
                {%$_}
            } @{ $model->{processes} }
        ],
        selected_pids => [ @{ $model->{selected_pids} } ]
    };
    my $t = $msg->{type};
    if ( $t eq 'FILTER' ) {
        $m->{search_query} = $msg->{val};
    }
    elsif ( $t eq 'SORT' ) {
        $m->{sort_column}    = $msg->{col};
        $m->{sort_direction} = $msg->{dir};
        $m->{status_text}    = sprintf( "Sorted by %s (%s)", $msg->{col}, $msg->{dir} );
    }
    elsif ( $t eq 'SELECT_MULTI' ) {
        my @rows = ref $msg->{rows} eq 'ARRAY' ? @{ $msg->{rows} } : ( $msg->{rows} ? ( $msg->{rows} ) : () );
        $m->{selected_pids} = [ map { $_->{pid} } @rows ];
        my $count = scalar(@rows);
        if ( $count == 0 ) {
            $m->{status_text} = "No items selected";
        }
        elsif ( $count == 1 ) {
            $m->{status_text} = sprintf( "Selected 1 process: %s (PID %s)", $rows[0]{name}, $rows[0]{pid} );
        }
        else {
            $m->{status_text} = sprintf( "Selected %d processes", $count );
        }
    }
    elsif ( $t eq 'TOGGLE_CHECK' ) {
        my $target_pid = $msg->{row}{pid};
        for my $p ( @{ $m->{processes} } ) {
            if ( $p->{pid} eq $target_pid ) {
                $p->{checked}     = $msg->{checked};
                $m->{status_text} = sprintf( "%s PID %s", $msg->{checked} ? 'Checked' : 'Unchecked', $target_pid );
                last;
            }
        }
    }
    elsif ( $t eq 'SELECT_ALL' ) {
        $m->{selected_pids} = [ map { $_->{pid} } @{ $m->{processes} } ];
        $m->{status_text}   = "Selected all " . scalar( @{ $m->{processes} } ) . " processes";
    }
    elsif ( $t eq 'DESELECT_ALL' ) {
        $m->{selected_pids} = [];
        $m->{status_text}   = "Cleared selection";
    }
    elsif ( $t eq 'KILL_PIDS' ) {
        my %kill_set = map { $_ => 1 } @{ $msg->{pids} // [] };
        if ( keys %kill_set ) {
            $m->{processes}     = [ grep { !$kill_set{ $_->{pid} } } @{ $m->{processes} } ];
            $m->{selected_pids} = [ grep { !$kill_set{$_} } @{ $m->{selected_pids} } ];
            $m->{status_text}   = sprintf( "Terminated %d process(es)", scalar( keys %kill_set ) );
        }
    }
    elsif ( $t eq 'KILL_SELECTED' ) {
        my %kill_set = map { $_ => 1 } @{ $m->{selected_pids} };
        if ( keys %kill_set ) {
            $m->{processes}     = [ grep { !$kill_set{ $_->{pid} } } @{ $m->{processes} } ];
            $m->{selected_pids} = [];
            $m->{status_text}   = sprintf( "Terminated %d process(es)", scalar( keys %kill_set ) );
        }
    }
    elsif ( $t eq 'INSPECT' ) {
        my $row = $msg->{row};
        return (
            $m,
            message_box(
                title   => "Process Details - $row->{name}",
                message => sprintf(
                    "Name: %s\nPID: %s\nCPU Load: %s\nMemory Usage: %s\nCurrent Status: %s\nFavorite: %s",
                    $row->{name}, $row->{pid}, $row->{cpu}, $row->{mem}, $row->{status}, $row->{checked} ? 'Yes' : 'No'
                ),
                type => 'ok',
                icon => 'info'
            )
        );
    }
    elsif ( $t eq 'ADD' ) {
        my $new_pid  = int( rand(9000) ) + 1000;
        my $new_proc = {
            pid     => $new_pid,
            name    => "worker_$new_pid.exe",
            cpu     => rand(40),
            mem     => rand(160) + 10,
            status  => ( rand() > 0.3 ? 'Running' : 'Idle' ),
            checked => 0
        };
        push @{ $m->{processes} }, $new_proc;
        $m->{status_text} = "Spawned worker PID $new_pid";
    }
    elsif ( $t eq 'TICK' ) {

        sub _min_max( $val, $min = 0, $max = 100 ) {
            $val > $max ? $max : $val < $min ? $min : $val;
        }
        $m = {
            %$model,
            processes => [
                map {
                    {
                        %$_, (
                            $_->{status} eq 'Running' ?
                                (
                                cpu => _min_max( $_->{cpu} + ( rand > .5 ? rand : -rand ) ),
                                mem => _min_max( $_->{mem} + ( rand > .5 ? rand : -rand ), .01, 1000 )
                                ) :
                                ()
                            )
                    }
                } @{ $model->{processes} }
            ],
            selected_pids => [ @{ $model->{selected_pids} } ]
        };
    }
    return ( $m, undef );
};
my $view = sub ($model) {

    # Filter rows
    my $q = lc $model->{search_query};
    my @filtered
        = grep { length($q) == 0 || index( lc( $_->{name} ), $q ) >= 0 || index( $_->{pid}, $q ) >= 0 || index( lc( $_->{status} ), $q ) >= 0 }
        @{ $model->{processes} };

    # Sort rows
    my $sorted_rows = sort_processes( \@filtered, $model->{sort_column}, $model->{sort_direction} );

    # Match selected indices
    my %sel_lookup = map { $_ => 1 } @{ $model->{selected_pids} };
    my @selected_indices;
    my @selected_objs;
    my $total_mem = 0;
    my $total_cpu = 0;
    for my $i ( 0 .. $#$sorted_rows ) {
        my $r = $sorted_rows->[$i];
        if ( $sel_lookup{ $r->{pid} } ) {
            push @selected_indices, $i;
            push @selected_objs,    $r;
            my ($mv) = $r->{mem} =~ /([\d.]+)/;
            my ($cv) = $r->{cpu} =~ /([\d.]+)/;
            $total_mem += ( $mv // 0 );
            $total_cpu += ( $cv // 0 );
        }
    }
    my $num_sel = scalar(@selected_objs);
    my $summary_text;
    if ( $num_sel == 0 ) {
        $summary_text = 'No processes selected. Tip: Click or Ctrl/Shift+Click to select, Double-click to inspect, Right-click for menu.';
    }
    elsif ( $num_sel == 1 ) {
        my $r = $selected_objs[0];
        $summary_text
            = sprintf( 'Selected: %s (PID %s) | Memory: %s | CPU: %s | Status: %s', $r->{name}, $r->{pid}, $r->{mem}, $r->{cpu}, $r->{status} );
    }
    else {
        $summary_text = sprintf( 'Selected %d processes | Combined CPU: %.1f%% | Combined Memory: %.1f MB', $num_sel, $total_cpu, $total_mem );
    }

    # Context menu
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
            push @items,
                menu_item(
                label    => ( $count == 1 ? "End Task (PID $sel_rows[0]{pid})" : "End $count Selected Tasks" ),
                on_click => { type => 'KILL_PIDS', pids => [ map { $_->{pid} } @sel_rows ] }
                );
            push @items, menu_separator();
        }
        push @items, menu_item( label => 'Select All', on_click => { type => 'SELECT_ALL' } );
        push @items, menu_item( label => 'Deselect All', on_click => { type => 'DESELECT_ALL' }, enabled => ( $count > 0 ? 1 : 0 ) );
        return menu( items => \@items );
    };
    window(
        title    => 'Uji ListView - Checkboxes, Cell Widgets & Context Menu',
        w        => 740,
        h        => 560,
        centered => 1,
        child    => column(
            padding  => 12,
            spacing  => 8,
            children => [

                # Top Toolbar
                row(
                    spacing  => 8,
                    children => [
                        text('Filter:'),
                        text_input( value => $model->{search_query}, on_input => sub ($v) { { type => 'FILTER', val => $v } }, flex => 1 ),
                        button( label => 'Spawn Worker', on_click => { type => 'ADD' } ),
                        button(
                            label    => ( $num_sel > 1 ? "End Selected ($num_sel)" : "End Task" ),
                            enabled  => ( $num_sel > 0 ),
                            on_click => { type => 'KILL_SELECTED' }
                        )
                    ]
                ),

                # Multi-Column ListView Data Table with Cell Widgets (Progress Bars & Badges)
                list_view(
                    flex           => 1,
                    multiselect    => 1,
                    checkboxes     => 1,
                    column_reorder => 1,
                    gridlines      => 1,
                    sort_column    => $model->{sort_column},
                    sort_direction => $model->{sort_direction},
                    on_sort        => sub ( $col_id, $dir ) {
                        { type => 'SORT', col => $col_id, dir => $dir }
                    },
                    on_activate => sub ( $idx, $row ) {
                        { type => 'INSPECT', row => $row }
                    },
                    on_check => sub ( $idx, $row, $checked ) {
                        { type => 'TOGGLE_CHECK', row => $row, checked => $checked }
                    },
                    context_menu => $context_menu_builder,
                    columns      => [
                        { id => 'pid',    text => 'PID',          width => 75,  align => 'right' },
                        { id => 'name',   text => 'Process Name', width => 190, align => 'left' },
                        { id => 'cpu',    text => 'CPU Load',     width => 130, align => 'center', type   => 'progress_bar', format => '%3.2f%%' },
                        { id => 'mem',    text => 'Memory',       width => 105, align => 'right',  format => '%3.2f MB' },
                        { id => 'status', text => 'Status',       width => 110, align => 'center', type   => 'badge' }
                    ],
                    rows      => $sorted_rows,
                    selected  => \@selected_indices,
                    on_select => sub ( $indices, $rows ) {
                        { type => 'SELECT_MULTI', rows => $rows }
                    }
                ),

                # Selection details
                text($summary_text),

                # Status bar
                row(
                    children => [
                        text("Status: $model->{status_text}"), spacer(),
                        text( sprintf( "%d of %d items", scalar(@$sorted_rows), scalar( @{ $model->{processes} } ) ) )
                    ]
                )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view, subscriptions => $subscriptions )->run();
