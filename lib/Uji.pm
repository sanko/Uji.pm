use v5.40;
use experimental 'class';
#
package Uji v0.0.1 {
    use Exporter qw[import];
    #
    use Uji::App;
    use Uji::Cmd;
    use Uji::Driver;
    use Uji::Layout;
    use Uji::Reconciler;
    use Uji::Sub;
    #
    use Uji::Node;
    use Uji::Node::Button;
    use Uji::Node::Checkbox;
    use Uji::Node::Column;
    use Uji::Node::ComboBox;
    use Uji::Node::DatePicker;
    use Uji::Node::ListBox;
    use Uji::Node::MultilineText;
    use Uji::Node::Password;
    use Uji::Node::Radio;
    use Uji::Node::RadioGroup;
    use Uji::Node::Row;
    use Uji::Node::Slider;
    use Uji::Node::SpinBox;
    use Uji::Node::Spacer;
    use Uji::Node::Text;
    use Uji::Node::TextInput;
    use Uji::Node::ToggleSwitch;
    use Uji::Node::Window;
    use Uji::Node::ProgressBar;
    use Uji::Node::GroupBox;
    use Uji::Node::ScrollView;
    use Uji::Node::Menu;
    use Uji::Node::MenuBar;
    use Uji::Node::MenuItem;
    use Uji::Node::MenuSeparator;
    use Uji::Node::Tab;
    use Uji::Node::TabPanel;
    #
    our %EXPORT_TAGS = (
        all => [
            our @EXPORT
                = qw[
                app window  group_box scroll_view
                column row
                text   text_input password multiline_text
                button
                checkbox radio_group
                slider  progress_bar
                combo_box list_box spin_box date_picker toggle_switch spacer
                every batch none
                menu_bar menu menu_item menu_separator
                message_box file_open_dialog file_save_dialog
                tab_panel tab
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
    sub slider         (%args)           { Uji::Node::Slider->new(%args) }
    sub checkbox       (%args)           { Uji::Node::Checkbox->new(%args) }
    sub radio_group    (%args)           { Uji::Node::RadioGroup->new(%args) }
    sub multiline_text (%args)           { Uji::Node::MultilineText->new(%args) }
    sub combo_box      (%args)           { Uji::Node::ComboBox->new(%args) }
    sub list_box       (%args)           { Uji::Node::ListBox->new(%args) }
    sub spin_box       (%args)           { Uji::Node::SpinBox->new(%args) }
    sub date_picker    (%args)           { Uji::Node::DatePicker->new(%args) }
    sub toggle_switch  (%args)           { Uji::Node::ToggleSwitch->new(%args) }
    sub group_box      (%args)           { Uji::Node::GroupBox->new(%args) }
    sub progress_bar   (%args)           { Uji::Node::ProgressBar->new(%args) }
    sub scroll_view    (%args)           { Uji::Node::ScrollView->new(%args) }
    sub tab_panel      (%args)           { Uji::Node::TabPanel->new(%args) }
    sub tab            (%args)           { Uji::Node::Tab->new(%args) }

    sub spacer (%args) {
        $args{flex} //= 1 unless defined $args{w} || defined $args{h};
        Uji::Node::Spacer->new(%args);
    }

    # Subscription primitives
    sub every ( $ms, $action, %args ) { Uji::Sub::every( $ms, $action, %args ) }
    sub batch (@subs)                 { Uji::Sub::batch(@subs) }
    sub none () { Uji::Sub::none() }

    # Menus
    sub menu_bar       (%args) { Uji::Node::MenuBar->new(%args) }
    sub menu           (%args) { Uji::Node::Menu->new(%args) }
    sub menu_item      (%args) { Uji::Node::MenuItem->new(%args) }
    sub menu_separator (%args) { Uji::Node::MenuSeparator->new(%args) }

    # Commands / Dialogs
    sub message_box      (%args) { Uji::Cmd::message_box(%args) }
    sub file_open_dialog (%args) { Uji::Cmd::file_open_dialog(%args) }
    sub file_save_dialog (%args) { Uji::Cmd::file_save_dialog(%args) }
};
#
1;
