use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Uji::Layout;
use Affix qw[:memory :core :types];
use Acme::Parataxis::Channel;
use Encode qw[decode encode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# ─── utf8everywhere boundary contract ────────────────────────────────────
# Perl strings may arrive as bare UTF-8 octets (no utf8 flag -- the default for literals in a
# source without `use utf8`, and for file data) or as flagged character strings. The drivers
# normalise both to Unicode at the WString boundary (_nz) and return decoded Unicode on reads.
# These tests pin that contract so a regressing call site can't reintroduce Latin-1 mojibake
# (a "…" must never come back as U+00E2 U+0080 U+00A6, the vertical-bar symptom).

my $chan = Acme::Parataxis::Channel->new( capacity => 8 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);

my $ellipsis_octets = "\xE2\x80\xA6";                    # "…" WITHOUT the utf8 flag
my $ellipsis        = decode( 'UTF-8', $ellipsis_octets );    # flagged U+2026

# ── 1. Button label: raw UTF-8 octets round-trip to the real character ──
my $vt = Uji::window(
    title => 'utf8',
    w     => 320,
    h     => 200,
    child => Uji::column(
        padding  => 10,
        children => [
            Uji::button( label => "Open$ellipsis_octets", id => 101 ),
            Uji::text( "Save$ellipsis_octets",           id => 102 ),
        ],
    ),
);
$drv->mount($vt);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vt, 0, 0, 320, 200 );
$drv->mount_children($vt);

sub hwnd_text ($id) {
    my $rec = $drv->_get_registry_record($id);
    my $len = Uji::Driver::Win32::GetWindowTextLengthW( $rec->{hwnd} );
    my $buf = malloc( ( $len + 1 ) * 2 );
    Uji::Driver::Win32::GetWindowTextW( $rec->{hwnd}, $buf, $len + 1 );
    my $s = decode( 'UTF-16LE', Affix::raw( $buf, $len * 2 ) );
    free($buf);
    return $s;
}

is hwnd_text(101), 'Open' . $ellipsis, 'button label: raw UTF-8 octets render the real ellipsis';
is hwnd_text(102), 'Save' . $ellipsis, 'static text: raw UTF-8 octets render the real ellipsis';

# ── 2. Window title: raw UTF-8 octets ────────────────────────────────────
{
    my $vt2 = Uji::window( title => $ellipsis_octets, w => 200, h => 100, child => Uji::column() );
    $drv->mount($vt2);
    my $rec = $drv->_get_registry_record( $vt2->id );
    my $len = Uji::Driver::Win32::GetWindowTextLengthW( $rec->{hwnd} );
    my $buf = malloc( ( $len + 1 ) * 2 );
    Uji::Driver::Win32::GetWindowTextW( $rec->{hwnd}, $buf, $len + 1 );
    my $s = decode( 'UTF-16LE', Affix::raw( $buf, $len * 2 ) );
    free($buf);
    is $s, $ellipsis, 'window title: raw UTF-8 octets round-trip to the real ellipsis';
    Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

# ── 3. measure_text normalises before measuring (octets == characters) ───
{
    my ( $wo, $ho ) = $drv->measure_text($ellipsis_octets);
    my ( $w,  $h )  = $drv->measure_text($ellipsis);
    is $wo, $w, 'measure_text: octet string and character string measure identical';
    ok $w > 0,                   'measure_text returns a non-zero width for the ellipsis';
    ok $w < 40, 'ellipsis measures like one glyph, not three Latin-1 letters';
}

# ── 4. Text input value: characters round-trip through the native edit ───
{
    my $vt3 = Uji::window(
        title => 'utf8-edit',
        w     => 300,
        h     => 150,
        child => Uji::column( padding => 10, children => [ Uji::text_input( id => 201, value => "caf\xC3\xA9 $ellipsis_octets done" ) ] ),
    );
    $drv->mount($vt3);
    my $layout3 = Uji::Layout->new( driver => $drv );
    $layout3->compute( $vt3, 0, 0, 300, 150 );
    $drv->mount_children($vt3);
    my $back   = $drv->_get_text( $drv->_get_registry_record(201)->{hwnd} );
    my $expect = decode( 'UTF-8', "caf\xC3\xA9 ${ellipsis_octets} done" );
    is $back, $expect, 'edit value: octet input round-trips to the same characters';
    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record( $vt3->id )->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

done_testing;