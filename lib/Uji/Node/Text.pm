use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Text v0.0.1 : isa(Uji::Node) {
    field $label : param : reader = '';
    sub _type {'text'}
};
1;
