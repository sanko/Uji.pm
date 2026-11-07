use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ComboBox v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = '';
    field $options   : param : reader = [];
    field $on_select : param : reader = undef;
    field $on_input  : param : reader = undef;    # editable combo only
    field $editable  : param : reader = 1;
    field $focused   : param : reader = 0;
    sub _type {'combo_box'}
};
1;
