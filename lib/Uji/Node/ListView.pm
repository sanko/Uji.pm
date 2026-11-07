use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ListView v0.0.1 : isa(Uji::Node) {
    field $value   : param : reader = undef;
    field $columns : param : reader = [];      # [ { id => '...', text => '...', width => 100, align => 'left', type => 'text', editable => 1 } ]
    field $rows    : param : reader = [];      # [ { col_id => 'val', checked => 1 } ] or [ [ 'val1', 'val2' ] ]

    #
    field $on_select   : param : reader = undef;    # sub ($index, $row) OR sub ($indices, $rows)
    field $on_sort     : param : reader = undef;    # sub ($column_id, $direction) { ... }
    field $on_reorder  : param : reader = undef;
    field $on_activate : param : reader = undef;    # sub ($index, $row) on double-click or Enter
    field $on_check    : param : reader = undef;    # sub ($index, $row, $checked) on row checkbox toggle

    #
    field $multiple        : param : reader = 0;        # 0 = single-select, 1 = multi-select
    field $full_row_select : param : reader = 1;
    field $grid_lines      : param : reader = 1;
    field $grid_color      : param : reader = undef;    # '#RRGGBB' custom gridline color
    field $header          : param : reader = 1;
    field $sortable        : param : reader = 0;
    field $reorderable     : param : reader = 0;
    #
    method _mount_only_props () {
        return [ 'multiple', 'full_row_select', 'grid_lines', 'header', 'sortable', 'reorderable' ];
    }
    sub _type {'list_view'}
};
1;
