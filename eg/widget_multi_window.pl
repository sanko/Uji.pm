use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;

# Two windows driven by ONE model: the controller window appends log lines (and toggles
# ping mode); the viewer window renders the growing log. Clicking in either window updates
# the shared model, and both windows re-render from the same view() call.
#
#   perl -Ilib eg/widget_multi_window.pl
package main {

    sub init () {
        return ( { log => [], pinging => 0 }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'ADD_LINE' ) {
            push @{ $model->{log} }, "line " . ( @{ $model->{log} } + 1 );
        }
        elsif ( $msg->{type} eq 'CLEAR' ) {
            $model->{log} = [];
        }
        elsif ( $msg->{type} eq 'TOGGLE_PING' ) {
            $model->{pinging} = $model->{pinging} ? 0 : 1;
        }
        return ( $model, undef );
    }

    sub view ($model) {
        my $viewer = Uji::window(
            title    => 'Uji Multi-Window: Log viewer',
            w        => 380,
            h        => 320,
            centered => 0,
            child    => Uji::column(
                padding  => 10,
                spacing  => 8,
                children => [
                    Uji::status_text( "viewer shows " . @{ $model->{log} } . " lines" ),
                    Uji::scroll_view(
                        Uji::column( spacing => 4, padding => 4, children => [ map { Uji::text($_) } @{ $model->{log} } ] ),
                        orientation => 'vertical'
                    )
                ]
            )
        );
        my $controller = Uji::window(
            title    => 'Uji Multi-Window: Controller',
            w        => 300,
            h        => 180,
            centered => 1,
            child    => Uji::column(
                padding  => 12,
                spacing  => 10,
                children => [
                    Uji::status_text( 'pings: ' . ( $model->{pinging} ? 'ON' : 'off' ) ),
                    Uji::button( label => 'Add a log line', on_click => { type => 'ADD_LINE' } ),
                    Uji::button( label => 'Toggle ping',    on_click => { type => 'TOGGLE_PING' } ),
                    Uji::button( label => 'Clear log',      on_click => { type => 'CLEAR' } )
                ]
            )
        );
        return [ $controller, $viewer ];
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
