use Inline Config => DIRECTORY => './blib_test';

BEGIN {
   print "1..2\n";
}

use Inline Python => <<'END';

class Foo:
    def __init__(self):
        print "new Foo object being created"
        self.data = {}
    def get_data(self): return self.data
    def set_data(self,dat): 
        self.data = dat

END

my $obj = new Foo;
print "not " if keys %{$obj->get_data()};
print "ok 1\n"; 

$obj->set_data({string => 'hello',
		number => 0.7574,
		array => [1, 2, 3],
	       });
print "not " unless $obj->get_data()->{string} eq "hello";
print "ok 2\n";
