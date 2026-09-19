use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Acme::Parataxis::Channel;
use Affix  qw[:memory :core :types];
use Encode qw[decode encode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';
my $drv = Uji::Driver::Win32->new;
$drv->init( Acme::Parataxis::Channel->new( capacity => 8 ) );

#  1. Filter string: "Label|*.ext|All|*.*" form
{
    my $blob = $drv->_ofn_filter_string("Text|*.txt|All|*.*");
    my $utf8 = encode( 'UTF-8', decode( 'UTF-16LE', $blob ) );

    # Pairs joined by \0 with a trailing \0: "Text\0*.txt\0All\0*.*\0\0"
    is $utf8, "Text\x00*.txt\x00All\x00*.*\x00\x00", 'string filter builds double-NUL pair blob';
}

#  2. Filter string: arrayref-of-pairs form
{
    my $blob = $drv->_ofn_filter_string( [ [ 'Perl', '*.pl' ], [ 'All', '*.*' ] ] );
    my $utf8 = encode( 'UTF-8', decode( 'UTF-16LE', $blob ) );
    is $utf8, "Perl\x00*.pl\x00All\x00*.*\x00\x00", 'arrayref filter builds double-NUL pair blob';
}

#  3. Filter string: default when omitted
{
    my $blob = $drv->_ofn_filter_string(undef);
    is $blob, encode( 'UTF-16LE', "All files\x00*.*\x00\x00" ), 'omitted filter defaults to All files|*.*';
}

#  4. OPENFILENAMEW struct: valid field offsets + size 152 (x64)
{
    my ( $ptr, $parts ) = $drv->_ofn_build( 'open', title => 'Open', filter => 'T|*.t' );
    my $ofn = $parts->[0];

    # lStructSize at 0, hwndOwner at 8, lpstrFile at 48, nMaxFile at 56, Flags at 96
    my $u32 = sub ($off) { unpack 'V', substr( Affix::raw( $ptr, 152 ), $off, 4 ) };
    is $u32->(0),  152,   'lStructSize = 152';
    is $u32->(56), 32768, 'nMaxFile = 32768';

    # Pointer fields must be REAL buffer addresses (integer), not Affix SV addresses.
    ok $ofn->{lpstrFile},   'lpstrFile set';
    ok $ofn->{lpstrFilter}, 'lpstrFilter set';
    is $ofn->{Flags} & 0x80000, 0x80000, 'OFN_EXPLORER set for open';
    is $ofn->{Flags} & 0x1000,  0x1000,  'OFN_FILEMUSTEXIST set for open';
    is $ofn->{Flags} & 0x200,   0,       'no OFN_ALLOWMULTISELECT by default';
    $drv->_ofn_free( $ptr, $parts );
}

#  5. OPENFILENAMEW: multi-select + no-file-must-exist flags
{
    my ( $ptr, $parts ) = $drv->_ofn_build( 'open', multi => 1, no_file_must_exist => 1 );
    is $parts->[0]{Flags} & 0x200,  0x200, 'OFN_ALLOWMULTISELECT set with multi => 1';
    is $parts->[0]{Flags} & 0x1000, 0,     'OFN_FILEMUSTEXIST cleared with no_file_must_exist';
    $drv->_ofn_free( $ptr, $parts );
}

#  6. OPENFILENAMEW: save-defaults (OVERWRITEPROMPT on, FILEMUSTEXIST off)
{
    my ( $ptr, $parts ) = $drv->_ofn_build('save');
    is $parts->[0]{Flags} & 0x2,    0x2, 'OFN_OVERWRITEPROMPT set for save';
    is $parts->[0]{Flags} & 0x1000, 0,   'no OFN_FILEMUSTEXIST for save';
    $drv->_ofn_free( $ptr, $parts );
}

#  7. Result parsing: single file
{
    my $buf = calloc( 512, 1 );
    my $raw = encode( 'UTF-16LE', "C:\\docs\\a.txt\x00" );
    memcpy( $buf, $raw, length $raw );
    is $drv->_ofn_parse_result( $buf, 1024, 0 ), 'C:\docs\a.txt', 'single-select result is one path';
}

#  8. Result parsing: multi-file (explorer double-NUL form)
{
    my $buf = calloc( 512, 1 );
    my $raw = encode( 'UTF-16LE', "C:\\docs\x00a.txt\x00b.txt\x00\x00" );
    memcpy( $buf, $raw, length $raw );
    my $got = $drv->_ofn_parse_result( $buf, 1024, 1 );
    is $got, [ 'C:\docs\a.txt', 'C:\docs\b.txt' ], 'multi-select result is full paths';
}

#  9. Result parsing: trailing zero padding from the buffer is ignored
{
    my $buf = calloc( 512, 1 );
    my $raw = encode( 'UTF-16LE', "C:\\docs\x00a.txt\x00\x00\x00\x00\x00" );
    memcpy( $buf, $raw, length $raw );
    my $got = $drv->_ofn_parse_result( $buf, 1024, 0 );
    is $got, 'C:\docs', 'single-select result trims trailing NUL padding';
}

#  10. MessageBox flag mapping
{
    is $drv->_mb_flags(), 0x0, 'default buttons => MB_OK';
    is $drv->_mb_flags( buttons => 'okcancel' ),         0x1, 'okcancel => MB_OKCANCEL';
    is $drv->_mb_flags( buttons => 'yesno' ),            0x4, 'yesno => MB_YESNO';
    is $drv->_mb_flags( buttons => 'yesnocancel' ),      0x3, 'yesnocancel => MB_YESNOCANCEL';
    is $drv->_mb_flags( buttons => 'abortretryignore' ), 0x2, 'abortretryignore => MB_ABORTRETRYIGNORE';
    is $drv->_mb_flags( buttons => 'retrycancel' ),      0x5, 'retrycancel => MB_RETRYCANCEL';
}

#  11. MessageBox icon + default-button flags
{
    my $f = $drv->_mb_flags( buttons => 'okcancel', icon => 'question', default => 2 );
    is $f, 0x1 | 0x20 | 0x100, 'icon question + default 2 combine';
    my $g = $drv->_mb_flags( buttons => 'yesno', icon => 'error', default => 3 );
    is $g, 0x4 | 0x10 | 0x200, 'icon error + default 3 combine';
}

#  12. Base driver declares the dialog contract
{
    my $base = Uji::Driver->can('message_box');
    ok $base,                                'Uji::Driver exposes message_box';
    ok Uji::Driver->can('file_open_dialog'), 'Uji::Driver exposes file_open_dialog';
    ok Uji::Driver->can('file_save_dialog'), 'Uji::Driver exposes file_save_dialog';
    ok Uji::Driver->can('color_picker'),     'Uji::Driver exposes color_picker';
    ok Uji::Driver->can('prompt_dialog'),    'Uji::Driver exposes prompt_dialog';
}

#  13. prompt_dialog: OK captures edited text via the test-only hook seam
{
    my $got = $drv->prompt_dialog(
        title   => 'Name',
        message => 'Enter it:',
        default => 'fallback',
        hook    => sub ( $dlg, $edit ) {
            Uji::Driver::Win32::SetWindowTextW( $edit, 'typed-value' );
            Uji::Driver::Win32::SendMessageW( $dlg, 0x0111, 1, 0 );    # WM_COMMAND OK (id 1)
        },
    );
    is $got, 'typed-value', 'prompt_dialog returns the edited text on OK';
}

#  14. prompt_dialog: cancel returns undef
{
    my $got = $drv->prompt_dialog(
        title => 'Name',
        hook  => sub ( $dlg, $edit ) { Uji::Driver::Win32::SendMessageW( $dlg, 0x0111, 2, 0 ) },    # WM_COMMAND Cancel
    );
    ok !defined $got, 'prompt_dialog returns undef on cancel';
}

#  15. prompt_dialog: pre-filled default appears in the edit
{
    my $got = $drv->prompt_dialog(
        default => 'prefilled',
        hook    => sub ( $dlg, $edit ) { Uji::Driver::Win32::SendMessageW( $dlg, 0x0111, 1, 0 ) },    # OK leaves default untouched
    );
    is $got, 'prefilled', 'prompt_dialog returns the pre-filled default when unchanged';
}

#  16. A SECOND driver instance runs its own prompt_dialog independently
# Regression for the window-class collision: RegisterClassExW no-ops on an existing class name,
# so before per-instance class names the second driver's prompt window re-used the FIRST
# driver's wndproc (writing the first driver's prompt_done flag), and the modal pump never saw
# its own flag -> OK/Cancel did nothing. Unique class names keep each instance self-contained.
{
    my $d2 = Uji::Driver::Win32->new;
    $d2->init( Acme::Parataxis::Channel->new( capacity => 8 ) );
    my $got = $d2->prompt_dialog(
        title => 'Second',
        hook  => sub ( $dlg, $edit ) {
            Uji::Driver::Win32::SetWindowTextW( $edit, 'second-driver' );
            Uji::Driver::Win32::SendMessageW( $dlg, 0x0111, 1, 0 );
        },
    );
    is $got, 'second-driver', 'a second driver instance closes and returns its own prompt value';
}

done_testing;
