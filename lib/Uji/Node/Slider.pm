use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Slider v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = 0;
    field $min       : param : reader = 0;
    field $max       : param : reader = 100;
    field $step      : param : reader = 1;
    field $on_change : param : reader = undef;
    sub _type {'slider'}
};
1;
