use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return ( { progress => 35, max_progress => 100, min_progress => -100, indeterminate => 0, notifications => 1, sound => 0, log_level => 'info' },
        undef );
};
sub _max( $a, $b ) { $a > $b ? $a : $b }
sub _min( $a, $b ) { $a < $b ? $a : $b }
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    my $t = $msg->{type};
    if    ( $t eq 'INC' )          { $m->{progress}      = _min $m->{progress} + 10, $m->{max_progress} }
    elsif ( $t eq 'DEC' )          { $m->{progress}      = _max $m->{progress} - 10, $m->{min_progress} }
    elsif ( $t eq 'TOGGLE_BUSY' )  { $m->{indeterminate} = !$m->{indeterminate}; }
    elsif ( $t eq 'TOGGLE_NOTIF' ) { $m->{notifications} = $msg->{val}; }
    elsif ( $t eq 'TOGGLE_SOUND' ) { $m->{sound}         = $msg->{val}; }
    elsif ( $t eq 'SET_LOG' )      { $m->{log_level}     = $msg->{val}; }
    return ( $m, undef );
};
my $view = sub ($model) {
    window(
        title    => 'Uji GroupBox & ProgressBar Demo',
        w        => 500,
        centered => 1,
        child    => column(
            padding  => 16,
            spacing  => 14,
            children => [

                # Section 1: Progress group
                group_box(
                    label => 'Task Progress',
                    child => column(
                        padding  => 0,    # group_box already supplies 12px frame padding
                        spacing  => 10,
                        children => [
                            progress_bar(
                                value         => $model->{progress},
                                min           => $model->{min_progress},
                                max           => $model->{max_progress},
                                indeterminate => $model->{indeterminate}
                            ),
                            row(
                                spacing  => 8,
                                children => [
                                    button( label => '-10%', on_click => { type => 'DEC' } ),
                                    button( label => '+10%', on_click => { type => 'INC' } ),
                                    button(
                                        label    => ( $model->{indeterminate} ? 'Stop Marquee' : 'Start Marquee' ),
                                        on_click => { type => 'TOGGLE_BUSY' }
                                    ),
                                    spacer(),
                                    text( $model->{indeterminate} ? 'Working...' : "$model->{progress}% complete" )
                                ]
                            )
                        ]
                    )
                ),

                # Section 2: Preferences group
                group_box(
                    label => 'Preferences',
                    child => column(
                        padding  => 0,
                        spacing  => 8,
                        children => [
                            checkbox(
                                label     => 'Enable notifications',
                                checked   => $model->{notifications},
                                on_toggle => sub ($v) { { type => 'TOGGLE_NOTIF', val => $v } }
                            ),
                            checkbox(
                                label     => 'Play sound effects',
                                checked   => $model->{sound},
                                on_toggle => sub ($v) { { type => 'TOGGLE_SOUND', val => $v } }
                            ),
                            row(
                                spacing  => 8,
                                children => [
                                    text('Logging:'),
                                    combo_box(
                                        value   => $model->{log_level},
                                        options => [
                                            { value => 'debug', label => 'Debug' },
                                            { value => 'info',  label => 'Info' },
                                            { value => 'warn',  label => 'Warning' },
                                            { value => 'error', label => 'Error' }
                                        ],
                                        on_select => sub ($v) { { type => 'SET_LOG', val => $v } }
                                    )
                                ]
                            )
                        ]
                    )
                )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
