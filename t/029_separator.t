use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Layout;
use Uji::Reconciler;

my $layout = Uji::Layout->new( driver => MockDriver->new );

#  1. Intrinsic boxes
subtest 'separator intrinsic box is the perpendicular thickness only' => sub {
    my $h = Uji::separator();
    is $h->type,      'separator',     'type is separator';
    is $h->orientation, 'horizontal',  'default orientation is horizontal';
    my ($hw, $hh) = $layout->_natural($h);
    is $hw, 0, 'horizontal separator intrinsic width is 0';
    is $hh, 3, 'horizontal separator intrinsic height is 3 (the rule thickness)';

    my $v = Uji::separator( orientation => 'vertical' );
    my ($vw, $vh) = $layout->_natural($v);
    is $vw, 3, 'vertical separator intrinsic width is 3';
    is $vh, 0, 'vertical separator intrinsic height is 0';
};

#  2. Horizontal separator spans a column, stays 3px tall
subtest 'horizontal separator crosses the full column width at 3px' => sub {
    my $sep = Uji::separator();
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'Top' ), $sep, Uji::button( label => 'Bottom' ) ],
    );
    $layout->compute( $col, 0, 0, 400, 300 );

    my ( $top, $s, $bot ) = @{ $col->children };
    is $sep->bw, 400, 'separator spans the full column width';
    is $sep->bh, 3,   'separator stays 3px tall';
    is $s->by,  $top->bh, 'separator sits right under the top button';
    is $bot->by, $top->bh + 3, 'bottom button resumes after the 3px rule';
};

#  3. Vertical separator spans a row, stays 3px wide
subtest 'vertical separator spans the full row height at 3px wide' => sub {
    my $sep = Uji::separator( orientation => 'vertical' );
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'L' ), $sep, Uji::button( label => 'R' ) ],
    );
    $layout->compute( $row, 0, 0, 400, 200 );

    my ( $l, $s, $r ) = @{ $row->children };
    is $sep->bw, 3,   'vertical separator stays 3px wide';
    is $sep->bh, 200, 'vertical separator spans the full row height';
    is $s->bx,  $l->bw, 'separator sits right after the left button';
    is $r->bx,  $l->bw + 3, 'right button resumes after the 3px rule';
};

#  4. Live Win32 mount: STATIC with the etched style bit
my $live = $^O eq 'MSWin32';
SKIP: {
    skip 'Win32 only', 6 unless $live;

    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;
    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);
    my $sep_h = Uji::separator();
    my $col   = Uji::column(
        padding  => 0,
        spacing  => 4,
        children => [ Uji::button( label => 'Top' ), $sep_h, Uji::button( label => 'Bottom' ) ],
    );
    my $vtree = Uji::window( id => 'sep_main', title => 'Separator Test', w => 400, h => 300, child => $col );
    $drv->mount($vtree);
    my $lay = Uji::Layout->new( driver => $drv );
    $lay->compute( $vtree, 0, 0, 400, 300 );
    $drv->mount_children($vtree);
    my $move_all;
    $move_all = sub {
        my ($n) = @_;
        $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
        $move_all->($_) for @{ $n->children };
    };
    $move_all->($vtree);

    my $sr = $drv->_get_registry_record( $sep_h->id );
    ok $sr && $sr->{hwnd}, 'separator has a registry record with a real HWND';
    is lc( $drv->_get_class( $sr->{hwnd} ) ), 'static', 'mounts a STATIC control';
    ok( $drv->_get_style( $sr->{hwnd} ) & 0x0010, 'style has SS_ETCHEDHORZ (0x10)' );

    #  5. Reconcile orientation change -> recreate with SS_ETCHEDVERT
    my $old_hwnd = $sr->{hwnd};
    my $recon    = Uji::Reconciler->new;
    my $old_sep  = Uji::separator( id => $sep_h->id, orientation => 'horizontal' );
    $old_sep->set_id( $sep_h->id );
    my $new_sep = Uji::separator( id => $sep_h->id, orientation => 'vertical' );
    $new_sep->set_id( $sep_h->id );
    $lay->compute( $old_sep, $sep_h->bx, $sep_h->by, $sep_h->bw, $sep_h->bh );
    $lay->compute( $new_sep, $sep_h->bx, $sep_h->by, $sep_h->bw, $sep_h->bh );
    $recon->patch( $old_sep, $new_sep, $drv );

    my $sr2 = $drv->_get_registry_record( $sep_h->id );
    ok $sr2 && $sr2->{hwnd}, 'registry entry survives the orientation change';
    isnt $sr2->{hwnd}, $old_hwnd, 'orientation change recreated the native control';
    ok( $drv->_get_style( $sr2->{hwnd} ) & 0x0011, 'recreated control has SS_ETCHEDVERT (0x11)' );

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('sep_main')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

done_testing;
