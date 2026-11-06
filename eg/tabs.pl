use v5.40;
use lib 'lib';
use blib;
use Uji qw[:all];
my $init = sub () {
    return (
        {   active_tab  => 0,
            app_name    => 'Uji Application',
            dark_mode   => 0,
            port        => 8080,
            proxy       => 0,
            proxy_host  => '127.0.0.1',
            status_text => 'Ready'
        },
        undef
    );
};
my $update = sub ( $msg, $model ) {
    my $m = {%$model};
    my $t = $msg->{type};
    if    ( $t eq 'CHANGE_TAB' )     { $m->{active_tab} = $msg->{tab}; $m->{status_text} = "Switched to tab $msg->{tab}"; }
    elsif ( $t eq 'SET_NAME' )       { $m->{app_name}   = $msg->{val}; }
    elsif ( $t eq 'SET_DARK' )       { $m->{dark_mode}  = $msg->{val}; }
    elsif ( $t eq 'SET_PORT' )       { $m->{port}       = $msg->{val}; }
    elsif ( $t eq 'SET_PROXY' )      { $m->{proxy}      = $msg->{val}; }
    elsif ( $t eq 'SET_PROXY_HOST' ) { $m->{proxy_host} = $msg->{val}; }
    return ( $m, undef );
};
my $view = sub ($model) {
    window(
        title    => 'Uji TabPanel Demo',
        w        => 520,
        h        => 420,
        centered => 1,
        child    => column(
            padding  => 14,
            spacing  => 10,
            children => [
                tab_panel(
                    selected  => $model->{active_tab},
                    on_select => sub ($idx) { { type => 'CHANGE_TAB', tab => $idx } },
                    flex      => 1,
                    tabs      => [
                        tab(
                            label => 'General',
                            child => column(
                                padding  => 12,
                                spacing  => 10,
                                children => [
                                    text('General Preferences:'),
                                    row(
                                        spacing  => 8,
                                        children => [
                                            text('App Name:'),
                                            text_input(
                                                value    => $model->{app_name},
                                                on_input => sub ($v) { { type => 'SET_NAME', val => $v } },
                                                flex     => 1
                                            )
                                        ]
                                    ),
                                    checkbox(
                                        label     => 'Enable Dark Mode theme',
                                        checked   => $model->{dark_mode},
                                        on_toggle => sub ($v) { { type => 'SET_DARK', val => $v } }
                                    )
                                ]
                            )
                        ),
                        tab(
                            label => 'Network',
                            child => column(
                                padding  => 12,
                                spacing  => 10,
                                children => [
                                    text('Network Settings:'),
                                    row(
                                        spacing  => 8,
                                        children => [
                                            text('Server Port:'),
                                            spin_box(
                                                value     => $model->{port},
                                                min       => 1024,
                                                max       => 65535,
                                                on_change => sub ($v) { { type => 'SET_PORT', val => $v } }
                                            )
                                        ]
                                    ),
                                    checkbox(
                                        label     => 'Use HTTP Proxy',
                                        checked   => $model->{proxy},
                                        on_toggle => sub ($v) { { type => 'SET_PROXY', val => $v } }
                                    ),
                                    row(
                                        spacing  => 8,
                                        children => [
                                            text('Proxy Host:'),
                                            text_input(
                                                value    => $model->{proxy_host},
                                                enabled  => $model->{proxy},
                                                on_input => sub ($v) { { type => 'SET_PROXY_HOST', val => $v } },
                                                flex     => 1
                                            )
                                        ]
                                    )
                                ]
                            )
                        ),
                        tab(
                            label => 'About',
                            child => column(
                                padding  => 12,
                                spacing  => 8,
                                children => [
                                    text('Uji GUI Toolkit - TabPanel Component'),
                                    text('Native Windows Common Controls (SysTabControl32).'),
                                    text('Pages are reconciled dynamically through TEA state loops.')
                                ]
                            )
                        )
                    ]
                ),

                # Bottom status row outside the tab panel
                row( children => [ text("Status: $model->{status_text}"), spacer(), text("Current Tab: $model->{active_tab}") ] )
            ]
        )
    );
};
app( init => $init, update => $update, view => $view )->run();
