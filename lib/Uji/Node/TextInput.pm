use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::TextInput v0.0.1 : isa(Uji::Node) {
    field $value       : param : reader = '';
    field $on_input    : param : reader = undef;
    field $readonly    : param : reader = 0;
    field $maxlength   : param : reader = 0;
    field $focused     : param : reader = 0;
    field $multiline   : param : reader = 0;
    field $placeholder : param : reader = undef;
    sub _type                {'text_input'}
    method _mount_only_props { $multiline ? [] : ['multiline'] }
};
1;
