use v5.40;
use Scalar::Util qw[refaddr blessed];

package Uji::Sub v0.0.1 {

    # Subscription descriptors are plain hashrefs produced by the sub_* helpers. Uji::App
    # diffs them by C<key> against the running set each render: a sub whose key disappears is
    # stopped, a brand-new key is started (interval timers get their first due time), and a
    # surviving interval keeps its phase while its message closure is refreshed.
    use Exporter qw[import];
    our @EXPORT_OK
        = qw[sub_interval sub_on_resize sub_on_focus sub_on_blur sub_on_close_request sub_on_key sub_on_key_chord sub_key];

    # sub_interval( $ms, $msg, %opts )
    #   $ms   milliseconds between firings (rounded up to 1)
    #   $msg  a message hashref, or a coderef called as $msg->($now_ms) returning one
    #   %opts id => '...' to disambiguate two structurally identical subs
    sub sub_interval ( $ms, $msg, %opts ) {
        $ms = 1 if !defined $ms || $ms < 1;
        return _normalize( %opts, kind => 'interval', ms => $ms, msg => $msg );
    }

    # sub_on_resize( $msg, %opts )
    #   Fires whenever the platform delivers a RESIZE event; same $msg shapes as above.
    sub sub_on_resize ( $msg, %opts ) {
        return _normalize( %opts, kind => 'resize', msg => $msg );
    }

    # sub_on_focus( $msg, %opts )
    #   Fires whenever keyboard focus lands on a widget (or the window itself). Pass
    #   id => 'widget-id' to scope the subscription to one widget; without an id it fires
    #   for every focus gain (the event carries the node id via the FOCUS transport).
    sub sub_on_focus ( $msg, %opts ) {
        return _normalize( %opts, kind => 'focus', msg => $msg );
    }

    # sub_on_blur( $msg, %opts )
    #   Fires whenever a widget (or the window) loses keyboard focus; id scoping works as
    #   sub_on_focus (the BLUR transport carries the node id).
    sub sub_on_blur ( $msg, %opts ) {
        return _normalize( %opts, kind => 'blur', msg => $msg );
    }

    # sub_on_close_request( $msg, %opts )
    #   Fires when the user asks to close a window (title-bar X, Alt+F4, WM_CLOSE). The
    #   window only closes when the update() handling this message returns undef; returning
    #   ANY value vetoes the close and the window stays open. Without a subscription the
    #   platform default applies and the window simply closes.
    sub sub_on_close_request ( $msg, %opts ) {
        return _normalize( %opts, kind => 'close_request', msg => $msg );
    }

    # sub_on_key( $chord, $msg, %opts ) / sub_on_key_chord( $chord, $msg, %opts )
    #   Fires when the focused window sees a keyboard chord. $chord is spelled like
    #   'ctrl+shift+a' (case-insensitive; modifiers in ctrl/alt/shift order via _norm_chord).
    #   sub_on_key_chord is an alias for the same builder.
    sub sub_on_key ( $chord, $msg, %opts ) {
        return _normalize( %opts, kind => 'key_chord', chord => $chord, msg => $msg );
    }

    sub sub_on_key_chord ( $chord, $msg, %opts ) {
        return _normalize( %opts, kind => 'key_chord', chord => $chord, msg => $msg );
    }

    sub _normalize ( %spec ) {
        my $msg = $spec{msg};
        $spec{key} = sub_key( $spec{kind}, $spec{id}, $spec{ms}, $msg, $spec{chord} );
        return \%spec;
    }

    sub sub_key ( $kind, $id, $ms, $msg, $chord = undef ) {
        my @parts = ( $kind, defined $id ? $id : () );
        push @parts, $ms if defined $ms;
        my $nc = _norm_chord($chord);
        push @parts, $nc if length $nc;
        my $fp = _fingerprint($msg);
        push @parts, $fp if defined $fp;
        return join ':', @parts;
    }

    # Canonical form for a keyboard chord: lowercased, modifiers in ctrl/alt/shift order,
    # known key-name spellings mapped to the driver's names. The Win32 driver normalizes the
    # chords it emits with the same rules, so a model-time string and an emitted event agree.
    sub _norm_chord ($chord) {
        return '' unless defined $chord;
        my $c = lc $chord;
        my %mod;
        $mod{ctrl}  = 1 if $c =~ /\b(ctrl|control|cmd|meta|super|win)\b/;
        $mod{alt}   = 1 if $c =~ /(?:^|[+\-\s])alt(?:$|[+\-\s])/;
        $mod{shift} = 1 if $c =~ /\bshift\b/;
        my $mods = join '+', map { $mod{$_} ? $_ : () } qw[ctrl alt shift];
        my $key;
        if ( $c =~ /(?:^|[+\-\s])([0-9a-z])(?:$|[+\-\s])/ ) {
            $key = $1;
        }
        elsif ( $c =~ /\b(esc|escape|enter|return|space|tab|backspace|del|delete|insert|home|end|pgup|pgdn|up|down|left|right|f([0-9]{1,2}))\b/ ) {
            $key      = defined $2 ? "f$2" : $1;
            $key      = 'esc'   if $key eq 'escape';
            $key      = 'enter' if $key eq 'return';
            $key      = 'delete' if $key eq 'del';
        }
        return '' unless defined $key;
        return $mods ? "$mods+$key" : $key;
    }

    # A stable string for a plain-data message so that re-building the same hashref each render
    # yields the same key. Coderefs (and odd blessed refs) have no stable value, so they are
    # deliberately not part of the key -- pass id => '...' to keep two such subs distinct.
    sub _fingerprint ($v) {
        return undef unless defined $v;
        return undef if ref $v eq 'CODE';
        if ( ref $v eq 'HASH' ) {
            return '{' . join( ',', map { $_ . '=' . ( _fingerprint( $v->{$_} ) // '~' ) } sort keys %$v ) . '}';
        }
        if ( ref $v eq 'ARRAY' ) {
            return '[' . join( ',', map { _fingerprint($_) // '~' } @$v ) . ']';
        }
        return $v unless ref $v;
        return blessed($v) ? join( '=', ref $v, refaddr($v) ) : undef;
    }
};
1;