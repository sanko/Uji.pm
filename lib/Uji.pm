use v5.40;
use experimental 'class';

package Uji v0.0.1 {
    use Uji::Node;
    use Uji::Node::Button;
    use Uji::Node::Calendar;
    use Uji::Node::Canvas;
    use Uji::Node::Checkbox;
    use Uji::Node::ColorButton;
    use Uji::Node::Column;
    use Uji::Node::ComboBox;
    use Uji::Node::DatePicker;
    use Uji::Node::GroupBox;
    use Uji::Node::Image;
    use Uji::Node::LinkButton;
    use Uji::Node::ListBox;
    use Uji::Node::ListView;
    use Uji::Node::MenuBar;
    use Uji::Node::MultilineText;
    use Uji::Node::Overlay;
    use Uji::Node::Password;
    use Uji::Node::ProgressBar;
    use Uji::Node::Radio;
    use Uji::Node::RadioGroup;
    use Uji::Node::Row;
    use Uji::Node::ScrollView;
    use Uji::Node::SearchInput;
    use Uji::Node::Separator;
    use Uji::Node::Slider;
    use Uji::Node::Spacer;
    use Uji::Node::SpinBox;
    use Uji::Node::Spinner;
    use Uji::Node::SplitView;
    use Uji::Node::StatusBar;
    use Uji::Node::StatusText;
    use Uji::Node::TabPanel;
    use Uji::Node::Text;
    use Uji::Node::TextInput;
    use Uji::Node::ToggleButton;
    use Uji::Node::ToggleSwitch;
    use Uji::Node::Toolbar;
    use Uji::Node::TreeView;
    use Uji::Node::Window;
    #
    use Uji::Layout;
    use Uji::Driver;
    use Uji::Reconciler;
    use Uji::App;
    use Uji::Cmd;
    use Uji::Sub qw[
        sub_interval sub_on_resize sub_on_focus sub_on_blur
        sub_on_close_request sub_on_key sub_on_key_chord
    ];
    use Exporter qw[import];
    our %EXPORT_TAGS = (
        all => [
            our @EXPORT
                = qw[
                app window column row text button text_input password
                multiline_text slider spin_box progress_bar toggle_switch
                toggle_button link_button checkbox radio_group combo_box
                list_box list_view status_text status_bar group_box
                scroll_view split_view tab_panel tree_view toolbar menu_bar
                spacer separator spinner date_picker search_input calendar
                overlay image canvas color_button
                sub_interval sub_on_resize sub_on_focus sub_on_blur
                sub_on_close_request sub_on_key sub_on_key_chord
                message_box file_open_dialog file_save_dialog task
                ]
        ]
    );

    # Runtime and top-level containers
    sub app    (%args) { Uji::App->new(%args) }
    sub window (%args) { Uji::Node::Window->new(%args) }
    sub column (%args) { Uji::Node::Column->new(%args) }
    sub row    (%args) { Uji::Node::Row->new(%args) }

    # Core controls
    sub text           ( $label, %args ) { Uji::Node::Text->new( label => $label, %args ) }
    sub button         (%args)           { Uji::Node::Button->new(%args) }
    sub text_input     (%args)           { Uji::Node::TextInput->new(%args) }
    sub password       (%args)           { Uji::Node::Password->new(%args) }
    sub multiline_text (%args)           { Uji::Node::MultilineText->new(%args) }
    sub slider         (%args)           { Uji::Node::Slider->new(%args) }
    sub spin_box       (%args)           { Uji::Node::SpinBox->new(%args) }
    sub progress_bar   (%args)           { Uji::Node::ProgressBar->new(%args) }
    sub checkbox       (%args)           { Uji::Node::Checkbox->new(%args) }
    sub radio_group    (%args)           { Uji::Node::RadioGroup->new(%args) }
    sub combo_box      (%args)           { Uji::Node::ComboBox->new(%args) }
    sub list_box       (%args)           { Uji::Node::ListBox->new(%args) }
    sub list_view      (%args)           { Uji::Node::ListView->new(%args) }

    # Toggle & Action buttons
    sub toggle_switch (%args) { Uji::Node::ToggleSwitch->new(%args) }
    sub toggle_button (%args) { Uji::Node::ToggleButton->new(%args) }
    sub link_button   (%args) { Uji::Node::LinkButton->new(%args) }
    sub color_button  (%args) { Uji::Node::ColorButton->new(%args) }

    # Layout primitives
    sub spacer    (%args) { Uji::Node::Spacer->new(%args) }
    sub separator (%args) { Uji::Node::Separator->new(%args) }
    sub overlay   (%args) { Uji::Node::Overlay->new(%args) }

    # Graphical & Visual widgets
    sub spinner      (%args) { Uji::Node::Spinner->new(%args) }
    sub image        (%args) { Uji::Node::Image->new(%args) }
    sub canvas       (%args) { Uji::Node::Canvas->new(%args) }
    sub search_input (%args) { Uji::Node::SearchInput->new(%args) }
    sub calendar     (%args) { my $n = Uji::Node::Calendar->new(%args); $n->_build; return $n; }

    # Navigation & Structural containers
    sub status_text ( $label, %args ) { Uji::Node::StatusText->new( label => $label, %args ) }
    sub status_bar  (%args)           { Uji::Node::StatusBar->new(%args) }
    sub group_box   (%args)           { Uji::Node::GroupBox->new(%args) }
    sub tab_panel   (%args)           { Uji::Node::TabPanel->new(%args) }
    sub tree_view   (%args)           { Uji::Node::TreeView->new(%args) }
    sub toolbar     (%args)           { Uji::Node::Toolbar->new(%args) }
    sub menu_bar    (%args)           { Uji::Node::MenuBar->new(%args) }
    sub date_picker (%args)           { Uji::Node::DatePicker->new(%args) }

    # Flexible scroll_view: accepts positional child or named arguments
    sub scroll_view ( $first, @rest ) {
        if ( ref $first && $first->isa('Uji::Node') ) {
            return Uji::Node::ScrollView->new( child => $first, @rest );
        }
        return Uji::Node::ScrollView->new( $first, @rest );
    }

    # Flexible split_view: accepts positional panes ($a, $b) or named arguments
    sub split_view ( $first, @rest ) {
        if ( ref $first && $first->isa('Uji::Node') && @rest && ref $rest[0] && $rest[0]->isa('Uji::Node') ) {
            my $second = shift @rest;
            return Uji::Node::SplitView->new( children => [ $first, $second ], @rest );
        }
        return Uji::Node::SplitView->new( $first, @rest );
    }

    # Side-effects / Cmds
    sub message_box      (%args)              { Uji::Cmd::message_box(%args) }
    sub file_open_dialog (%args)              { Uji::Cmd::file_open_dialog(%args) }
    sub file_save_dialog (%args)              { Uji::Cmd::file_save_dialog(%args) }
    sub task             ( $fn, $cb = undef ) { Uji::Cmd::task( $fn, $cb ) }
};
1;
