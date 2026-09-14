use v5.40;
use experimental 'class';
use Uji::Node::TextInput;
class Uji::Node::Password v0.0.1 : isa(Uji::Node::TextInput) {
    sub _type {'password'}
};
1;
