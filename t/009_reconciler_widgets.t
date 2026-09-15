use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Reconciler;

# Reconcile a column of spin box / progress bar / toggle switch / toggle button / link button.
# Verifies each property diff routes to a set_prop call with the right value (mock mirrors the
# native-control side), and that widget ids survive the patch.
my $drv    = MockDriver->new;
my $patch  = Uji::Reconciler->new;
my $layout = Uji::Layout->new( driver => $drv );
my $build  = sub ( $level, $min, $max, $step, $bar, $sw_on, $tb_on, $label ) {
    Uji::window(
        id    => 'main',
        title => 't',
        w     => 360,
        h     => 400,
        child => Uji::column(
            padding  => 15,
            spacing  => 12,
            children => [
                Uji::spin_box(
                    value     => $level,
                    min       => $min,
                    max       => $max,
                    step      => $step,
                    on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } }
                ),
                Uji::progress_bar( value => $bar, min => 0, max => 100 ),
                Uji::toggle_switch( label => 'Enabled', checked => $sw_on, on_toggle => sub ($on) { { type => 'TOGGLE_SW', value => $on } } ),
                Uji::toggle_button( label => 'Lock', checked => $tb_on, on_toggle => sub ($on) { { type => 'TOGGLE_LOCK', value => $on } } ),
                Uji::link_button( label => $label, on_click => { type => 'OPEN_LINK' } )
            ]
        )
    );
};
my $old = $build->( 40, 0, 100, 1, 40, 0, 1, 'Docs' );
$drv->mount($old);
$drv->mount_children($old);
$layout->compute( $old, 0, 0, 360, 400 );
my $old_spin = $old->child->children->[0];
my $old_bar  = $old->child->children->[1];
my $old_sw   = $old->child->children->[2];
my $old_tb   = $old->child->children->[3];
my $old_lk   = $old->child->children->[4];
is $drv->checks->{ $old_sw->id }, 0, 'toggle switch starts unchecked in the mock';
is $drv->checks->{ $old_tb->id }, 1, 'toggle button starts checked in the mock';
#
my $new = $build->( 3, -5, 50, 10, 80, 1, 0, 'Visit docs' );
$layout->compute( $new, 0, 0, 360, 400 );
$patch->patch( $old, $new, $drv );
my $new_spin = $new->child->children->[0];
my $new_bar  = $new->child->children->[1];
my $new_sw   = $new->child->children->[2];
my $new_tb   = $new->child->children->[3];
my $new_lk   = $new->child->children->[4];

sub prop_calls ( $id, $prop ) {
    grep { $_->[1] eq $id && $_->[2] eq $prop } @{ $drv->calls };
}
is $new_spin->id, $old_spin->id, 'spin box id preserved across render';
is $new_bar->id,  $old_bar->id,  'progress bar id preserved across render';
is $new_sw->id,   $old_sw->id,   'toggle switch id preserved across render';
is $new_tb->id,   $old_tb->id,   'toggle button id preserved across render';
is $new_lk->id,   $old_lk->id,   'link button id preserved across render';
my @spin_val  = prop_calls( $new_spin->id, 'value' );
my @spin_min  = prop_calls( $new_spin->id, 'min' );
my @spin_max  = prop_calls( $new_spin->id, 'max' );
my @spin_step = prop_calls( $new_spin->id, 'step' );
my @bar_val   = prop_calls( $new_bar->id,  'value' );
my @sw_check  = prop_calls( $new_sw->id,   'checked' );
my @tb_check  = prop_calls( $new_tb->id,   'checked' );
my @lk_label  = prop_calls( $new_lk->id,   'label' );
is scalar @spin_val,  1,            'spin value pushed once';
is $spin_val[-1][3],  3,            'spin value is 3';
is scalar @spin_min,  1,            'spin min pushed once';
is $spin_min[-1][3],  -5,           'spin min is -5';
is scalar @spin_max,  1,            'spin max pushed once';
is $spin_max[-1][3],  50,           'spin max is 50';
is scalar @spin_step, 1,            'spin step pushed once';
is $spin_step[-1][3], 10,           'spin step is 10';
is scalar @bar_val,   1,            'progress value pushed once';
is $bar_val[-1][3],   80,           'progress value is 80';
is scalar @sw_check,  1,            'toggle switch checked pushed once';
is scalar @tb_check,  1,            'toggle button checked pushed once';
is scalar @lk_label,  1,            'link label pushed once';
is $lk_label[-1][3],  'Visit docs', 'link label text updated';

# The mock mirror applied the toggles (set_prop 'checked' branch).
is $drv->checks->{ $new_sw->id }, 1, 'toggle switch mirror now checked';
is $drv->checks->{ $new_tb->id }, 0, 'toggle button mirror now unchecked';

# No stray updates for unchanged props (rerender identical tree issues nothing).
my $calls_before = scalar @{ $drv->calls };
my $same         = $build->( 3, -5, 50, 10, 80, 1, 0, 'Visit docs' );
$layout->compute( $same, 0, 0, 360, 400 );
$patch->patch( $new, $same, $drv );
is scalar @{ $drv->calls }, $calls_before, 'unchanged re-render issues no set_prop calls';
done_testing;
