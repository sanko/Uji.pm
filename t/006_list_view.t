use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji;
use Uji::Driver::Win32;
use Uji::Reconciler;
use Acme::Parataxis::Channel;
use Affix  qw[:memory :types :core];
use Encode qw[decode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';
typedef LVITEMW_TEST => Struct [
    mask       => UInt,
    iItem      => Int,
    iSubItem   => Int,
    state      => UInt,
    stateMask  => UInt,
    pszText    => Pointer [Void],
    cchTextMax => Int,
    iImage     => Int,
    lParam     => SSize_t
];
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my @columns = (
    { id => 'pid',    text => 'PID',          width => 75,  align => 'right' },
    { id => 'name',   text => 'Process Name', width => 200, align => 'left' },
    { id => 'status', text => 'Status',       width => 100, align => 'center' }
);
my $build = sub ($rows) {
    Uji::window(
        title => 'listview test',
        w     => 640,
        h     => 480,
        child => Uji::column(
            padding  => 12,
            spacing  => 8,
            children => [
                Uji::list_view(
                    flex      => 1,
                    columns   => \@columns,
                    rows      => $rows,
                    selected  => -1,
                    on_select => sub ( $idx, $row ) { { type => 'SELECT', idx => $idx } }
                )
            ]
        )
    );
};

sub row_count {
    my ($lv) = @_;
    return Uji::Driver::Win32::SendMessageW( $lv, 0x1004, 0, 0 );    # LVM_GETITEMCOUNT
}

sub column_count {
    my ($lv)   = @_;
    my $header = Uji::Driver::Win32::SendMessageW( $lv, 0x101F, 0, 0 );                # LVM_GETHEADER
    return $header ? Uji::Driver::Win32::SendMessageW( $header, 0x1200, 0, 0 ) : 0;    # HDM_GETITEMCOUNT
}

sub cell_text {
    my ( $lv, $row, $col ) = @_;
    my $buf = malloc(512);
    my $ip  = malloc( sizeof( LVITEMW_TEST() ) );
    my $it  = cast( $ip, LVITEMW_TEST() );
    $it->{mask}       = 0x0001;                                                               # LVIF_TEXT
    $it->{iItem}      = $row;
    $it->{iSubItem}   = $col;
    $it->{pszText}    = $buf;
    $it->{cchTextMax} = 256;
    my $n    = Uji::Driver::Win32::SendMessageW( $lv, 0x1073, $row, Affix::address($ip) );    # LVM_GETITEMTEXTW
    my $text = $n > 0 ? decode( 'UTF-16LE', Affix::raw( $buf, $n * 2 ) ) : '';
    free($buf);
    free($ip);
    return $text;
}
my @rows  = ( { pid => '1048', name => 'perl.exe', status => 'Running' }, { pid => '2104', name => 'chrome.exe', status => 'Idle' } );
my $vtree = $build->( \@rows );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute($vtree);
$drv->mount_children($vtree);
my $lv_node = $vtree->child->children->[0];
my $lv      = $drv->_get_registry_record( $lv_node->id )->{hwnd};
ok $lv, 'list view has a real HWND';
is column_count($lv),      3,          'columns populated at mount';
is row_count($lv),         2,          'rows populated at mount';
is cell_text( $lv, 0, 1 ), 'perl.exe', 'initial cell text is native';

# Adding a row re-renders and repopulates both columns and items.
my @more = ( @rows, { pid => '3840', name => 'code.exe', status => 'Running' } );
my $new  = $build->( \@more );
$drv->sync_window_bounds($new);
$layout->compute($new);
Uji::Reconciler->new->patch( $vtree, $new, $drv );
is column_count($lv), 3, 'columns preserved after add';
is row_count($lv),    3, 'rows repopulated after add';

# Editing a cell without changing the row count also repopulates.
my @edited = @more;
$edited[1] = { %{ $edited[1] }, status => 'Suspended' };
my $newer = $build->( \@edited );
$drv->sync_window_bounds($newer);
$layout->compute($newer);
Uji::Reconciler->new->patch( $new, $newer, $drv );
is row_count($lv),         3,           'rows stay populated after editing a cell';
is cell_text( $lv, 1, 2 ), 'Suspended', 'replaced status cell pushed to the native control';

# Mutating a model row in place must still be detected: ListView nodes snapshot their data.
$edited[0]{name} = 'perl5.40.exe';
my $inplace = $build->( \@edited );
$drv->sync_window_bounds($inplace);
$layout->compute($inplace);
Uji::Reconciler->new->patch( $newer, $inplace, $drv );
is cell_text( $lv, 0, 1 ), 'perl5.40.exe', 'in-place row mutation pushed to the native control';

# The table must also survive a filter that shrinks it.
my @filtered = ( $edited[0] );
my $filtered = $build->( \@filtered );
$drv->sync_window_bounds($filtered);
$layout->compute($filtered);
Uji::Reconciler->new->patch( $newer, $filtered, $drv );
is row_count($lv), 1, 'rows repopulated after filter shrinks the table';
Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record( $vtree->id )->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;
