use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Uji::Layout;
use Uji::Reconciler;
use Acme::Parataxis::Channel;
use Uji::Node::Row;
use Uji::Node::Text;
use Uji::Node::Spacer;
use Uji::Node::Button;
use Affix;
Affix::affix 'user32', 'SendMessageW', [ Pointer[Void], UInt, Size_t, SSize_t ] => Int;

skip_all 'Win32 only' unless $^O eq 'MSWin32';

my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $layout = Uji::Layout->new( driver => $drv );

my $find;
$find = sub ($n, $id) {
    return $n if $n->id eq $id;
    for my $k ( @{ $n->children } ) { my $r = $find->( $k, $id ); return $r if $r; }
    return undef;
};

#  1. Pure structure: intrinsic size + row layout of a composed month
{
    my $cal = Uji::calendar( month => '2026-05', value => '2026-05-04' );
    my $i   = [ $layout->_intrinsic($cal) ];
    is $i, [ 232, 200 ], 'calendar intrinsic size is 232x200';

    my $rows = $cal->children;
    is scalar @$rows, 8, 'grid is 8 rows (header + weekday + 6 week rows)';
    is $rows->[0]->type, 'row', 'row 0 (header) is a row';
    is $rows->[0]->spacing, 2, 'header row uses 2px spacing';
    is scalar @{ $rows->[0]->children }, 3, 'header has prev / title / next';
    is $rows->[0]->children->[0]->label, "\xE2\x97\x80", 'prev is a ◀ button';
    is $rows->[0]->children->[2]->label, "\xE2\x96\xB6", 'next is a ▶ button';
    is $rows->[0]->children->[1]->label, 'May 2026', 'title shows month + year';
    is $rows->[0]->children->[1]->flex, 1, 'title flexes to center';

    is scalar @{ $rows->[1]->children }, 7, 'weekday row has 7 columns';
    is join( '', map { $_->label } @{ $rows->[1]->children } ), 'SMTWTFS', 'weekday letters SMTWTFS';
    is $rows->[1]->spacing, 2, 'weekday row uses 2px spacing';

    # May 2026: first day is a Friday -> 5 leading blanks then 1, 2.
    my @w0 = map { $_->can('label') ? $_->label // '' : '' } @{ $rows->[2]->children };
    is \@w0, [ '', '', '', '', '', '1', '2' ], 'week 1 shows leading blanks for Friday 1st';
    is $rows->[2]->spacing, 0, 'week rows are at 0 spacing';

    my $day   = $find->( $cal, $cal->id . '-day-2026-05-04' );
    ok $day, 'the selected day cell exists';
    isa_ok $day, 'Uji::Node::Button';
    is $day->label, '4', 'day cell label is the day number';
    is $day->background, '#BBD8F4', 'selected day is highlighted';
    my $other = $find->( $cal, $cal->id . '-day-2026-05-17' );
    is $other->background, undef, 'a non-selected day has no highlight';
    my $blank = $find->( $cal, $cal->id . '-blank-0-0' );
    isa_ok $blank, 'Uji::Node::Spacer';
    is $blank->w, 28, 'blank cells size like day cells';
}

#  2. Month math: leap years and the weekday of the 1st
{
    my $feb24 = Uji::calendar( month => '2024-02' );
    ok  $find->( $feb24, $feb24->id . '-day-2024-02-29' ), '2024 is a leap year (Feb 29 exists)';
    ok !$find->( $feb24, $feb24->id . '-day-2024-02-30' ), 'leap February stops at 29 days';
    my $feb26 = Uji::calendar( month => '2026-02' );
    ok !$find->( $feb26, $feb26->id . '-day-2026-02-29' ), '2026-02 has only 28 days';

    # Jan 2000 started on a Saturday (6), May 2026 on a Friday (5).
    my $c = Uji::calendar( month => '2000-01' );
    my $c2 = Uji::calendar( month => '2026-05' );
    my $b0 = $find->( $c, $c->id . '-blank-0-0' );
    my $b02 = $find->( $c2, $c2->id . '-blank-0-0' );
    ok $b0, 'Jan 2000 leads with blanks';
    my $jan_blanks = grep { $_->type eq 'spacer' } @{ $c->children->[2]->children };
    is $jan_blanks, 6, 'Jan 1 2000 was a Saturday (6 leading blanks)';
    is $c2->children->[2]->children->[5]->label // '', '1', 'May 1 2026 falls in the Friday column';
}

#  3. min / max disable day cells outside the range
{
    my $cal = Uji::calendar( month => '2026-05', min => '2026-05-10', max => '2026-05-20' );
    ok !$find->( $cal, $cal->id . '-day-2026-05-09' )->enabled, 'a day before min is disabled';
    ok  $find->( $cal, $cal->id . '-day-2026-05-10' )->enabled, 'a day at min is enabled';
    ok  $find->( $cal, $cal->id . '-day-2026-05-20' )->enabled, 'a day at max is enabled';
    ok !$find->( $cal, $cal->id . '-day-2026-05-21' )->enabled, 'a day after max is disabled';
}

#  4. Live driver: selection and month navigation over WM_COMMAND
my @seen;
my $cal_live = Uji::calendar(
    month     => '2026-05',
    value     => '2026-05-04',
    on_select => sub ($iso) { push @seen, $iso; { type => 'PICKED', value => $iso } },
    on_nav    => sub ($d)    { { type => 'NAV', delta => $d } },
);
my $win = Uji::window( id => 'cal_main', title => 'Calendar', w => 300, h => 330, child => $cal_live );
$drv->mount($win);
$layout->compute( $win, 0, 0, 300, 330 );
$drv->mount_children($win);
my $move_all;
$move_all = sub ($n) {
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    $move_all->($_) for @{ $n->children };
};
$move_all->($win);
my $winrec = $drv->_get_registry_record( $win->id );
my $click  = sub ($id) {
    my $rec = $drv->_get_registry_record($id) or return undef;
    Uji::Driver::Win32::SendMessageW( $winrec->{hwnd}, 0x0111, $rec->{cid} & 0xFFFF, $rec->{hwnd} );
    return 1;
};

{
    my $rec = $drv->_get_registry_record( $cal_live->id . '-day-2026-05-04' );
    ok $rec && $rec->{hwnd}, 'the composed day cell mounts as a real button';
    my $cid = $rec->{cid};
    ok $cid >= 0x6000, "generated children get a numeric id from the 0x6000 allocator ($cid)";
    $chan->get() while $chan->size;

    $click->( $cal_live->id . '-day-2026-05-17' );
    my $m = $chan->get;
    is $m->{type},  'PICKED', 'clicking a day dispatches on_select';
    is $m->{value}, '2026-05-17', 'on_select carries the ISO date';
    is \@seen, [ '2026-05-17' ], 'on_select callback gets the picked ISO date';

    $chan->get() while $chan->size;
    $click->( $cal_live->id . '-nav-prev' );
    my $p = $chan->get;
    is $p->{type}, 'NAV', 'clicking ◀ dispatches on_nav';
    is $p->{delta}, -1, '◀ reports delta -1';
    $chan->get() while $chan->size;
    $click->( $cal_live->id . '-nav-next' );
    is $chan->get->{delta}, 1, '▶ reports delta +1';
    $chan->get() while $chan->size;
}

#  5. Reconcile a new month: cells swap without leaking old records
{
    $chan->get() while $chan->size;
    my $old_cal = Uji::calendar( id => 'mc', month => '2026-05', value => '2026-05-04' );
    my $old_win = Uji::window( id => 'cal_main', title => 'Calendar', w => 300, h => 330, child => $old_cal );
    $drv->mount($old_win);
    $layout->compute( $old_win, 0, 0, 300, 330 );
    $drv->mount_children($old_win);
    ok $drv->_get_registry_record( $old_cal->id . '-day-2026-05-04' ), 'May grid mounts before reconcile';

    my $new_cal = Uji::calendar( id => 'mc', month => '2026-06', value => '2026-06-01' );
    my $new_win = Uji::window( id => 'cal_main', title => 'Calendar', w => 300, h => 330, child => $new_cal );
    my $recon = Uji::Reconciler->new;
    $recon->patch_windows( [ $old_win ], [ $new_win ], $drv );
    ok !$drv->_get_registry_record( 'mc-day-2026-05-04' ), 'old-month day cells are unmounted';
    ok  $drv->_get_registry_record( 'mc-day-2026-06-01' ), 'the new month mounts fresh day cells';
    ok !$drv->_get_registry_record( 'mc-day-2026-06-31' ), 'June 2026 has no day 31';
    my $j1 = $find->( $new_cal, $new_cal->id . '-day-2026-06-01' );
    is $j1->background, '#BBD8F4', 'the selected day highlights again after reconcile';
    ok $drv->_get_registry_record( $cal_live->id . '-day-2026-05-04' ), 'the live window from section 4 is left untouched';
}

Uji::Driver::Win32::SendMessageW( $winrec->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
done_testing;
