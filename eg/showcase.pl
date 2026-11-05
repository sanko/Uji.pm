use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return (
        {   count      => 42,
            slider_val => 42,
            text_val   => 'Hello Perl 5.40',
            password   => 'secret',
            checked    => 1,
            switched   => 0,
            combo_val  => 'apple',
            list_val   => 'perl',
            radio_val  => 'light',
            date_val   => '2026-11-05'
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    my $t = $msg->{type};
    if    ( $t eq 'INC' )          { $m->{count}++; $m->{slider_val} = $m->{count}; }
    elsif ( $t eq 'DEC' )          { $m->{count}--; $m->{slider_val} = $m->{count}; }
    elsif ( $t eq 'SPIN' )         { $m->{count}      = $msg->{val}; $m->{slider_val} = $msg->{val}; }
    elsif ( $t eq 'SLIDE' )        { $m->{slider_val} = $msg->{val}; $m->{count}      = $msg->{val}; }
    elsif ( $t eq 'TEXT' )         { $m->{text_val}   = $msg->{val}; }
    elsif ( $t eq 'PASS' )         { $m->{password}   = $msg->{val}; }
    elsif ( $t eq 'TOGGLE_CHK' )   { $m->{checked}    = $msg->{val}; }
    elsif ( $t eq 'TOGGLE_SW' )    { $m->{switched}   = $msg->{val}; }
    elsif ( $t eq 'SELECT_COMBO' ) { $m->{combo_val}  = $msg->{val}; }
    elsif ( $t eq 'SELECT_LIST' )  { $m->{list_val}   = $msg->{val}; }
    elsif ( $t eq 'SELECT_RADIO' ) { $m->{radio_val}  = $msg->{val}; }
    elsif ( $t eq 'DATE_CHANGE' )  { $m->{date_val}   = $msg->{val}; }
    return ( $m, undef );
};
my $view = sub ($model) {
    window(
        title    => 'Uji Controls Showcase',
        w        => 640,
        h        => 580,
        centered => 1,
        child    => column(
            padding  => 14,
            spacing  => 10,
            children => [
                row(
                    spacing  => 8,
                    children => [
                        button( label => '-1', on_click => { type => 'DEC' } ),
                        button( label => '+1', on_click => { type => 'INC' } ),
                        spin_box( value => $model->{count}, min => 0, max => 100, on_change => sub ($v) { { type => 'SPIN', val => $v } } ),
                        slider(
                            value     => $model->{slider_val},
                            min       => 0,
                            max       => 100,
                            step      => 1,
                            on_change => sub ($v) { { type => 'SLIDE', val => $v } },
                            flex      => 1
                        ),
                        text("Value: $model->{count}")
                    ]
                ),
                row(
                    spacing  => 8,
                    children => [
                        text_input( value => $model->{text_val}, on_input => sub ($v) { { type => 'TEXT', val => $v } }, flex => 1 ),
                        password( value => $model->{password}, on_input => sub ($v) { { type => 'PASS', val => $v } }, flex => 1 )
                    ]
                ),
                row(
                    spacing  => 12,
                    children => [
                        checkbox(
                            label     => 'Checkbox feature',
                            checked   => $model->{checked},
                            on_toggle => sub ($v) { { type => 'TOGGLE_CHK', val => $v } }
                        ),
                        toggle_switch(
                            label     => 'Toggle switch',
                            checked   => $model->{switched},
                            on_toggle => sub ($v) { { type => 'TOGGLE_SW', val => $v } }
                        ),
                        date_picker( value => $model->{date_val}, on_change => sub ($v) { { type => 'DATE_CHANGE', val => $v } } )
                    ]
                ),
                row(
                    spacing  => 12,
                    children => [
                        combo_box(
                            value   => $model->{combo_val},
                            options => [
                                { value => 'apple',  label => 'Apple' },
                                { value => 'banana', label => 'Banana' },
                                { value => 'cherry', label => 'Cherry' }
                            ],
                            on_select => sub ($v) { { type => 'SELECT_COMBO', val => $v } }
                        ),
                        list_box(
                            selection => $model->{list_val},
                            rows      => 3,
                            options   => [
                                { value => 'c',      label => 'C Language' },
                                { value => 'perl',   label => 'Perl 5.40' },
                                { value => 'python', label => 'Python' }
                            ],
                            on_select => sub ($v) { { type => 'SELECT_LIST', val => $v } }
                        ),
                        radio_group(
                            value   => $model->{radio_val},
                            options => [
                                { value => 'light',  label => 'Light Mode' },
                                { value => 'dark',   label => 'Dark Mode' },
                                { value => 'system', label => 'System' }
                            ],
                            on_select => sub ($v) { { type => 'SELECT_RADIO', val => $v } }
                        )
                    ]
                ),
                text("Summary: radio=$model->{radio_val}, combo=$model->{combo_val}, list=$model->{list_val}, date=$model->{date_val}")
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
