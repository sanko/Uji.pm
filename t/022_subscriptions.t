use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use Time::HiRes ();
use MockDriver;
use Uji;
use Uji::App;
use Uji::Sub;

# Minimal channel stand-in so we never spin up Acme::Parataxis in a unit test.
package Canned::Channel {
    use v5.40;
    sub new  { bless { q => [] }, shift }
    sub put  { my ( $s, $m ) = @_; push @{ $s->{q} }, $m; 1 }
    sub get  { my ($s) = @_; shift @{ $s->{q} } }
    sub size { my ($s) = @_; scalar @{ $s->{q} } }
}

# the subscription factories

subtest 'sub_interval normalizes its descriptor' => sub {
    my $sub = Uji::sub_interval( 1000, { type => 'TICK' } );
    is $sub->{kind}, 'interval', 'kind';
    is $sub->{ms},   1000,       'ms';
    is $sub->{msg},  { type => 'TICK' }, 'message preserved';
    ok $sub->{key}, 'key computed';
    is Uji::sub_interval( 1000, { type => 'TICK' } )->{key}, $sub->{key}, 'same data -> same key';
    isnt Uji::sub_interval( 1000, { type => 'TOCK' } )->{key}, $sub->{key}, 'message content is part of the key';
    isnt Uji::sub_interval( 2000, { type => 'TICK' } )->{key}, $sub->{key}, 'period is part of the key';
};

subtest 'keys are order-independent and identity-free for closures' => sub {
    is Uji::sub_interval( 500, { b => 2, a => 1 } )->{key},
        Uji::sub_interval( 500, { a => 1, b => 2 } )->{key},
        'hash key order does not matter';
    my $a = Uji::sub_interval( 500, sub { { type => 'TICK' } } );
    my $b = Uji::sub_interval( 500, sub { { type => 'TICK' } } );
    is $a->{key}, $b->{key}, 'closures key on period, not identity';
    isnt $a->{key}, Uji::sub_interval( 500, sub { { type => 'TICK' } }, id => 'x' )->{key}, 'explicit id disambiguates';
};

subtest 'sub_on_resize' => sub {
    my $sub = Uji::sub_on_resize( { type => 'RESIZED' } );
    is $sub->{kind}, 'resize', 'kind';
    is $sub->{key},  'resize:{type=RESIZED}', 'key';
};

# a live app

my $view = sub ($m) {
    Uji::window(
        id    => 'main',
        title => 'subs',
        w     => 360,
        h     => 400,
        child => Uji::column( children => [ Uji::text( 'Count: ' . ( $m->{count} // 0 ) ) ] ),
    );
};

my $mk_update = sub ( $seen ) {
    return sub ( $msg, $model ) {
        push @$seen, $msg->{type};
        if    ( $msg->{type} eq 'TICK' )    { $model->{count} += 1 }
        elsif ( $msg->{type} eq 'TICK_AT' ) { $model->{count} += 1; $model->{stamp} = $msg->{now} }
        elsif ( $msg->{type} eq 'RESIZED' ) { $model->{resizes} += 1 }
        elsif ( $msg->{type} eq 'START' )   { $model->{want_timer} = 1 }
        elsif ( $msg->{type} eq 'STOP' )    { $model->{want_timer} = 0 }
        return ( $model, undef );
    };
};

subtest 'interval subscription fires, survives renders, and stops' => sub {
    my @seen   = ();
    my $drv    = MockDriver->new;
    my $chan   = Canned::Channel->new;
    my $update = $mk_update->( \@seen );
    my $subs   = sub ($m) { $m->{want_timer} ? [ Uji::sub_interval( 1000, { type => 'TICK' } ) ] : [] };
    my $app    = Uji::App->new(
        init => sub { ( { count => 0, want_timer => 1 }, undef ) },
        update => $update, view => $view, subscriptions => $subs,
        driver => $drv, channel => $chan,
    );
    $app->_boot;
    is scalar( keys %{ $app->active_subs } ), 1, 'one subscription activated at boot';
    my ($key) = keys %{ $app->active_subs };
    my $live  = $app->active_subs->{$key};
    ok $live->{next} > 0, 'interval has a due time';

    $app->_tick_subscriptions( $live->{next} - 1 );
    is $chan->size, 0, 'nothing fires before it is due';

    $app->_tick_subscriptions( $live->{next} );
    is $chan->size, 1, 'fires once when due';
    $app->_drain_and_render( $chan->get );
    is $app->model->{count}, 1, 'TICK reached the model';

    # The render must not have reset the timer's phase (no starvation).
    my $next_after = $live->{next};
    is $app->active_subs->{$key}, $live, 'same live descriptor across renders';
    $app->_sync_subscriptions;
    is $app->active_subs->{$key}{next}, $next_after, 'phase is preserved by a re-sync';

    $app->_tick_subscriptions($next_after);
    is $chan->size, 1, 'fires again on the next period';
    $app->_drain_and_render( $chan->get );
    is $app->model->{count}, 2, 'second TICK reached the model';

    # Unsubscribe through a normal message round-trip.
    $chan->put( { type => 'STOP' } );
    $app->_drain_and_render( $chan->get );
    is scalar( keys %{ $app->active_subs } ), 0, 'subscription stopped when no longer wanted';
    $app->_tick_subscriptions( $next_after + 10_000 );
    is $chan->size, 0, 'stopped interval stays silent';
    is $app->model->{count}, 2, 'no further ticks';
};

subtest 'a message closure is called with the current time' => sub {
    my @seen = ();
    my $drv  = MockDriver->new;
    my $chan = Canned::Channel->new;
    my $subs = sub { [ Uji::sub_interval( 500, sub ($now) { { type => 'TICK_AT', now => $now } } ) ] };
    my $app  = Uji::App->new(
        init => sub { ( { count => 0 }, undef ) },
        update => $mk_update->( \@seen ), view => $view, subscriptions => $subs,
        driver => $drv, channel => $chan,
    );
    $app->_boot;
    my ($key) = keys %{ $app->active_subs };
    my $due   = $app->active_subs->{$key}{next};
    $app->_tick_subscriptions($due);
    $app->_drain_and_render( $chan->get );
    is $app->model->{stamp}, $due, 'closure received the tick time';
};

subtest 'identical subscriptions collapse; ids keep them distinct' => sub {
    my $chan = Canned::Channel->new;
    my $app  = Uji::App->new(
        init    => sub { ( {}, undef ) },
        update  => sub { ( $_[1], undef ) },
        view    => $view,
        driver  => MockDriver->new,
        channel => $chan,
        subscriptions => sub {
            [ Uji::sub_interval( 1000, { type => 'TICK' } ), Uji::sub_interval( 1000, { type => 'TICK' } ) ];
        },
    );
    $app->_boot;
    is scalar( keys %{ $app->active_subs } ), 1, 'two identical intervals collapse to one';

    my $app2 = Uji::App->new(
        init    => sub { ( {}, undef ) },
        update  => sub { ( $_[1], undef ) },
        view    => $view,
        driver  => MockDriver->new,
        channel => Canned::Channel->new,
        subscriptions => sub {
            [ Uji::sub_interval( 1000, sub { {} }, id => 'a' ), Uji::sub_interval( 1000, sub { {} }, id => 'b' ) ];
        },
    );
    $app2->_boot;
    is scalar( keys %{ $app2->active_subs } ), 2, 'explicit ids disambiguate';
};

subtest 'resize subscription routes the platform event into update' => sub {
    my @seen = ();
    my $chan = Canned::Channel->new;
    my $app  = Uji::App->new(
        init     => sub { ( { resizes => 0 }, undef ) },
        update   => $mk_update->( \@seen ),
        view     => $view,
        driver   => MockDriver->new,
        channel  => $chan,
        subscriptions => sub { [ Uji::sub_on_resize( { type => 'RESIZED' } ) ] },
    );
    $app->_boot;
    is scalar( keys %{ $app->active_subs } ), 1, 'resize subscription active';

    $chan->put( { type => 'RESIZE' } );
    $app->_drain_and_render( $chan->get );
    is $app->model->{resizes}, 1, 'RESIZED reached the model';
    is \@seen,             ['RESIZED'], 'reserved RESIZE never reached update';
};

subtest 'the synchronous modal pump ticks and renders inline' => sub {
    my @seen = ();
    my $drv  = MockDriver->new;
    my $chan = Canned::Channel->new;
    my $app  = Uji::App->new(
        init          => sub { ( { count => 0 }, undef ) },
        update        => $mk_update->( \@seen ),
        view          => $view,
        driver        => $drv,
        channel       => $chan,
        subscriptions => sub { [ Uji::sub_interval( 10_000_000, { type => 'TICK' } ) ] },
    );
    $app->_boot;
    my ($key) = keys %{ $app->active_subs };

    my $now = Time::HiRes::time() * 1000;
    $app->active_subs->{$key}{next} = $now + 10_000_000;
    $app->_pump_modal;
    is $app->model->{count}, 0, 'no tick before the interval is due';
    is $chan->size,          0, 'channel still empty';

    $app->active_subs->{$key}{next} = $now - 1;    # due now
    $app->_pump_modal;
    is $app->model->{count}, 1, 'pump folded the tick synchronously';
    is $chan->size,          0, 'channel drained by the pump';
    like $app->vtrees->[0]->child->children->[0]->label, qr/Count: 1/, 'view re-rendered inline';
};

subtest 'a RESIZE with no subscriptions is harmless' => sub {
    my $chan = Canned::Channel->new;
    my $app  = Uji::App->new(
        init    => sub { ( { n => 0 }, undef ) },
        update  => sub { ( $_[1], undef ) },
        view    => $view,
        driver  => MockDriver->new,
        channel => $chan,
    );
    $app->_boot;
    is scalar( keys %{ $app->active_subs } ), 0, 'no subscriptions by default';
    $chan->put( { type => 'RESIZE' } );
    ok lives { $app->_drain_and_render( $chan->get ) }, 'drained a bare RESIZE';
};

done_testing;
