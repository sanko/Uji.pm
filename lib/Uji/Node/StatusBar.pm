use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::StatusBar v0.0.1 : isa(Uji::Node) {
    field $label  : param : reader = '';
    field $panels : param : reader = [];
    sub _type {'status_bar'}
};
1;
