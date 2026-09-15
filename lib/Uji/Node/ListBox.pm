use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ListBox v0.0.1 : isa(Uji::Node) {
    field $value      : param : reader = '';
    field $options    : param : reader = [];
    field $on_select  : param : reader = undef;
    field $multiple   : param : reader = 0;
    sub _type {'list_box'}
};
1;