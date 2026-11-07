use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Separator v0.0.1 : isa(Uji::Node) {
    field $orientation : param : reader = 'horizontal';    # 'horizontal' | 'vertical'
    sub _type                   {'separator'}
    method _mount_only_props () { ['orientation'] }
};
1;
