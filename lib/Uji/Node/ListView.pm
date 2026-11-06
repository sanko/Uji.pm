use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ListView v0.0.1 : isa(Uji::Node) {
    field $columns        : param : reader = [];    # [ { id => '...', text => '...', width => 100, align => 'left', type => 'text', editable => 1 } ]
    field $rows           : param : reader = [];    # [ { col_id => 'val', checked => 1 } ] or [ [ 'val1', 'val2' ] ]
    field $selected       : param : reader = -1;    # integer or arrayref of selected indices
    field $on_select      : param : reader = undef; # sub ($index, $row) OR sub ($indices, $rows)
    field $on_activate    : param : reader = undef; # sub ($index, $row) on double-click or Enter
    field $on_check       : param : reader = undef; # sub ($index, $row, $checked) on row checkbox toggle
    field $on_sort        : param : reader = undef; # sub ($column_id, $direction) { ... }
    field $sort_column    : param : reader = undef; # column id currently sorted by
    field $sort_direction : param : reader = 'asc'; # 'asc' or 'desc'
    field $multiselect    : param : reader = 0;     # 0 = single-select, 1 = multi-select
    field $checkboxes     : param : reader = 0;     # enable native row checkboxes
    field $context_menu   : param : reader = undef; # menu(...) or sub ($indices, $rows) { menu(...) }
    field $gridlines      : param : reader = 1;
    field $full_row_select : param : reader = 1;
    field $column_reorder  : param : reader = 1;
    field $scroll_to_row   : param : reader = -1;    # integer row index to jump to

    # Virtual Mode & In-Place Editing
    field $virtual   : param : reader = 0;           # 1 = LVS_OWNERDATA virtualized rows
    field $row_count : param : reader = undef;       # total virtual rows count (defaults to scalar(@$rows))
    field $on_row    : param : reader = undef;       # sub ($row_idx) -> returns row hashref or arrayref on demand
    field $on_edit   : param : reader = undef;       # sub ($row_idx, $col_id, $new_text) on commit

    # VDOM nodes are snapshots: shallow clone rows/columns so in-place mutations don't hide diffs
    ADJUST {
        $columns = [ map { ref $_ eq 'HASH' ? {%$_} : $_ } @{ $columns // [] } ];

        # In virtual mode with huge datasets, avoid cloning millions of rows
        $rows = [ map { ref $_ eq 'HASH' ? {%$_} : ref $_ eq 'ARRAY' ? [@$_] : $_ } @{ $rows // [] } ] unless $virtual;
    }

    method total_row_count () {
        return $row_count if defined $row_count;
        return scalar(@$rows);
    }
    sub _type {'list_view'}
};
1;
