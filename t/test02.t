use Inline Config => DIRECTORY => './blib_test';

BEGIN {
   print "1..4\n";
}

use Inline Python => 't/test02.py';
my $failed = 0;

print "not " unless (add(10,20) == 10 + 20);
print "ok 1\n";

print "not " unless (subtract(10,20) == 10 - 20);
print "ok 2\n";

print "not " unless (multiply(13,76) == 13*76);
print "ok 3\n";

print "not " unless (divide(12,4) == 12/4);
print "ok 4\n";

