use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Menu v0.0.1 : isa(Uji::Node) {
    field $label : param : reader = '';
    field $items : param : reader = [];
    sub _type          {'menu'}
    method children () {$items}
};
1;
