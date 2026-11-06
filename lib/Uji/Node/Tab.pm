use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Tab v0.0.1 : isa(Uji::Node) {
    field $label : param : reader = '';
    field $child : param : reader = undef;
    sub _type          {'tab'}
    method children () { $child ? [$child] : [] }
};
1;
