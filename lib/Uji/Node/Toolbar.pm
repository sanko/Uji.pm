use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::Toolbar v0.0.1 : isa(Uji::Node) {
    field $buttons  : param : reader = [];       # [{ label => '', id => '', icon => '', separator => 0, checked => 0, enabled => 1 }]
    field $on_click : param : reader = undef;    # sub ($id) { ... }
    field $icon_size : param : reader = 16;      # image-list icon size in pixels (square)
    method _mount_only_props { ['icon_size'] }   # native image list is baked at creation
    sub _type {'toolbar'}
};
1;
