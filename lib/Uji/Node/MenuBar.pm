use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::MenuBar v0.0.1 : isa(Uji::Node) {
    field $menus : param : reader = [];
    sub _type          {'menu_bar'}
    method children () {$menus}
};
1;
