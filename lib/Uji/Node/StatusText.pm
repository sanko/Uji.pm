use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::StatusText v0.0.1 : isa(Uji::Node) {
    field $label : param : reader = '';
    field $align : param : reader = 'left';    # 'left' | 'center' | 'right'
    sub _type                   {'status_text'}
    method _mount_only_props () { ['align'] }
};
1;
