use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Separator v0.0.1 : isa(Uji::Node) {
    field $orientation : param : reader = 'horizontal';    # 'horizontal' (a ruled line in a column) | 'vertical' (in a row)
    sub _type {'separator'}
    method _mount_only_props () { ['orientation'] }        # etched style is baked into the STATIC at creation
};
1;