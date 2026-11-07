use v5.40;
use Scalar::Util qw[refaddr blessed];

package Uji::Sub v0.0.1 {
    use Exporter qw[import];
    our @EXPORT_OK = qw[
        sub_interval sub_on_resize sub_on_focus sub_on_blur
        sub_on_close_request sub_on_key sub_on_key_chord sub_key
    ];

    # Interval timer: $ms period with a message hashref or dynamic coderef
    sub sub_interval ( $ms, $msg, %opts ) {
        $ms = 1 if !defined $ms || $ms < 1;
        return _normalize( %opts, kind => 'interval', ms => $ms, msg => $msg );
    }

    # Window resize listener
    sub sub_on_resize ( $msg, %opts ) {
        return _normalize( %opts, kind => 'resize', msg => $msg );
    }

    # Keyboard focus listeners (optional: id => 'target_node_id')
    sub sub_on_focus ( $msg, %opts ) {
        return _normalize( %opts, kind => 'focus', msg => $msg );
    }

    sub sub_on_blur ( $msg, %opts ) {
        return _normalize( %opts, kind => 'blur', msg => $msg );
    }

    # Window close listener (returning a defined command or veto cancels window closure)
    sub sub_on_close_request ( $msg, %opts ) {
        return _normalize( %opts, kind => 'close_request', msg => $msg );
    }

    # Key chords e.g. 'ctrl+shift+s'
    sub sub_on_key ( $chord, $msg, %opts ) {
        return _normalize( %opts, kind => 'key_chord', chord => $chord, msg => $msg );
    }

    sub sub_on_key_chord ( $chord, $msg, %opts ) {
        return _normalize( %opts, kind => 'key_chord', chord => $chord, msg => $msg );
    }

    sub _normalize (%spec) {
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
            $key = defined $2 ? "f$2" : $1;
            $key = 'esc'    if $key eq 'escape';
            $key = 'enter'  if $key eq 'return';
            $key = 'delete' if $key eq 'del';
        }
        return '' unless defined $key;
        return $mods ? "$mods+$key" : $key;
    }

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
