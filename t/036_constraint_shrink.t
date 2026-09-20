use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::App;

# Minimal channel stand-in so we never spin up Acme::Parataxis in a unit test.
package Canned::Channel {
    use v5.40;
    sub new  { bless { q => [] }, shift }
    sub put  { my ( $s, $m ) = @_; push @{ $s->{q} }, $m; 1 }
    sub get  { my ($s) = @_; shift @{ $s->{q} } }
    sub size { my ($s) = @_; scalar @{ $s->{q} } }
}

# A window whose max_w is applied at RUNTIME via a message. Shrinking the window while it is already
# mounted must re-layout every child; regression for "constraint applied at runtime shrinks the window
# but the layout is not recalculated for everything inside".
my $model0 = { max_w => 0, clicks => 0 };
my $update = sub ( $msg, $model ) {
    $model->{max_w}  = $msg->{max_w}  if $msg->{type} eq 'SET_MAXW';
    $model->{clicks} += 1             if $msg->{type} eq 'CLICK';
    return ( $model, undef );
};
my $view = sub ($model) {
    Uji::window(
        id    => 'main',
        w     => 380,
        h     => 400,
        max_w => $model->{max_w} || 0,
        child => Uji::column(
            padding  => 8,
            children => [
                Uji::text('header'),
                Uji::button( label => 'grow', on_click => { type => 'CLICK' } ),
            ],
        ),
    );
};

my $drv  = MockDriver->new;
my $chan = Canned::Channel->new;
my $app  = Uji::App->new( init => sub { ( $model0, undef ) }, update => $update, view => $view, driver => $drv, channel => $chan );
$app->_boot;    # init + mount + layout

my $all_nodes = sub ($node) {
    my $out = [];
    my $walk;
    $walk = sub ($n) {
        push @$out, $n;
        $walk->($_) for @{ $n->children };
    };
    $walk->($node);
    return $out;
};
my $find_id = sub ( $root, $type, $label ) {
    my @m = grep { $_->type eq $type && ( !$label || $_->label eq $label ) } @{ $all_nodes->($root) };
    return $m[0];
};

my $win    = $app->vtrees->[0];
my $button = $find_id->( $win, 'button', 'grow' );
my $text   = $find_id->( $win, 'text',   'header' );
my $sim    = $drv->sim_size->{ 'main' };

is $sim->{cw}, 360, 'mounted simulated client width is 360';
is $button->bw, 344, 'button laid out at boot: 360 minus 2x8 padding';

# Time passes: a message applies max_w => 200 at runtime. This must shrink the simulated native
# window live (as the Win32 frame clamp does) AND re-layout every control inside it.
$chan->put( { type => 'SET_MAXW', max_w => 200 } );
$app->_drain_and_render( $chan->get );

is $sim->{cw}, 200, 'constraint shrank the simulated native window to 200';

my $win2    = $app->vtrees->[0];
my $button2 = $find_id->( $win2, 'button', 'grow' );
my $text2   = $find_id->( $win2, 'text',   'header' );

is $win2->bw, 200, 'live tree re-measured: window client width is 200 (not stale 360)';
is $button2->bw, 184, 'button re-laid-out to 184 (200 minus 2x8 padding)';
is $text2->bw,   184, 'text re-laid-out to 184 (200 minus 2x8 padding)';

# The real controls must have been MOVED to the new slot, not left at the pre-shrink 344 width.
my @button_moves = grep { $_->[0] eq 'move_widget' && $_->[1] eq $button2->id } @{ $drv->calls };
my $last_w = $button_moves[-1][4];
is $last_w, 184, 'last move_widget for the button uses the shrunken width';

# And a follow-up render with no further constraint change must keep the shrunken geometry (a
# steady-state render still re-moves controls -- the patch always re-issues positions -- but it must
# not reflow everything to a stale size or re-apply the constraint).
my $calls_before = scalar @{ $drv->calls };
$chan->put( { type => 'CLICK' } );
$app->_drain_and_render( $chan->get );
my $win3 = $app->vtrees->[0];
my ( $button3 ) = grep { $_->type eq 'button' } @{ $all_nodes->($win3) };
is $win3->bw, 200, 'steady-state render keeps the shrunken window width';
is $button3->bw, 184, 'steady-state render keeps the shrunken child width';
my @new_sets = grep { $_->[0] eq 'set_prop' } @{ $drv->calls }[ $calls_before .. $#{$drv->calls} ];
is scalar @new_sets, 0, 'steady-state render re-applies no constraint set_prop';

done_testing;