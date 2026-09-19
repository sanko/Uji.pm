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

# A tiny 8x8 solid-black PNG data URI (reuses the toolbar's GDI+ loader for the icon glyph).
my $uri = 'data:image/png;base64,'
    . do { require MIME::Base64; MIME::Base64::encode_base64(
    MIME::Base64::decode_base64(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGP8z8Dwn4EIwERQxQwwAAAoWgHJi0x4WQAAAABJRU5ErkJggg=='
    ), '' ) };

#  1. Node + intrinsic box
subtest 'search_input node exposes its value props and intrinsic size' => sub {
    my $s = Uji::search_input( placeholder => 'Find…', icon => $uri );
    is $s->type, 'search_input', 'type is search_input';
    is $s->value, '', 'default value is empty';
    is $s->placeholder, 'Find…', 'placeholder preserved';
    is $s->icon, $uri, 'icon spec preserved';
    my ($nw, $nh) = $layout->_natural($s);
    ok $nw >= 100, 'intrinsic width is at least 100';
    is $nh, 24, 'intrinsic height is 24';

    my $plain = Uji::search_input();
    my ($pw) = $layout->_natural($plain);
    my ($iw) = $layout->_natural($s);
    ok $iw > $pw, 'an icon widens the intrinsic box (icon + gap + clear strips)';
};

#  2. Live Win32: EDIT + icon glyph + clear button, clear-on-click, EN_CHANGE
my $live = $^O eq 'MSWin32';
SKIP: {
    skip 'Win32 only', 13 unless $live;

    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;
    use Affix qw[:core :types];

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);

    my $on_input  = sub ($txt) { { type => 'SEARCH_TYPED', text => $txt } };
    my $on_search = sub ($txt) { { type => 'SEARCHED',     text => $txt } };
    my $si        = Uji::search_input( placeholder => 'Search…', icon => $uri, on_input => $on_input, on_search => $on_search );
    my $vtree     = Uji::window(
        id    => 'search_main',
        title => 'Search Test',
        w     => 520, h => 160,
        child => Uji::row( padding => 12, spacing => 8, children => [ $si, Uji::button( label => 'Go' ) ] ),
    );
    $drv->mount($vtree);
    my $lay = Uji::Layout->new( driver => $drv );
    $lay->compute( $vtree, 0, 0, 520, 160 );
    $drv->mount_children($vtree);
    my $move_all;
    $move_all = sub {
        my ($n) = @_;
        $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
        $move_all->($_) for @{ $n->children };
    };
    $move_all->($vtree);

    my $sr = $drv->_get_registry_record( $si->id );
    ok $sr && $sr->{hwnd}, 'search field has a registry record with a HWND';
    is lc( $drv->_get_class( $sr->{hwnd} ) ), 'edit', 'edit is an EDIT control';
    ok $sr->{aux}, 'clear button aux exists';
    is lc( $drv->_get_class( $sr->{aux} ) ), 'button', 'clear aux is a BUTTON';
    ok $sr->{icon_hwnd}, 'icon glyph STATIC was created (GDI+ loader ran)';

    # Clear button hidden while the field is empty.
    Affix::affix 'user32', 'IsWindowVisible', [ Pointer [Void] ] => Int;
    ok !IsWindowVisible( $sr->{aux} ), 'clear button hidden while empty';

    #  EN_CHANGE -> on_input
    Affix::affix 'user32', 'GetDlgCtrlID', [ Pointer [Void] ] => Int;
    my $eid = GetDlgCtrlID( $sr->{hwnd} );
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('search_main')->{hwnd}, 0x0111, ( 0x0300 << 16 ) | $eid, 0 );
    my $msg1 = $chan->size ? $chan->get : undef;
    ok $msg1, 'EN_CHANGE dispatches on_input';
    is $msg1->{type}, 'SEARCH_TYPED', 'on_input message type';
    is $msg1->{text}, '', 'empty text reported';

    #  set_prop('value') shows the clear button; typing text via native path
    $drv->set_prop( $si->id, 'value', 'perl' );
    ok IsWindowVisible( $sr->{aux} ), 'clear button visible when the field has text';
    $drv->set_prop( $si->id, 'value', '' );
    ok !IsWindowVisible( $sr->{aux} ), 'clear button hidden again after value cleared';

    #  Simulate clicking ✕: BN_CLICKED with the clear button's control id
    my $clear_id = GetDlgCtrlID( $sr->{aux} );
    ok $clear_id > 0, 'clear button has a control id';
    $drv->set_prop( $si->id, 'value', 'xyz' );
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('search_main')->{hwnd}, 0x0111, $clear_id, 0 );
    my $msg2 = $chan->size ? $chan->get : undef;
    ok $msg2, '✕ click dispatches on_search';
    is $msg2->{type}, 'SEARCHED', 'on_search message type';
    is $msg2->{text}, '', 'on_search fires with the cleared (empty) text';
    is $drv->_get_text( $sr->{hwnd} ), '', 'edit text emptied by the clear button';
    ok !IsWindowVisible( $sr->{aux} ), 'clear button hidden after ✕';

    #  3. Reconcile: changing the icon recreates the field cleanly
    my $old_hwnd = $sr->{hwnd};
    my $recon    = Uji::Reconciler->new;
    my $old_si   = Uji::search_input( id => $si->id, icon => $uri );
    $old_si->set_id( $si->id );
    my $new_si = Uji::search_input( id => $si->id, icon => '', placeholder => 'New…' );
    $new_si->set_id( $si->id );
    $lay->compute( $old_si, $si->bx, $si->by, $si->bw, $si->bh );
    $lay->compute( $new_si, $si->bx, $si->by, $si->bw, $si->bh );
    $recon->patch( $old_si, $new_si, $drv );
    my $sr2 = $drv->_get_registry_record( $si->id );
    ok $sr2 && $sr2->{hwnd}, 'field survives reconcile';
    isnt $sr2->{hwnd}, $old_hwnd, 'icon change recreated the edit';
    ok $sr2->{aux}, 'recreated clear button';
    ok !$sr2->{icon_hwnd}, 'dropping the icon destroyed the glyph STATIC';

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('search_main')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

done_testing;
