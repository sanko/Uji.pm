use v5.40;
use experimental 'class';

package Uji v0.0.1 {
    use Uji::Node;
    use Uji::Node::Button;
    use Uji::Node::Checkbox;
    use Uji::Node::Column;
    use Uji::Node::Password;
    use Uji::Node::Radio;
    use Uji::Node::RadioGroup;
    use Uji::Node::Row;
    use Uji::Node::Slider;
    use Uji::Node::Text;
    use Uji::Node::TextInput;
    use Uji::Node::Window;
    use Uji::Layout;
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::App;
    use Exporter qw[import];
    our @EXPORT = qw[app window column row text button text_input password slider checkbox radio_group];
    sub app         (%args)           { Uji::App->new(%args) }
    sub window      (%args)           { Uji::Node::Window->new(%args) }
    sub column      (%args)           { Uji::Node::Column->new(%args) }
    sub row         (%args)           { Uji::Node::Row->new(%args) }
    sub text        ( $label, %args ) { Uji::Node::Text->new( label => $label, %args ) }
    sub button      (%args)           { Uji::Node::Button->new(%args) }
    sub text_input  (%args)           { Uji::Node::TextInput->new(%args) }
    sub password    (%args)           { Uji::Node::Password->new(%args) }
    sub slider      (%args)           { Uji::Node::Slider->new(%args) }
    sub checkbox    (%args)           { Uji::Node::Checkbox->new(%args) }
    sub radio_group (%args)           { Uji::Node::RadioGroup->new(%args) }
};
1;
