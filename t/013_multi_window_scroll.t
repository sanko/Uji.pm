use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Uji::App;
use Affix qw[:memory :core :types];
use Acme::Parataxis::Channel;
use Encode qw[decode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Multi-window + reconciler ADD regression: window A appends rows of Uji::text() into a
# scroll_view content column in window B. view() returns an ARRAY (no explicit ids; window
# identity is positional), and rows are added at runtime via BM_CLICK -> channel -> update ->
# render. The first row lands in an EMPTY content column, so there are no mounted siblings to
# inherit parent/output from -- the anchor-context path in Reconciler::patch + Driver::mount_subtree
# must resolve the parent to the VIEWER's viewport HWND and tag the new records with the viewer's
# scroll store. Regression for rows ending up parented to $main_hwnd (window A) / untagged.
my $chan   = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv    = Uji::Driver::Win32->new;
my $model  = { log => [] };
my $update = sub ( $msg, $model ) {
    if    ( $msg->{type} eq 'APPEND' ) { push @{ $model->{log} }, 'row ' . ( @{ $model->{log} } + 1 ) }
    elsif ( $msg->{type} eq 'CLEAR' )  { $model->{log} = [] }
    return ( $model, undef );
};
my $view = sub ($model) {
    my $viewer = Uji::window(
        title => 'Viewer',
        w     => 380,
        h     => 320,
        child => Uji::column(
            padding  => 10,
            spacing  => 8,
            children => [
                Uji::status_text( 'rows: ' . @{ $model->{log} } ),
                Uji::scroll_view( Uji::column( spacing => 4, padding => 4, children => [ map { Uji::text($_) } @{ $model->{log} } ] ) )
            ]
        )
    );
    my $controller = Uji::window(
        title => 'Controller',
        w     => 300,
        h     => 160,
        child => Uji::column(
            padding  => 12,
            spacing  => 10,
            children => [
                Uji::button( label => 'Append', on_click => { type => 'APPEND' } ),
                Uji::button( label => 'Clear',  on_click => { type => 'CLEAR' } )
            ]
        )
    );
    return [ $controller, $viewer ];
};
my $app = Uji::App->new( init => sub { ( $model, undef ) }, update => $update, view => $view, driver => $drv, channel => $chan );
$drv->init($chan);
$app->_boot;

sub pump {
    for ( 1 .. 5 ) { $drv->poll_events(); select undef, undef, undef, 0.01 }
}

sub drain {
    while ( $chan->size ) { $app->_drain_and_render( $chan->get() ) }
}
sub zstr ($s) { my $i = CORE::index( $s, chr(0) ); return $i >= 0 ? substr( $s, 0, $i ) : $s }

sub tree_texts ($n) {
    my $c = $n->type eq 'text' ? 1 : 0;
    $c += tree_texts($_) for @{ $n->children };
    return $c;
}

sub find_button ( $win, $label ) {
    my $h = Uji::Driver::Win32::GetWindow( $win, 5 );    # GW_CHILD
    while ($h) {
        my $buf1 = malloc(64);
        Uji::Driver::Win32::GetClassNameW( $h, $buf1, 16 );
        my $cls = lc zstr( decode( 'UTF-16LE', Affix::raw( $buf1, 32 ) ) );
        my $buf = malloc(128);
        Uji::Driver::Win32::GetWindowTextW( $h, $buf, 64 );
        my $txt = zstr( decode( 'UTF-16LE', Affix::raw( $buf, 128 ) ) );
        return $h if $cls eq 'button' && $txt eq $label;
        $h = Uji::Driver::Win32::GetWindow( $h, 2 );    # GW_HWNDNEXT
    }
    return;
}

sub viewer_node {
    ( grep { $_->title eq 'Viewer' } @{ $app->vtrees } )[0];
}
pump;
drain;
is @{ $app->vtrees }, 2, 'view returned two windows';
my $cwin = ( grep { $_->title eq 'Controller' } @{ $app->vtrees } )[0];
my $vwin = viewer_node();
ok $cwin && $drv->_get_registry_record( $cwin->id )->{hwnd}, 'controller window mounted';
ok $vwin && $drv->_get_registry_record( $vwin->id )->{hwnd}, 'viewer window mounted';
scroll_assert( $vwin, 0, 'boot' );

sub scroll_assert ( $vnode, $n_expected, $when ) {
    my $sv;
    my $walk;
    $walk = sub ($n) {
        if ( !$sv && $n->type eq 'scroll_view' ) { $sv = $n }
        else                                     { $walk->($_) for @{ $n->children } }
    };
    $walk->($vnode);
    my $svr = $drv->_get_registry_record( $sv->id );
    ok $svr && $svr->{hwnd}, "$when: scroll_view mounted";
    my $col  = $sv->children->[0];
    my $rows = $col && @{ $col->children } ? $col->children : [];
    is scalar(@$rows), $n_expected, "$when: content has $n_expected row(s)";
    my $good = 0;

    for my $i ( 0 .. $#$rows ) {
        my $r = $drv->_get_registry_record( $rows->[$i]->id );
        if ( $r && defined $r->{parent_hwnd} && $r->{parent_hwnd} == $svr->{hwnd} && $r->{scroll} && $r->{scroll} == $svr->{scroll} ) {
            $good++;
        }
    }
    is $good, $n_expected, "$when: every added row is parented to the viewer viewport + tagged";
    return $svr;
}

# First APPEND lands in the EMPTY column (no sibling record exists): the anchor-context
# resolution must parent the new row to the viewer's viewport + tag it with its scroll store.
# no warnings guard: SendMessageW re-enters the Affix wndproc bridge (poll_events quirk).
sub SendMessageW_BM_CLICK ($h) {
    no warnings 'uninitialized';
    Uji::Driver::Win32::SendMessageW( $h, 0x00F5, 0, 0 );
}
my $btn = find_button( $drv->_get_registry_record( $cwin->id )->{hwnd}, 'Append' );
ok $btn, 'Append button found in the controller window';
SendMessageW_BM_CLICK($btn);
pump;
drain;
scroll_assert( viewer_node(), 1, 'after 1st APPEND' );

# Second APPEND inherits the sibling's parent/store.
SendMessageW_BM_CLICK($btn);
pump;
drain;
scroll_assert( viewer_node(), 2, 'after 2nd APPEND' );

# CLEAR removes the rows: records for the removed texts must be gone.
my $cbtn = find_button( $drv->_get_registry_record( $cwin->id )->{hwnd}, 'Clear' );
ok $cbtn, 'Clear button found';
SendMessageW_BM_CLICK($cbtn);
pump;
drain;
my $vwin3 = viewer_node();
scroll_assert( $vwin3, 0, 'after CLEAR' );
my $leftover = 0;
my $walk2;
$walk2 = sub ($n) {
    $leftover += 2 if $n->type eq 'text' && $drv->_get_registry_record( $n->id );
    $walk2->($_) for @{ $n->children };
};
$walk2->($vwin3);
is $leftover, 0, 'removed rows left no registry records behind';

# ─── bug regression: appended rows must grow the scroll range immediately (no window resize) ───
# Before the fix, _place_scrollbars only ran from move_widget; the plain render path never invoked
# it for a scroll_view whose own (fill) bounds were unchanged, so the range stayed stale until a
# window resize forced _relayout_now against the LIVE tree. Overflow the viewport by appending,
# then add ONE more row and require the range to grow.
sub viewer_range ($vnode) {
    my $sv;
    my $walk;
    $walk = sub ($n) {
        if ( !$sv && $n->type eq 'scroll_view' ) { $sv = $n }
        else                                     { $walk->($_) for @{ $n->children } }
    };
    $walk->($vnode);
    my $svr = $drv->_get_registry_record( $sv->id );
    return ( $svr, $svr ? ( $svr->{range_v} // 0 ) : 0 );
}
{
    my ( $svr_f, $r_f ) = ( undef, 0 );
    for my $i ( 1 .. 100 ) {
        SendMessageW_BM_CLICK($btn);
        pump();
        drain();
        ( $svr_f, $r_f ) = viewer_range( viewer_node() );
        last if $r_f > 0;
    }
    ok $r_f > 0,                  'a vertical scroll range exists once the content overflows the viewport';
    ok $svr_f && $svr_f->{aux_v}, 'a vertical scrollbar was created for the overflowing content';
    SendMessageW_BM_CLICK($btn);
    pump();
    drain();
    my ( $svr_g, $r_g ) = viewer_range( viewer_node() );
    ok $r_g > $r_f, 'adding a row grows the scroll range without a window resize';
}

# ─── scrollbar geometry: bar spans the viewport, page matches viewport height ───
{
    my $sv;
    my $walk;
    $walk = sub ($n) {
        if ( !$sv && $n->type eq 'scroll_view' ) { $sv = $n }
        else                                     { $walk->($_) for @{ $n->children } }
    };
    $walk->( viewer_node() );
    my $svr = $drv->_get_registry_record( $sv->id );

    sub rect_of ($h) {
        my $r = malloc(16);
        Uji::Driver::Win32::GetWindowRect( $h, $r );
        my @rc = unpack 'l<4', Affix::raw( $r, 16 );
        free($r);
        return @rc;
    }
    my @vp = rect_of( $svr->{hwnd} );
    my @vb = rect_of( $svr->{aux_v} );
    is $svr->{page_v},  $sv->bh,         'scroll page size equals the viewport height';
    is $vb[3] - $vb[1], $vp[3] - $vp[1], 'scrollbar spans the full viewport height';
    is $vb[1],          $vp[1],          'scrollbar top aligns with the viewport top';
    is $vb[0],          $vp[2],          'scrollbar sits flush against the viewport right edge (its own gutter)';
}

# Close both windows.
sub SendMessageW_WM_CLOSE ($h) { Uji::Driver::Win32::SendMessageW( $h, 0x0010, 0, 0 ) }
my $cwin3 = ( grep { $_->title eq 'Controller' } @{ $app->vtrees } )[0];
SendMessageW_WM_CLOSE( $drv->_get_registry_record( $cwin3->id )->{hwnd} );
SendMessageW_WM_CLOSE( $drv->_get_registry_record( $vwin3->id )->{hwnd} );
done_testing;
