use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ListView v0.0.1 : isa(Uji::Node) {
    field $value           : param : reader = undef;
    field $columns         : param : reader = [];
    field $rows            : param : reader = [];
    field $on_select       : param : reader = undef;
    field $multiple        : param : reader = 0;
    field $full_row_select : param : reader = 0;
    field $grid_lines      : param : reader = 0;
    field $header          : param : reader = 1;
    method _mount_only_props { [ 'multiple', 'full_row_select', 'grid_lines', 'header' ] }
    sub _type {'list_view'}
};
1;