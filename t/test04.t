use Inline Config => DIRECTORY => './blib_test';

BEGIN {
   print "1..3\n";
}

use Inline::Python qw(eval_python);

print "not " unless eval_python("print 'Hello from Python!'");
print "ok 1\n";

eval_python(<<'END');

class Foo:
	def __init__(self):
		print "Foo() created!"
	def apple(self): pass

def funky(a): print a

END

print "not " unless eval_python("main","funky",{neil=>'happy'}) eq 'None';
print "ok 2\n";

print "not " unless eval_python("main::Foo","Foo") ne 'None';
print "ok 3\n";

