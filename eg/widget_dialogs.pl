use v5.40;
use utf8;    # source is UTF-8: literals like "…" are Unicode, per the utf8everywhere convention
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;
use Uji::Driver;

package main {
    my $drv = Uji::Driver::detect();    # the ONE driver: passed to Uji::app below so dialogs and the window share it

    sub init () {
        return ( { last => 'none', path => undef, pick => undef }, undef );
    }

    sub update ( $msg, $model ) {
        return ( $model, undef ) if !$msg;
        if ( $msg->{type} eq 'OPEN' ) {
            $model->{last} = 'open';
            $model->{path} = $drv->file_open_dialog(
                title       => 'Pick a file',
                filter      => 'Text files|*.txt|Perl scripts|*.pl|All files|*.*',
                default_dir => 'C:/Windows',
            );
        }
        elsif ( $msg->{type} eq 'SAVE' ) {
            $model->{last} = 'save';
            $model->{path} = $drv->file_save_dialog( title => 'Save as', filter => 'Text files|*.txt', default_name => 'untitled.txt', );
        }
        elsif ( $msg->{type} eq 'MULTI' ) {
            $model->{last} = 'multi';
            my $picks = $drv->file_open_dialog( title => 'Pick files', filter => 'All files|*.*', multi => 1 );
            $model->{path} = ref $picks ? join( '; ', @$picks ) : ( $picks // 'cancel' );
        }
        elsif ( $msg->{type} eq 'ASK' ) {
            $model->{last} = 'ask';
            $model->{path}
                = $drv->message_box( message => 'Save your changes before closing?', title => 'Demo', buttons => 'yesnocancel', icon => 'question', );
        }
        elsif ( $msg->{type} eq 'PROMPT' ) {
            $model->{last} = 'prompt';
            $model->{path} = $drv->prompt_dialog( title => 'Name', message => 'Enter a project name:', default => 'demo', ) // 'cancel';
        }
        elsif ( $msg->{type} eq 'COLOR' ) {
            $model->{last} = 'color';
            $model->{path} = $drv->color_picker( initial => '#336699' ) // 'cancel';
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji Dialogs Demo',
            w        => 460,
            h        => 300,
            centered => 1,
            child    => Uji::column(
                padding  => 16,
                spacing  => 10,
                children => [
                    Uji::text( 'Last dialog: ' . $model->{last} ),
                    Uji::text( 'Result: ' . ( $model->{path} // '—' ) ),
                    Uji::row(
                        spacing  => 8,
                        children => [
                            Uji::button( label => 'Open…',      on_click => { type => 'OPEN' } ),
                            Uji::button( label => 'Save…',      on_click => { type => 'SAVE' } ),
                            Uji::button( label => 'Open multi', on_click => { type => 'MULTI' } ),
                        ],
                    ),
                    Uji::row(
                        spacing  => 8,
                        children => [
                            Uji::button( label => 'Message box…', on_click => { type => 'ASK' } ),
                            Uji::button( label => 'Prompt…',      on_click => { type => 'PROMPT' } ),
                            Uji::button( label => 'Color…',       on_click => { type => 'COLOR' } ),
                        ],
                    ),
                ],
            ),
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view, driver => $drv )->run();
}
