use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return ( { search => '', notes => "First line of notes\nSecond line\nThird line", status => 'Ready' }, undef );
};
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    if    ( $msg->{type} eq 'SET_SEARCH' ) { $m->{search} = $msg->{val}; $m->{status} = "Searching for: $msg->{val}"; }
    elsif ( $msg->{type} eq 'SET_NOTES' )  { $m->{notes}  = $msg->{val}; }
    elsif ( $msg->{type} eq 'SAVE' )       { $m->{status} = 'Saved notes successfully!'; }
    elsif ( $msg->{type} eq 'CANCEL' )     { $m->{status} = 'Action cancelled'; $m->{search} = ''; }
    return ( $m, undef );
};
my $view = sub ($model) {
    window(
        title    => 'Uji Layout & Constraints Demo',
        centered => 1,
        child    => column(
            padding  => 16,
            spacing  => 12,
            children => [

                # Top Toolbar: title, flexible spacer, search input clamped between 120 and 240px
                row(
                    spacing  => 10,
                    children => [
                        text('My Application'),
                        spacer(),
                        text('Search:'),
                        text_input(
                            value    => $model->{search},
                            on_input => sub ($v) { { type => 'SET_SEARCH', val => $v } },
                            flex     => 1,
                            min_w    => 120,
                            max_w    => 240
                        )
                    ]
                ),

                # Form row: label aligned to top (align_self => 'start') alongside multiline text
                row(
                    spacing  => 10,
                    children => [
                        text( 'Notes:', align_self => 'start' ),
                        multiline_text( value => $model->{notes}, rows => 5, flex => 1, on_input => sub ($v) { { type => 'SET_NOTES', val => $v } } )
                    ]
                ),

                # Dialog action row: status on left, spacer pushes actions to right
                row(
                    spacing  => 8,
                    children => [
                        text("Status: $model->{status}"),                              spacer(),
                        button( label => 'Cancel', on_click => { type => 'CANCEL' } ), button( label => 'Save', on_click => { type => 'SAVE' } )
                    ]
                )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
