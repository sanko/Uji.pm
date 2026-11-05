use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::DatePicker v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = '';      # YYYY-MM-DD
    field $on_change : param : reader = undef;
    field $focused   : param : reader = 0;
    sub _type {'date_picker'}
};
1;
