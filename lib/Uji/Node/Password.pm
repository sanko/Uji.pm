use v5.40;
use experimental 'class';
use Uji::Node::TextInput;
class Uji::Node::Password v0.0.1 : isa(Uji::Node::TextInput) {
    field $password_char : param : reader = undef;
    sub _type {'password'}
    method _mount_only_props { [] }    # password is always single-line: multiline can never change
};
1;
