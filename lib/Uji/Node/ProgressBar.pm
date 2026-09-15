use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::ProgressBar v0.0.1 : isa(Uji::Node) {
    field $value : param : reader = 0;
    field $min   : param : reader = 0;
    field $max   : param : reader = 100;
    sub _type {'progress_bar'}
};
1;
