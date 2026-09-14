use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Reconciler;

# Reconcile a column containing checkbox + radio_group. Simulates one render cycle: mount the first
# vtree (registers ids), then patch the second vtree and check driver calls.
my $drv    = MockDriver->new;
my $patch  = Uji::Reconciler->new;
my $layout = Uji::Layout->new( driver => $drv );
my $build  = sub ( $dark, $color ) {
    Uji::window(
        title => 't',
        w     => 360,
        h     => 400,
        child => Uji::column(
            padding  => 15,
            spacing  => 12,
            children => [
                Uji::checkbox( label => 'Dark mode', checked => $dark, on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } } ),
                Uji::text( 'Dark: ' . ( $dark ? 'ON' : 'OFF' ) ),
                Uji::radio_group(
                    value     => $color,
                    options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' } ],
                    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
                )
            ]
        )
    );
};
my $old = $build->( 0, 'blue' );
$drv->mount($old);
$drv->mount_children($old);
$layout->compute( $old, 0, 0, 360, 400 );
my $old_cb  = $old->child->children->[0];
my $old_rg  = $old->child->children->[2];
my $old_rad = $old_rg->children;
is $drv->checks->{ $old_cb->id },       0, 'checkbox starts unchecked';
is $drv->checks->{ $old_rad->[2]->id }, 1, 'blue radio starts selected';
#
my $new = $build->( 1, 'red' );
subtest 'toggle dark on + pick "red"' => sub {
    $layout->compute( $new, 0, 0, 360, 400 );
    $patch->patch( $old, $new, $drv );
    my $new_cb  = $new->child->children->[0];
    my $new_rg  = $new->child->children->[2];
    my $new_rad = $new_rg->children;
    is $new_cb->id,                         $old_cb->id,       'checkbox id preserved across render';
    is $new_rg->id,                         $old_rg->id,       'radio_group id preserved across render';
    is $new_rad->[0]->id,                   $old_rad->[0]->id, 'radio[0] id transferred';
    is $new_rad->[2]->id,                   $old_rad->[2]->id, 'radio[2] id transferred';
    is $drv->checks->{ $new_cb->id },       1,                 'checkbox was checked via set_prop';
    is $drv->checks->{ $new_rad->[0]->id }, 1,                 'red radio selected';
    is $drv->checks->{ $new_rad->[2]->id }, 0,                 'blue radio deselected';
    my @value_calls = grep { $_->[1] eq $new_rg->id && $_->[2] eq 'value' } @{ $drv->calls };
    is scalar @value_calls, 1, 'radio_group value pushed exactly once';
};
subtest 'unchecked + blue again (round-trip)' => sub {
    my $newer = $build->( 0, 'blue' );
    $layout->compute( $newer, 0, 0, 360, 400 );
    $patch->patch( $new, $newer, $drv );
    my $newer_cb  = $newer->child->children->[0];
    my $newer_rg  = $newer->child->children->[2];
    my $newer_rad = $newer_rg->children;
    is $drv->checks->{ $newer_cb->id },       0, 'checkbox unchecked again';
    is $drv->checks->{ $newer_rad->[0]->id }, 0, 'red deselected';
    is $drv->checks->{ $newer_rad->[2]->id }, 1, 'blue reselected';
};
#
done_testing;
