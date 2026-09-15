use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ComboBox v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = '';
    field $options   : param : reader = [];
    field $editable  : param : reader = 0;
    field $on_select : param : reader = undef;
    field $on_input  : param : reader = undef;
    sub _type {'combo_box'}
};
1;