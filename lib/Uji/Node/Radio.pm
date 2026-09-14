use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Radio v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = '';
    field $label     : param : reader = '';
    field $first     : param : reader = 0;       # first in group carries WS_GROUP for exclusive selection
    field $selected  : param : reader = 0;
    field $on_select : param : reader = undef;
    sub _type {'radio'}
};
1;
