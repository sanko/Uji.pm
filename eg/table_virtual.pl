use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];

# Generate or read 100,000 virtual rows on demand
my $TOTAL_ROWS = 100_000;
my %edited_overrides;    # tracks edited cell values in-place
my $init = sub () {
    return (
        { total_items => $TOTAL_ROWS, selected => -1, status_text => "100,000 virtual rows loaded instantly. Click Column 0 or press F2 to edit." },
        undef );
};
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    my $t = $msg->{type};
    if ( $t eq 'SELECT' ) {
        $m->{selected}    = $msg->{idx};
        $m->{status_text} = sprintf( "Selected row index #%d", $msg->{idx} );
    }
    elsif ( $t eq 'EDIT_CELL' ) {
        my ( $row_idx, $col_id, $new_text ) = ( $msg->{row}, $msg->{col}, $msg->{val} );
        $edited_overrides{$row_idx} = $new_text;
        $m->{status_text} = sprintf( "Edited row #%d [%s] -> '%s'", $row_idx, $col_id, $new_text );
    }
    return ( $m, undef );
};

# Virtual row generator: computes cell values on the fly for visible viewport rows
my $get_virtual_row = sub ($idx) {
    my $name   = $edited_overrides{$idx} // sprintf( "Task_Item_%06d.dat", $idx + 1 );
    my $status = ( $idx % 5 == 0 ) ? 'Running' : ( $idx % 3 == 0 ) ? 'Idle' : 'Active';
    my $pct    = ( $idx * 7 ) % 101;
    return { id => $idx + 1, name => $name, progress => $pct, status => $status };
};
my $view = sub ($model) {
    window(
        title    => 'Uji 100,000 Virtual Rows & In-Place Editing Table Demo',
        w        => 680,
        h        => 520,
        centered => 1,
        child    => column(
            padding  => 12,
            spacing  => 8,
            children => [
                row(
                    children =>
                        [ text("Virtual Table Dataset: $model->{total_items} items"), spacer(), text("In-place edit: Double-click Task Name") ]
                ),

                # Virtualized ListView with editable Task Name column
                list_view(
                    flex      => 1,
                    virtual   => 1,
                    row_count => $model->{total_items},
                    on_row    => $get_virtual_row,
                    selected  => $model->{selected},
                    on_select => sub ( $idx,   $row ) { { type => 'SELECT', idx => $idx } },
                    on_edit   => sub ( $r_idx, $col_id, $new_txt ) {
                        { type => 'EDIT_CELL', row => $r_idx, col => $col_id, val => $new_txt }
                    },
                    columns => [
                        { id => 'id',       text => 'Index',     width => 90,  align => 'right' },
                        { id => 'name',     text => 'Task Name', width => 240, align => 'left',   editable => 1 },
                        { id => 'progress', text => 'Progress',  width => 140, align => 'center', type     => 'progress_bar' },
                        { id => 'status',   text => 'Status',    width => 110, align => 'center', type     => 'badge' }
                    ]
                ),
                row( children => [ text( $model->{status_text} ) ] )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
