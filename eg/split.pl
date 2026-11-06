use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    my @files = (
        'App.pm', 'Driver.pm', 'Layout.pm', 'Node.pm',      'Reconciler.pm', 'Sub.pm',
        'Cmd.pm', 'Win32.pm',  'Button.pm', 'TextInput.pm', 'SplitView.pm',  'ScrollView.pm'
    );
    return (
        {   split_ratio   => 0.32,
            files         => \@files,
            selected_file => 'SplitView.pm',
            editor_text   => "# SplitView.pm\n# Movable two-pane container for Uji GUI.\n\nuse v5.40;\nuse experimental 'class';",
            status        => 'Ready'
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    my $t = $msg->{type};
    if ( $t eq 'SET_SPLIT' ) {
        $m->{split_ratio} = $msg->{val};
        $m->{status}      = sprintf( 'Sidebar split: %d%%', int( $msg->{val} * 100 ) );
    }
    elsif ( $t eq 'SELECT_FILE' ) {
        $m->{selected_file} = $msg->{file};
        $m->{editor_text}   = "# File: $msg->{file}\n# Loaded at split ratio $m->{split_ratio}\n";
        $m->{status}        = "Selected: $msg->{file}";
    }
    elsif ( $t eq 'TEXT_CHANGE' ) {
        $m->{editor_text} = $msg->{val};
    }
    return ( $m, undef );
};
my $view = sub ($model) {
    my @file_buttons;
    for my $f ( @{ $model->{files} } ) {
        my $is_sel = ( $f eq $model->{selected_file} );
        push @file_buttons, button( key => "file-$f", label => ( $is_sel ? "> $f" : "  $f" ), on_click => { type => 'SELECT_FILE', file => $f } );
    }
    window(
        title    => 'Uji SplitView IDE Demo',
        w        => 680,
        h        => 480,
        centered => 1,
        child    => column(
            padding  => 12,
            spacing  => 8,
            children => [

                # Top toolbar
                row(
                    spacing  => 8,
                    children => [ text('Project Explorer'), spacer(), text( "Split: " . sprintf( '%d%%', int( $model->{split_ratio} * 100 ) ) ) ]
                ),

                # Resizable Two-Pane SplitView
                split_view(
                    flex        => 1,
                    orientation => 'horizontal',
                    split       => $model->{split_ratio},
                    min_first   => 140,
                    min_second  => 220,
                    on_change   => sub ($ratio) { { type => 'SET_SPLIT', val => $ratio } },

                    # Left pane: Scrollable file list
                    first => group_box(
                        label => 'Files',
                        child => scroll_view( flex => 1, child => column( padding => 4, spacing => 4, children => \@file_buttons ) )
                    ),

                    # Right pane: Text editor
                    second => group_box(
                        label => "Editor - $model->{selected_file}",
                        child => multiline_text(
                            value    => $model->{editor_text},
                            on_input => sub ($v) { { type => 'TEXT_CHANGE', val => $v } },
                            flex     => 1
                        )
                    )
                ),

                # Bottom status bar
                row( children => [ text("Status: $model->{status}"), spacer(), text("Current: $model->{selected_file}") ] )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
