use Inline Config => BLIB => './blib_test';

BEGIN {
    print "1..4\n";
}

use Inline Python => <<END;

import sys
import re

def match(str, regex):
    f = re.compile(regex);
    if f.match(str): return 1
    return 0

def print_test(x): print "ok %s" % x

END

print "not " unless match("abcabcabc",'(abc)*');
print "ok 1\n";

print "not " if match("debracox",'(abc)+');
print "ok 2\n";

print_test(3);
print_test(4);
