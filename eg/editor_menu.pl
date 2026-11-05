use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return ( { file_path => '', content => "Welcome to Uji Text Editor!\nTry using File -> Open or File -> New.", status => 'Ready' }, undef );
};
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    my $t = $msg->{type};
    if ( $t eq 'TEXT_INPUT' ) {
        $m->{content} = $msg->{val};
    }
    elsif ( $t eq 'MENU_NEW' ) {
        return (
            $m,
            message_box(
                title     => 'New Document',
                message   => 'Discard current document and create a new one?',
                type      => 'yes_no',
                icon      => 'question',
                on_result => sub ($choice) { { type => 'CONFIRM_NEW', choice => $choice } }
            )
        );
    }
    elsif ( $t eq 'CONFIRM_NEW' ) {
        if ( $msg->{choice} eq 'yes' ) {
            $m->{content}   = '';
            $m->{file_path} = '';
            $m->{status}    = 'New file created';
        }
    }
    elsif ( $t eq 'MENU_OPEN' ) {
        return (
            $m,
            file_open_dialog(
                title     => 'Open Text Document',
                filter    => [ 'Text Documents (*.txt)' => '*.txt', 'Perl Scripts (*.pl;*.pm)' => '*.pl;*.pm', 'All Files (*.*)' => '*.*' ],
                on_select => sub ($path) { { type => 'FILE_SELECTED', path => $path } }
            )
        );
    }
    elsif ( $t eq 'FILE_SELECTED' ) {
        my $path = $msg->{path};
        if ( open my $fh, '<:encoding(UTF-8)', $path ) {
            $m->{content}   = do { local $/; <$fh> };
            $m->{file_path} = $path;
            $m->{status}    = "Loaded: $path";
        }
        else {
            $m->{status} = "Failed to open $path: $!";
        }
    }
    elsif ( $t eq 'MENU_SAVE' ) {
        if ( $m->{file_path} ) {
            if ( open my $fh, '>:encoding(UTF-8)', $m->{file_path} ) {
                print $fh $m->{content};
                $m->{status} = "Saved to: $m->{file_path}";
            }
            return ( $m, undef );
        }
        return (
            $m,
            file_save_dialog(
                title     => 'Save Document As',
                filter    => [ 'Text Documents (*.txt)' => '*.txt', 'All Files (*.*)' => '*.*' ],
                on_select => sub ($path) { { type => 'FILE_SAVED_AS', path => $path } }
            )
        );
    }
    elsif ( $t eq 'FILE_SAVED_AS' ) {
        my $path = $msg->{path};
        if ( open my $fh, '>:encoding(UTF-8)', $path ) {
            print $fh $m->{content};
            $m->{file_path} = $path;
            $m->{status}    = "Saved: $path";
        }
    }
    elsif ( $t eq 'MENU_ABOUT' ) {
        return (
            $m,
            message_box(
                title   => 'About Uji',
                message => "Uji GUI Toolkit v0.0.1\nBuilt on Perl 5.40, Affix FFI, and Acme::Parataxis fibers.",
                type    => 'ok',
                icon    => 'info'
            )
        );
    }
    return ( $m, undef );
};
my $view = sub ($model) {
    window(
        title    => 'Uji Text Editor & Native Dialogs',
        w        => 580,
        h        => 440,
        centered => 1,
        menu_bar => menu_bar(
            menus => [
                menu(
                    label => 'File',
                    items => [
                        menu_item( label => 'New',     on_click => { type => 'MENU_NEW' },  shortcut => 'Ctrl+N' ),
                        menu_item( label => 'Open...', on_click => { type => 'MENU_OPEN' }, shortcut => 'Ctrl+O' ),
                        menu_item( label => 'Save',    on_click => { type => 'MENU_SAVE' }, shortcut => 'Ctrl+S' ),
                        menu_separator(),
                        menu_item( label => 'Exit', on_click => { type => 'QUIT' } )
                    ]
                ),
                menu( label => 'Help', items => [ menu_item( label => 'About Uji...', on_click => { type => 'MENU_ABOUT' } ) ] )
            ]
        ),
        child => column(
            padding  => 12,
            spacing  => 8,
            children => [
                row(
                    children => [
                        text( $model->{file_path} ? "File: $model->{file_path}" : "Untitled Document" ),
                        spacer(),
                        button( label => 'Open', on_click => { type => 'MENU_OPEN' } ),
                        button( label => 'Save', on_click => { type => 'MENU_SAVE' } )
                    ]
                ),
                multiline_text( value => $model->{content}, on_input => sub ($v) { { type => 'TEXT_INPUT', val => $v } }, flex => 1 ),
                row( children => [ text("Status: $model->{status}"), spacer(), text( "Length: " . length( $model->{content} ) . " chars" ) ] )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
