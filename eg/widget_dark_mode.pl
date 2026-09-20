use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;
use Uji::Driver::Win32;

# Light/dark mode demo.
#
#   perl eg/widget_dark_mode.pl             follow the Windows theme (auto)
#   perl eg/widget_dark_mode.pl dark        pin dark  (driver dark_mode => 1)
#   perl eg/widget_dark_mode.pl light       pin light (driver dark_mode => 0)
#
# "auto" probes HKCU\...\Themes\Personalize\AppsUseLightTheme through the driver;
# the pinned modes force the driver's uses_dark_mode without reading the registry.
# The boot-time scheme drives:
#   - the immersive dark title bar + frame (DwmSetWindowAttribute, driver _frame_dark)
#   - the window background brush (near-black in dark, COLOR_WINDOW in light)
# The controls below are a schema of the WM_CTLCOLOR recolor path every model change
# uses: hit the preview button to flip between the two palettes AT RUNTIME (the frame
# stays at the boot scheme -- only the control colours are live).
package main {
    my $mode = lc( $ARGV[0] // 'auto' );
    $mode = 'auto' unless $mode =~ /^(auto|dark|light)$/;
    my $drv
        = $mode eq 'dark' ? Uji::Driver::Win32->new( dark_mode => 1 ) :
        $mode eq 'light'  ? Uji::Driver::Win32->new( dark_mode => 0 ) :
        Uji::Driver::Win32->new;
    my $scheme   = $drv->uses_dark_mode ? 'dark' : 'light';
    my %palettes = (
        dark  => { panel => '#2D2D30', fg => '#E6E6E6', accent => '#5CA8FF', muted => '#9E9E9E' },
        light => { panel => '#F5F5F5', fg => '#1E1E1E', accent => '#1E6FEB', muted => '#666666' }
    );

    sub init () {
        return ( { mode => $mode, scheme => $scheme, preview => 0, name => '', agree => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if    ( $msg->{type} eq 'SET_NAME' )       { $model->{name}    = $msg->{value} }
        elsif ( $msg->{type} eq 'TOGGLE_AGREE' )   { $model->{agree}   = $msg->{value} ? 1 : 0 }
        elsif ( $msg->{type} eq 'TOGGLE_PREVIEW' ) { $model->{preview} = $model->{preview} ? 0 : 1 }
        return ( $model, undef );
    }

    sub view ($model) {
        my $use   = $model->{scheme};
        my $pal   = $model->{preview}        ? $palettes{ $use eq 'dark' ? 'light' : 'dark' } : $palettes{$use};
        my $show  = $model->{preview}        ? ( $use eq 'dark' ? 'light' : 'dark' )          : $use;
        my $label = $model->{preview}        ? 'Back to ' . $use . ' palette'  : 'Preview ' . ( $use eq 'dark' ? 'light' : 'dark' ) . ' palette';
        my $src   = $model->{mode} eq 'auto' ? 'from the Windows theme (auto)' : "pinned by --mode";
        return Uji::window(
            title    => 'Uji Light/Dark — ' . $use . " ($mode)",
            w        => 460,
            h        => 430,
            centered => 1,
            child    => Uji::column(
                padding  => 16,
                spacing  => 12,
                children => [
                    Uji::text( 'Active scheme: ' . $use . '  —  ' . $src,                                                   color => $pal->{accent} ),
                    Uji::text( 'The driver paints every unthemed control dark in dark mode (labels, inputs, lists);',       color => $pal->{muted} ),
                    Uji::text( 'the widgets below that carry no colour prove it. The rest are themed explicitly and live.', color => $pal->{muted} ),
                    Uji::row(
                        spacing  => 10,
                        children => [ Uji::text_input(), Uji::text_input( value => 'no colours ', placeholder => 'placeholder' ), ]
                    ),
                    Uji::row( spacing => 10, children => [ Uji::text('Default label'), Uji::checkbox( label => 'Default checkbox' ), ] ),
                    Uji::text_input(
                        value       => $model->{name} // '',
                        placeholder => 'Themed: type here',
                        color       => $pal->{fg},
                        background  => $pal->{panel},
                        on_input    => sub ($t) { { type => 'SET_NAME', value => $t } }
                    ),
                    Uji::checkbox(
                        label      => 'Themed: remember me',
                        checked    => $model->{agree},
                        color      => $pal->{fg},
                        background => $pal->{panel},
                        on_toggle  => sub ($on) { { type => 'TOGGLE_AGREE', value => $on } }
                    ),
                    Uji::row(
                        spacing  => 10,
                        children => [
                            Uji::button( label => $label, on_click => { type => 'TOGGLE_PREVIEW' } ),
                            Uji::text( 'Accent colour', color => $pal->{accent}, background => $pal->{panel} ),
                        ]
                    ),
                    Uji::separator(),
                    Uji::text(
                        'Controls are showing the ' . $show . ' palette now. Push buttons stay native: CTLCOLORBTN is not sent for them.',
                        color => $pal->{muted}
                    ),
                ]
            ),
        );
    }
    Uji::app( driver => $drv, init => \&init, update => \&update, view => \&view )->run();
}
