use Inline Config => BLIB => './blib_test';

BEGIN {
   print "1..3\n";
}

use Inline Python => 'DATA';

my $o = new Neil;
print "not " unless interesting($o)==0;
print "ok 1\n";

print "not " unless interesting({neil=>'cool', happy=>'sad'})==0;
print "ok 2\n";

print "not " unless $o->foof(0) == 1.75;
print "ok 3\n";

__END__

__Python__

class Neil:
   def __init__(self):
      print "New Neil being created"
   def foof(self,a):
      print "foof called with a=%s" % a
      return 1.75

def interesting(obj):
   print obj
   return 0
