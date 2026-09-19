use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use Uji;

# 1. Spinner node and factory
subtest 'the spinner node and factory' => sub {
    my $s = Uji::spinner;
    is $s->type, 'spinner', 'default spinner is a spinner';
    is $s->size, 24,  'default size is 24';
    is $s->speed, 80, 'default speed is 80 ms/frame';
    is $s->running, 1, 'default running is on';
    is $s->_type, 'spinner', '_type is spinner';

    my $t = Uji::spinner( size => 48, color => '#c00000', speed => 30, running => 0 );
    is $t->size, 48,    'explicit size is honoured';
    is $t->color, '#c00000', 'explicit color is honoured';
    is $t->speed, 30,   'explicit speed is honoured';
    is $t->running, 0,  'explicit running is honoured';
};

# 2. Layout: intrinsic square box, natural sizing
subtest 'layout sizes a spinner as its `size` square' => sub {
    use Uji::Layout;
    my $layout = Uji::Layout->new( driver => undef );

    my $tiny = Uji::spinner;
    my ( $iw, $ih ) = $layout->_natural($tiny);
    is( [ $iw, $ih ], [ 24, 24 ], 'default spinner is 24x24' );

    my $big = Uji::spinner( size => 64 );
    ( $iw, $ih ) = $layout->_natural($big);
    is( [ $iw, $ih ], [ 64, 64 ], 'size=64 gives a 64x64 natural box' );

    my $pinned = Uji::spinner( size => 30, w => 100 );
    ( $iw, $ih ) = $layout->_natural($pinned);
    is( [ $iw, $ih ], [ 100, 30 ], 'an explicit w overrides the natural width' );
};

# 3. Real driver: STATIC SS_ICON host, frames, WM_TIMER ticks
subtest 'the Win32 driver animates a spinner' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $sp = Uji::spinner( id => 'sp', size => 28, speed => 40 );
    my $win = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ $sp, Uji::button( id => 99, label => 'x' ) ] ) );
    $drv->mount($win);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win, 0, 0, 200, 120 );
    $drv->mount_children($win);
    $chan->get() while $chan->size;

    my $rec   = $drv->_get_registry_record('sp');
    my $frames = $rec->{spin_frames};
    ok ref $frames eq 'ARRAY', 'the registry holds a frame list';
    cmp_ok scalar(@$frames), '>=', 12, 'a dozen or more frames were pre-rendered';
    is $rec->{spin_idx}, 0, 'starts on frame 0';

    my $hwnd = $rec->{hwnd};
    is Uji::Driver::Win32::SendMessageW( $hwnd, 0x0171, 0, 0 ), $frames->[0], 'frame 0 is shown on the STATIC';

    my $parent = $drv->_get_registry_record('o')->{hwnd};
    my $cid    = $rec->{cid};

    # A synthetic WM_TIMER must act like the real one: advance the frame and swap the icon.
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 );
    is $rec->{spin_idx}, 1, 'a WM_TIMER tick advanced the frame index';
    is Uji::Driver::Win32::SendMessageW( $hwnd, 0x0171, 0, 0 ), $frames->[1], 'the second frame is now shown';

    # Wrap-around after a full cycle.
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 ) for 1 .. 11;
    is $rec->{spin_idx}, 0, 'the frame index wraps around the cycle';
    is Uji::Driver::Win32::SendMessageW( $hwnd, 0x0171, 0, 0 ), $frames->[0], 'the first frame is shown again';

    # running => 0 disarms the timer (set_prop path); a stale tick must be ignored.
    $drv->set_prop( 'sp', 'running', 0 );
    $rec = $drv->_get_registry_record('sp');
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 );
    is Uji::Driver::Win32::SendMessageW( $hwnd, 0x0171, 0, 0 ), $frames->[0], 'a stopped spinner ignores stale ticks';

    # running => 1 re-arms.
    $drv->set_prop( 'sp', 'running', 1 );
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 );
    is $rec->{spin_idx}, 1, 'after re-arming, ticks advance again';

    Uji::Driver::Win32::SendMessageW( $parent, 0x0010, 0, 0 );    # WM_CLOSE
};

# 3b. The demo path: toggle running THROUGH a window patch
subtest 'a patched running flag freezes and restarts the spinner' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;
    use Uji::Reconciler;

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $spinning = Uji::spinner( id => 'sp', size => 28, speed => 40, running => 1 );
    my $win = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ $spinning ] ) );
    $drv->mount($win);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win, 0, 0, 200, 120 );
    $drv->mount_children($win);
    $chan->get() while $chan->size;

    my $rec    = $drv->_get_registry_record('sp');
    my $parent = $drv->_get_registry_record('o')->{hwnd};
    my $cid    = $rec->{cid};
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 );
    my $ticked = Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0171, 0, 0 );

    # Re-render with running => 0 (exactly what the demo's view() does on Toggle) and patch.
    my $stopped = Uji::spinner( id => 'sp', size => 28, speed => 40, running => 0 );
    my $win1 = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ $stopped ] ) );
    Uji::Reconciler->new->patch_windows( [$win], [$win1], $drv );

    my $before = Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0171, 0, 0 );
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 );
    is Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0171, 0, 0 ), $before,
        'running=0 through a patch keeps the last frame (no animation)';

    # Re-render with running => 1: animation resumes on the same control.
    my $resumed = Uji::spinner( id => 'sp', size => 28, speed => 40, running => 1 );
    my $win2 = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ $resumed ] ) );
    Uji::Reconciler->new->patch_windows( [$win1], [$win2], $drv );
    Uji::Driver::Win32::SendMessageW( $parent, 0x0113, $cid, 0 );
    isnt Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0171, 0, 0 ), $before,
        'running=1 through a patch animates again';

    Uji::Driver::Win32::SendMessageW( $parent, 0x0010, 0, 0 );    # WM_CLOSE
};

# 4. Reconciler: adding a spinner by patching
subtest 'a reconciled spinner mounts and animates' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $win0 = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ Uji::text( 'loading' ) ] ) );
    $drv->mount($win0);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win0, 0, 0, 200, 120 );
    $drv->mount_children($win0);
    $chan->get() while $chan->size;

    my $win1 = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ Uji::text( 'loading' ), Uji::spinner( id => 'sp2' ) ] ) );
    Uji::Reconciler->new->patch_windows( [$win0], [$win1], $drv );

    my $rec = $drv->_get_registry_record('sp2');
    ok !ref $rec->{spin_frames} || @{ $rec->{spin_frames} }, 'the reconciled spinner got frames';
    is Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0171, 0, 0 ), $rec->{spin_frames}[0], 'it shows frame 0';
    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('o')->{hwnd}, 0x0113, $rec->{cid}, 0 );
    is Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0171, 0, 0 ), $rec->{spin_frames}[1], 'a tick animates it';

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('o')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
};

done_testing;
