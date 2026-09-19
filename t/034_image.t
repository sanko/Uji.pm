use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use Uji;
use Uji::Layout;
use Uji::Reconciler;

require File::Temp;

# A 24-bit BMP (written to disk for the real driver): 4x2, rows bottom-up, solid red.
my $row = "\x00\x00\xff" x 4;    # 4 px x 24bpp = 12 bytes
my $bmp_bytes = pack( 'a2', 'BM' )
    . pack( 'L<', 14 + 40 + 24 ) . pack( 'v2', 0, 0 ) . pack( 'L<', 14 + 40 )    # file header
    . pack( 'L<', 40 )           # biSize
    . pack( 'L<', 4 )            # biWidth
    . pack( 'L<', 2 )            # biHeight
    . pack( 'v',  1 )            # biPlanes
    . pack( 'v',  24 )           # biBitCount
    . pack( 'L<', 0 )            # biCompression (BI_RGB)
    . pack( 'L<', 24 )           # biSizeImage
    . pack( 'L<', 2835 ) . pack( 'L<', 2835 ) . pack( 'L<', 0 ) . pack( 'L<', 0 )
    . $row . $row;

# A 1x1 transparent PNG as a data:image URI.
my $one_px_png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

# --- A tiny mock driver whose raster is 40x20. ----------------------------
package MockMeasure {
    use v5.40;
    sub new { bless {}, shift }
    sub measure_text  ( $self, $t ) { ( CORE::length($t) * 8, 16 ) }
    sub measure_image ( $self, $s ) { ( 40, 20 ) }
}
package NoMeasure {
    use v5.40;
    sub new { bless {}, shift }
    sub measure_text ( $self, $t ) { ( 10, 10 ) }
}
package main;

# ── 1. Node / factory ────────────────────────────────────────────────────
subtest 'the image node and factory' => sub {
    my $img = Uji::image( src => 'x.png', alt => 'a chart', object_fit => 'cover' );
    isa_ok $img, ['Uji::Node::Image'];
    is $img->type, 'image', 'type is image';
    is $img->src, 'x.png', 'src captured';
    is $img->alt, 'a chart', 'alt captured';
    is $img->object_fit, 'cover', 'object_fit captured';
    is Uji::image->object_fit, 'contain', 'object_fit defaults to contain';
    is Uji::image->src, undef, 'src is optional';
};

# ── 2. Layout: natural size and aspect preservation ──────────────────────
subtest 'layout measures natural size and preserves aspect' => sub {
    my $layout = Uji::Layout->new( driver => MockMeasure->new );
    my ( $nw, $nh ) = $layout->_natural( Uji::image( src => 'a.png' ) );
    is [ $nw, $nh ], [ 40, 20 ], 'natural size comes from measure_image';

    my ( $w1, $h1 ) = $layout->_natural( Uji::image( src => 'a.png', w => 80 ) );
    is [ $w1, $h1 ], [ 80, 40 ], 'explicit w keeps the aspect (h = 40)';

    my ( $w2, $h2 ) = $layout->_natural( Uji::image( src => 'a.png', h => 30 ) );
    is [ $w2, $h2 ], [ 60, 30 ], 'explicit h keeps the aspect (w = 60)';

    my ( $w3, $h3 ) = $layout->_natural( Uji::image( src => 'a.png', w => 80, h => 90 ) );
    is [ $w3, $h3 ], [ 80, 90 ], 'explicit w and h win verbatim';

    my $plain = Uji::Layout->new( driver => NoMeasure->new );
    my ( $pw, $ph ) = $plain->_natural( Uji::image( src => 'a.png' ) );
    is [ $pw, $ph ], [ 64, 64 ], 'missing measure_image falls back to a 64x64 placeholder';
};

# ── 3. Real driver: mount, raster at the laid-out box, fit change ────────
subtest 'the Win32 driver mounts an image and rasters it at the laid-out box' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;

    my ( $fh, $bmp_path ) = File::Temp::tempfile( 'uji_img_XXXXXX', SUFFIX => '.bmp', OPEN => 1 );
    binmode $fh;
    print {$fh} $bmp_bytes;
    close $fh;

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $img = Uji::image( id => 'pic', src => $bmp_path );
    my $win = Uji::window( id => 'o', title => 't', w => 200, h => 120,
        child => Uji::column( padding => 20, children => [ $img ] ) );
    $drv->mount($win);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win, 0, 0, 200, 120 );
    $drv->mount_children($win);

    is [ $drv->measure_image($bmp_path) ], [ 4, 2 ], 'measure_image reports the BMPs natural size';

    my $rec = $drv->_get_registry_record('pic');
    ok $rec->{hwnd}, 'image mounted with an hwnd';
    is $rec->{img_src}, $bmp_path, 'img_src tracked';
    ok Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0173, 0, 0 ), 'SS_BITMAP shows a bitmap after mount';

    # The move to the real box re-rasters at the laid-out w x h.
    $drv->move_widget( 'pic', 20, 20, 80, 40 );
    is $rec->{img_w}, 80, 're-rastered width after the layout move';
    is $rec->{img_h}, 40, 're-rastered height after the layout move';

    # A fit change swaps the picture through set_prop without touching the control.
    $drv->set_prop( 'pic', 'object_fit', 'cover' );
    is $rec->{img_fit}, 'cover', 'fit change tracked';
    ok Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0173, 0, 0 ), 'bitmap survives a fit swap';

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('o')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
};

# ── 3b. data:image URI through the real driver ───────────────────────────
subtest 'a data:image URI decodes through the shared loader' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    my $drv = Uji::Driver::Win32->new;
    is [ $drv->measure_image( "data:image/png;base64,$one_px_png" ) ], [ 1, 1 ],
        'data URI decodes to its natural 1x1 size';
};

# ── 4. Reconcile: a re-render that swaps src/object_fit keeps the control ─
subtest 'a patched src/object_fit keeps the same image control' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;

    my ( $fh, $bmp_path ) = File::Temp::tempfile( 'uji_img_XXXXXX', SUFFIX => '.bmp', OPEN => 1 );
    binmode $fh;
    print {$fh} $bmp_bytes;
    close $fh;

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $build = sub ( $src, $fit ) {
        Uji::window(
            id => 'o', title => 't', w => 200, h => 120,
            child => Uji::column( padding => 20, children => [
                Uji::image( id => 'pic', src => $src, object_fit => $fit )
            ] )
        );
    };

    my $win1 = $build->( "data:image/png;base64,$one_px_png", 'contain' );
    $drv->mount($win1);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win1, 0, 0, 200, 120 );
    $drv->mount_children($win1);
    $chan->get() while $chan->size;

    my $rec   = $drv->_get_registry_record('pic');
    my $hwnd  = $rec->{hwnd};
    $drv->move_widget( 'pic', 20, 20, 80, 40 );

    my $before = Uji::Driver::Win32::SendMessageW( $hwnd, 0x0173, 0, 0 );
    my $win2   = $build->( $bmp_path, 'cover' );
    $layout->compute( $win2, 0, 0, 200, 120 );
    Uji::Reconciler->new->patch_windows( [$win1], [$win2], $drv );

    $rec = $drv->_get_registry_record('pic');
    is $rec->{img_src}, $bmp_path, 'patched src re-rastered';
    is $rec->{img_fit}, 'cover',    'patched object_fit re-rastered';
    is $rec->{hwnd},    $hwnd,      'same control survived the patch';
    my $after = Uji::Driver::Win32::SendMessageW( $hwnd, 0x0173, 0, 0 );
    ok $after && $after != $before, 'the displayed bitmap changed with the source';

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('o')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
};

done_testing;