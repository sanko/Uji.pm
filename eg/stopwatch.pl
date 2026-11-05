use v5.40;
use lib 'lib';
use blib;
use Uji         qw[:all];
use Time::HiRes qw[time];
my $init = sub () {
    return ( { start_epoch => undef, elapsed_ms => 0, running => 0, laps => [] }, undef );
};
my $update = sub ( $msg, $model ) {
    my $m = { %$model, laps => [ @{ $model->{laps} } ] };
    my $t = $msg->{type};
    if ( $t eq 'TICK' ) {
        if ( $m->{running} && defined $m->{start_epoch} ) {
            $m->{elapsed_ms} = int( ( time() - $m->{start_epoch} ) * 1000 );
        }
    }
    elsif ( $t eq 'TOGGLE' ) {
        $m->{running} = !$m->{running};
        if ( $m->{running} ) {

            # Start/resume: offset start_epoch so elapsed_ms continues smoothly
            $m->{start_epoch} //= time() - ( $m->{elapsed_ms} / 1000 );
        }
        else {
            $m->{start_epoch} = undef;
        }
    }
    elsif ( $t eq 'RESET' ) {
        $m->{elapsed_ms}  = 0;
        $m->{start_epoch} = undef;
        $m->{running}     = 0;
        $m->{laps}        = [];
    }
    elsif ( $t eq 'LAP' ) {
        my $formatted = sprintf( '%02d:%02d.%02d',
            int( $m->{elapsed_ms} / 60000 ),
            int( ( $m->{elapsed_ms} % 60000 ) / 1000 ),
            int( ( $m->{elapsed_ms} % 1000 ) / 10 ) );
        push @{ $m->{laps} }, { id => scalar( @{ $m->{laps} } ) + 1, time => $formatted };
    }
    return ( $m, undef );
};

# Declarative Subscriptions:
# Only tick when $model->{running} is true! When false, runtime cancels the fiber.
my $subscriptions = sub ($model) {
    return $model->{running} ? every( 50, sub { { type => 'TICK' } }, key => 'stopwatch_timer' ) : none();
};
my $view = sub ($model) {
    my $minutes    = int( $model->{elapsed_ms} / 60000 );
    my $seconds    = int( ( $model->{elapsed_ms} % 60000 ) / 1000 );
    my $hundredths = int( ( $model->{elapsed_ms} % 1000 ) / 10 );
    my $time_str   = sprintf( '%02d:%02d.%02d', $minutes, $seconds, $hundredths );

    # Progress bar animates across each second (0..1000ms)
    my $sec_progress = int( ( ( $model->{elapsed_ms} % 1000 ) / 1000 ) * 100 );
    my @lap_rows;
    for my $lap ( reverse @{ $model->{laps} } ) {
        push @lap_rows,
            row( key => "lap-$lap->{id}", spacing => 8, children => [ text( sprintf( 'Lap #%02d', $lap->{id} ) ), spacer(), text( $lap->{time} ) ] );
    }
    window(
        title    => 'Uji Subscriptions & Stopwatch Demo',
        w        => 460,
        h        => 420,
        centered => 1,
        child    => column(
            padding  => 16,
            spacing  => 12,
            children => [

                # Timer display box
                group_box(
                    label => 'Stopwatch Timer',
                    child => column(
                        padding  => 0,
                        spacing  => 10,
                        children => [
                            row( children => [ spacer(), text($time_str), spacer() ] ),
                            progress_bar( value => $sec_progress, min => 0, max => 100, flex => 1 )
                        ]
                    )
                ),

                # Controls
                row(
                    spacing  => 10,
                    children => [
                        button( label => ( $model->{running} ? 'Pause' : 'Start' ), on_click => { type => 'TOGGLE' }, flex => 1 ),
                        button( label => 'Lap',   enabled  => $model->{running}, on_click => { type => 'LAP' }, flex => 1 ),
                        button( label => 'Reset', on_click => { type => 'RESET' }, flex => 1 )
                    ]
                ),

                # Laps table embedded in native clipped scroll_view
                text('Recorded Laps:'),
                scroll_view( flex => 1, child => column( padding => 6, spacing => 4, children => \@lap_rows ) )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view, subscriptions => $subscriptions )->run();
