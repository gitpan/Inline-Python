use Inline Config => DIRECTORY => './blib_test';

BEGIN {
   print "1..1\n";
}

use Inline Python => <<'END', PRIVATE_PREFIXES => [undef, "_priv_"];

def _priv_function(): return None
def public_function(): return None

END

print "not " if defined &_priv_function;
print "ok 1\n";

