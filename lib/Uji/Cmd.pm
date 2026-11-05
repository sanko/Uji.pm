use v5.40;
use experimental 'class';
class Uji::Cmd v0.0.1 {
    field $runner : param : reader;

    method run ( $channel, $driver ) {
        $runner->( $channel, $driver );
    }

    # Factory: Generic async task
    sub task ( $task_sub, $on_complete = undef ) {
        return Uji::Cmd->new(
            runner => sub ( $channel, $driver ) {
                my $res = $task_sub->();
                if ($on_complete) {
                    my $msg = $on_complete->($res);
                    $channel->put($msg) if $msg;
                }
            }
        );
    }

    # Factory: Native message box dialog
    sub message_box (%args) {
        return Uji::Cmd->new(
            runner => sub ( $channel, $driver ) {
                my $choice = $driver->show_message_box(%args);
                if ( my $cb = $args{on_result} ) {
                    my $msg = $cb->($choice);
                    $channel->put($msg) if $msg;
                }
            }
        );
    }

    # Factory: Native file open dialog
    sub file_open_dialog (%args) {
        return Uji::Cmd->new(
            runner => sub ( $channel, $driver ) {
                my $path = $driver->show_file_open_dialog(%args);
                if ( defined $path && length $path ) {
                    if ( my $cb = $args{on_select} ) {
                        my $msg = $cb->($path);
                        $channel->put($msg) if $msg;
                    }
                }
                elsif ( my $cb = $args{on_cancel} ) {
                    my $msg = $cb->();
                    $channel->put($msg) if $msg;
                }
            }
        );
    }

    # Factory: Native file save dialog
    sub file_save_dialog (%args) {
        return Uji::Cmd->new(
            runner => sub ( $channel, $driver ) {
                my $path = $driver->show_file_save_dialog(%args);
                if ( defined $path && length $path ) {
                    if ( my $cb = $args{on_select} ) {
                        my $msg = $cb->($path);
                        $channel->put($msg) if $msg;
                    }
                }
                elsif ( my $cb = $args{on_cancel} ) {
                    my $msg = $cb->();
                    $channel->put($msg) if $msg;
                }
            }
        );
    }
};
1;
