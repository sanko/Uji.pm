use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return (
        {   input   => '',
            next_id => 4,
            filter  => 'all',    # all | active | completed
            todos   => [
                { id => 1, text => 'Explore Perl 5.40 class syntax',   done => 1 },
                { id => 2, text => 'Verify keyed VDOM reconciliation', done => 0 },
                { id => 3, text => 'Build reactive native desktop UI', done => 0 }
            ]
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = { %$model, todos => [ @{ $model->{todos} } ] };
    if ( $msg->{type} eq 'SET_INPUT' ) {
        $m->{input} = $msg->{text};
    }
    elsif ( $msg->{type} eq 'ADD_TODO' ) {
        my $text = $m->{input};
        $text =~ s/^\s+|\s+$//g;
        if ( length $text ) {
            push @{ $m->{todos} }, { id => $m->{next_id}++, text => $text, done => 0 };
            $m->{input} = '';
        }
    }
    elsif ( $msg->{type} eq 'TOGGLE_TODO' ) {
        for my $todo ( @{ $m->{todos} } ) {
            if ( $todo->{id} == $msg->{id} ) {
                $todo->{done} = $msg->{done};
                last;
            }
        }
    }
    elsif ( $msg->{type} eq 'DELETE_TODO' ) {
        $m->{todos} = [ grep { $_->{id} != $msg->{id} } @{ $m->{todos} } ];
    }
    elsif ( $msg->{type} eq 'SET_FILTER' ) {
        $m->{filter} = $msg->{filter};
    }
    elsif ( $msg->{type} eq 'CLEAR_COMPLETED' ) {
        $m->{todos} = [ grep { !$_->{done} } @{ $m->{todos} } ];
    }
    return ( $m, undef );
};
my $view = sub ($model) {
    my @visible_todos = grep { $model->{filter} eq 'active' ? !$_->{done} : $model->{filter} eq 'completed' ? $_->{done} : 1 } @{ $model->{todos} };
    my $remaining     = scalar grep { !$_->{done} } @{ $model->{todos} };
    my @todo_rows;
    for my $t (@visible_todos) {
        my $tid = $t->{id};
        push @todo_rows,
            row(
            key      => "todo-$tid",
            spacing  => 8,
            children => [
                checkbox(
                    key       => "chk-$tid",
                    label     => '',
                    checked   => $t->{done},
                    on_toggle => sub ($checked) { { type => 'TOGGLE_TODO', id => $tid, done => $checked } }
                ),
                text( ( $t->{done} ? "[DONE] " : "" ) . $t->{text}, key => "txt-$tid", flex => 1 ),
                button( key => "del-$tid", label => 'Delete', on_click => { type => 'DELETE_TODO', id => $tid } )
            ]
            );
    }
    window(
        title    => 'Uji TodoMVC Demo',
        w        => 520,
        h        => 480,
        centered => 1,
        child    => column(
            padding  => 16,
            spacing  => 12,
            children => [
                text('Uji Keyed VDOM Todo Demo'),
                row(
                    spacing  => 8,
                    children => [
                        text_input( value => $model->{input}, on_input => sub ($val) { { type => 'SET_INPUT', text => $val } }, flex => 1 ),
                        button( label => 'Add Task', on_click => { type => 'ADD_TODO' } )
                    ]
                ),
                row(
                    spacing  => 6,
                    children => [
                        button( label => 'All',             on_click => { type => 'SET_FILTER', filter => 'all' } ),
                        button( label => 'Active',          on_click => { type => 'SET_FILTER', filter => 'active' } ),
                        button( label => 'Completed',       on_click => { type => 'SET_FILTER', filter => 'completed' } ),
                        button( label => 'Clear Completed', on_click => { type => 'CLEAR_COMPLETED' } )
                    ]
                ),
                column( key => 'todo-list', padding => 0, spacing => 6, children => \@todo_rows ),
                text( "Tasks remaining: $remaining of " . scalar( @{ $model->{todos} } ) )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
