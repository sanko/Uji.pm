use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Window v0.0.1 : isa(Uji::Node) {
    field $title     : param : reader = 'Uji Application';
    field $child     : param : reader = undef;
    field $menu_bar  : param : reader = undef;               # Uji::Node::MenuBar attached to the window frame
    field $centered  : param : reader = 0;
    field $topmost   : param : reader = 0;
    field $minimized : param : reader = 0;
    field $maximized : param : reader = 0;
    field $resizable : param : reader = 1;
    sub _type          {'window'}
    method children () { $child ? [$child] : [] }
};
1;
