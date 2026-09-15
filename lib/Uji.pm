use v5.40;
use experimental 'class';

package Uji v0.0.1 {
    use Uji::Node;
    use Uji::Node::Button;
    use Uji::Node::Checkbox;
    use Uji::Node::Column;
    use Uji::Node::ComboBox;
    use Uji::Node::LinkButton;
    use Uji::Node::ListBox;
    use Uji::Node::MultilineText;
    use Uji::Node::Password;
    use Uji::Node::ProgressBar;
    use Uji::Node::Radio;
    use Uji::Node::RadioGroup;
    use Uji::Node::Row;
    use Uji::Node::Slider;
    use Uji::Node::SpinBox;
    use Uji::Node::Text;
    use Uji::Node::TextInput;
    use Uji::Node::ToggleButton;
    use Uji::Node::ToggleSwitch;
    use Uji::Node::Window;
    use Uji::Layout;
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::App;
    #
    use Exporter qw[import];
    our %EXPORT_TAGS = (
        all => [
            our @EXPORT
                = qw[app window column row text button text_input password
                multiline_text slider spin_box progress_bar toggle_switch toggle_button link_button checkbox radio_group combo_box list_box
                ]
        ]
    );
    #
    sub app            (%args)           { Uji::App->new(%args) }
    sub window         (%args)           { Uji::Node::Window->new(%args) }
    sub column         (%args)           { Uji::Node::Column->new(%args) }
    sub row            (%args)           { Uji::Node::Row->new(%args) }
    sub text           ( $label, %args ) { Uji::Node::Text->new( label => $label, %args ) }
    sub button         (%args)           { Uji::Node::Button->new(%args) }
    sub text_input     (%args)           { Uji::Node::TextInput->new(%args) }
    sub password       (%args)           { Uji::Node::Password->new(%args) }
    sub multiline_text (%args)           { Uji::Node::MultilineText->new(%args) }
    sub slider         (%args)           { Uji::Node::Slider->new(%args) }
    sub spin_box       (%args)           { Uji::Node::SpinBox->new(%args) }
    sub progress_bar   (%args)           { Uji::Node::ProgressBar->new(%args) }
    sub toggle_switch  (%args)           { Uji::Node::ToggleSwitch->new(%args) }
    sub toggle_button  (%args)           { Uji::Node::ToggleButton->new(%args) }
    sub link_button    (%args)           { Uji::Node::LinkButton->new(%args) }
    sub checkbox       (%args)           { Uji::Node::Checkbox->new(%args) }
    sub radio_group    (%args)           { Uji::Node::RadioGroup->new(%args) }
    sub combo_box      (%args)           { Uji::Node::ComboBox->new(%args) }
    sub list_box       (%args)           { Uji::Node::ListBox->new(%args) }
};
1;
