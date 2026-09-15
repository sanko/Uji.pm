use v5.40;
use experimental 'class';
use Uji::Node::TextInput;
class Uji::Node::MultilineText v0.0.1 : isa(Uji::Node::TextInput) {

    # A text input whose multiline is always on. multiline is NOT a :param here, it's a fixed
    # constant shadowing the parent's reader (the field value in TextInput is unused for us).
    # Mount-only prop set is empty: `multiline` can never change on this node type.
    method multiline {1}
    method _mount_only_props { [] }
    sub _type {'multiline_text'}
};
1;
