use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return (
        {   split_ratio => 0.45,
            query_text  =>
                "-- SQL / Command Query Editor\nSELECT id, name, status, created_at\nFROM users\nWHERE active = 1\nORDER BY created_at DESC\nLIMIT 50;",
            logs => [
                "[12:00:01] System initialized.",
                "[12:00:02] Connected to database: postgres://localhost:5432/main",
                "[12:00:03] Ready for execution."
            ],
            counter => 1
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = { %$model, logs => [ @{ $model->{logs} } ] };
    my $t = $msg->{type};
    if ( $t eq 'SET_SPLIT' ) {
        $m->{split_ratio} = $msg->{val};
    }
    elsif ( $t eq 'SET_QUERY' ) {
        $m->{query_text} = $msg->{val};
    }
    elsif ( $t eq 'EXECUTE' ) {
        my $num  = $m->{counter}++;
        my $time = sprintf( "%02d:%02d:%02d", (localtime)[2], (localtime)[1], (localtime)[0] );
        push @{ $m->{logs} }, "[$time] Query #$num executed successfully: (returned 42 rows in 14ms)";
    }
    elsif ( $t eq 'CLEAR_LOGS' ) {
        $m->{logs} = ["[System] Execution log cleared."];
    }
    elsif ( $t eq 'PRESET_SPLIT' ) {
        $m->{split_ratio} = $msg->{val};
    }
    return ( $m, undef );
};
my $view = sub ($model) {
    my @log_rows;
    for my $i ( 0 .. $#{ $model->{logs} } ) {
        my $entry = $model->{logs}[$i];
        push @log_rows, row( key => "log-$i", spacing => 6, children => [ text( $entry, flex => 1 ) ] );
    }
    window(
        title    => 'Uji Vertical SplitView Demo',
        w        => 640,
        h        => 520,
        centered => 1,
        child    => column(
            padding  => 12,
            spacing  => 8,
            children => [

                # Top action bar
                row(
                    spacing  => 8,
                    children => [
                        button( label => 'Execute Query', on_click => { type => 'EXECUTE' } ),
                        button( label => 'Clear Log',     on_click => { type => 'CLEAR_LOGS' } ),
                        spacer(),
                        button( label => '50 / 50', on_click => { type => 'PRESET_SPLIT', val => 0.50 } ),
                        button( label => '70 / 30', on_click => { type => 'PRESET_SPLIT', val => 0.70 } ),
                        button( label => '30 / 70', on_click => { type => 'PRESET_SPLIT', val => 0.30 } ),
                        spacer(),
                        text( sprintf( 'Split: %d%%', int( $model->{split_ratio} * 100 ) ) )
                    ]
                ),

                # Vertical SplitView (top editor pane / bottom output log pane)
                split_view(
                    flex        => 1,
                    orientation => 'vertical',
                    split       => $model->{split_ratio},
                    min_first   => 80,
                    min_second  => 80,
                    on_change   => sub ($ratio) { { type => 'SET_SPLIT', val => $ratio } },

                    # Top Pane: SQL / Script editor
                    first => group_box(
                        label => 'Query / Script Editor',
                        child =>
                            multiline_text( value => $model->{query_text}, on_input => sub ($v) { { type => 'SET_QUERY', val => $v } }, flex => 1 )
                    ),

                    # Bottom Pane: Execution Output inside a clipped ScrollView
                    second => group_box(
                        label => 'Execution Log & Results',
                        child => scroll_view( flex => 1, child => column( padding => 6, spacing => 4, children => \@log_rows ) )
                    )
                ),

                # Bottom status bar
                row(
                    children =>
                        [ text( "Entries logged: " . scalar( @{ $model->{logs} } ) ), spacer(), text("Drag the horizontal divider to resize panes") ]
                )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
