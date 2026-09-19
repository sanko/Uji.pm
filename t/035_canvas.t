use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use Uji;
use Uji::Layout;
use Uji::Reconciler;

# --- A tiny mock driver (no drawing seam; the intrinsic size is constant) ---
package MockLayout {
    use v5.40;
    sub new { bless {}, shift }
    sub measure_text  ( $self, $t ) { ( CORE::length($t) * 8, 16 ) }
}
package main;

# ── 1. Node / factory ──────────────────────────────────────────────────
subtest 'the canvas node and factory' => sub {
    my $cb   = sub ($d) {};
    my $cnv  = Uji::canvas( w => 120, h => 60, on_draw => $cb, redraw => 3 );
    isa_ok $cnv, ['Uji::Node::Canvas'];
    is $cnv->type, 'canvas', 'type is canvas';
    is $cnv->w, 120,  'explicit w captured';
    is $cnv->h, 60,   'explicit h captured';
    is $cnv->on_draw, $cb, 'on_draw captured';
    is $cnv->redraw, 3,    'redraw captured';
    is Uji::canvas->on_draw, undef, 'on_draw is optional';
    is Uji::canvas->w,       0,     'w defaults to 0 (layout provides the natural box)';
};

# ── 2. Layout: natural size and explicit override ──────────────────────
subtest 'layout sizes the canvas and hands a Uji::Draw sized to the box' => sub {
    my $layout = Uji::Layout->new( driver => MockLayout->new );
    my ( $nw, $nh ) = $layout->_natural( Uji::canvas() );
    is [ $nw, $nh ], [ 200, 100 ], 'canvas defaults to a 200x100 natural box';

    my ( $w1, $h1 ) = $layout->_natural( Uji::canvas( w => 300 ) );
    is [ $w1, $h1 ], [ 300, 100 ], 'explicit w overrides the natural width';

    my ( $w2, $h2 ) = $layout->_natural( Uji::canvas( w => 320, h => 240 ) );
    is [ $w2, $h2 ], [ 320, 240 ], 'explicit w and h win verbatim';
};

# ── 3. Uji::Draw (base): public vocabulary, colour parsing, size (headless) ─
subtest 'Uji::Draw defines the portable drawing vocabulary' => sub {
    use Uji::Draw;
    ok( Uji::Draw->can('clear') && Uji::Draw->can('line') && Uji::Draw->can('rect')
            && Uji::Draw->can('fill_rect') && Uji::Draw->can('ellipse') && Uji::Draw->can('fill_ellipse')
            && Uji::Draw->can('arc') && Uji::Draw->can('fill_pie'),
        'the base draw exposes every primitive in the public vocabulary' );
    ok( Uji::Draw->can('_clear') && Uji::Draw->can('_line') && Uji::Draw->can('_fill_pie'),
        '... and the platform contract the implementations must supply' );

    # _argb is the color→ARGB map used by the implementations: '#RRGGBB' with an
    # opaque alpha top byte (no R/B swap like the spinner's historical math).
    my $d   = Uji::Draw->new( w => 12, h => 8 );
    my $red = $d->_argb('#FF0000');
    is( $red & 0xFFFFFF, 0xFF0000, 'red maps to ARGB 0xFFFF0000' );
    is( $red >> 24,      0xFF,     'alpha defaults to opaque' );
    is( $d->_argb('#0000FF') & 0xFFFFFF, 0x0000FF, 'blue maps to ARGB 0xFF0000FF' );
    is [ $d->size ], [ 12, 8 ], 'size reports the box';

    # The base itself is abstract: drawing without a platform impl fails loudly.
    like dies( sub { $d->line( 0, 0, 1, 1 ) } ), qr/must implement _line/, 'abstract _line dies with a clear message';
};

# ── 4. Real driver: mount, paint via on_draw, reconcile keeps the control ─
subtest 'the Win32 driver mounts a canvas, paints on_draw, and repaints on redraw' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;

    my @log;
    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $cnv = sub {
        Uji::canvas(
            id         => 'cv',
            w          => 160,
            h          => 90,
            background => '#123456',
            on_draw    => sub ($d) {
                push @log, [ 'size', [ $d->size ] ];
                $d->color('#FF0000');
                $d->width(2);
                $d->fill_rect( 10, 10, 40, 30 );
                $d->line( 0, 0, 159, 89 );
                $d->ellipse( 50, 20, 40, 40 );
                $d->arc( 60, 50, 40, 30, 0, 180 );
                push @log, [ 'after', $d->color, $d->width ];
            }
        );
    };
    my $win = Uji::window( id => 'o', title => 't', w => 200, h => 140,
        child => Uji::column( padding => 16, children => [ $cnv->() ] ) );
    $drv->mount($win);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win, 0, 0, 200, 140 );
    $drv->mount_children($win);
    $chan->get() while $chan->size;

    my $rec  = $drv->_get_registry_record('cv');
    ok $rec->{hwnd}, 'canvas mounted with an hwnd';

    # Clear any paints that already happened during mount/ShowWindow/resize,
    # then force exactly one WM_PAINT synchronously.
    @log = ();
    Uji::Driver::Win32::InvalidateRect( $rec->{hwnd}, undef, 0 );
    Uji::Driver::Win32::UpdateWindow( $rec->{hwnd} );
    is @log, 2, 'one on_draw fired per WM_PAINT (two recorded calls)';
    is $log[0][0], 'size', 'first call was size()';
    is $log[0][1], [ 160, 90 ], 'draw received the 160x90 box';
    is $log[1][0], 'after', 'state getters work';
    is $log[1][1], '#FF0000', 'color held after the draws';
    is $log[1][2], 2, 'width held after the draws';

    # Bumping redraw (the reconciler path) invalidates without touching the hwnd.
    my $hwnd = $rec->{hwnd};
    my $win2 = Uji::window( id => 'o', title => 't', w => 200, h => 140,
        child => Uji::column( padding => 16, children => [
            Uji::canvas( id => 'cv', w => 160, h => 90, background => '#123456',
                on_draw => sub ($d) { push @log, [ 'redraw' ] },
                redraw  => 1 )
        ] ) );
    $layout->compute( $win2, 0, 0, 200, 140 );
    Uji::Reconciler->new->patch_windows( [$win], [$win2], $drv );
    $chan->get() while $chan->size;

    $rec = $drv->_get_registry_record('cv');
    is $rec->{node}->redraw, 1,   'redraw prop reached the node';
    is $rec->{hwnd},         $hwnd, 'same control survived the patch';

    @log = ();
    Uji::Driver::Win32::InvalidateRect( $rec->{hwnd}, undef, 0 );
    Uji::Driver::Win32::UpdateWindow( $rec->{hwnd} );
    is $log[-1][0], 'redraw', 'the reconciled callback was painted';

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('o')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
};

done_testing;