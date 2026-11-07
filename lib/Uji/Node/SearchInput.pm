use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::SearchInput v0.0.1 : isa(Uji::Node) {
    field $value       : param : reader = '';
    field $placeholder : param : reader = '';
    field $icon        : param : reader = '';
    field $on_input    : param : reader = undef;
    field $on_search   : param : reader = undef;
    sub _type                   {'search_input'}
    method _mount_only_props () { ['icon'] }
};
1;
