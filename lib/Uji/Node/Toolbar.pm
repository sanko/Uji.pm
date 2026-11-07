use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Toolbar v0.0.1 : isa(Uji::Node) {
    field $buttons   : param : reader = [];
    field $on_click  : param : reader = undef;
    field $icon_size : param : reader = 16;
    method _mount_only_props () { ['icon_size'] }
    sub _type                   {'toolbar'}
};
1;
