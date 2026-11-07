use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Image v0.0.1 : isa(Uji::Node) {
    field $src        : param : reader = undef;       # file path or data:image/...;base64,.. URI
    field $alt        : param : reader = undef;
    field $object_fit : param : reader = 'contain';
    sub _type {'image'}
};
1;
