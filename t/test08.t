use Inline Config => DIRECTORY => './blib_test';

BEGIN {
   print "1..5\n";
}

use Inline Python => <<'END';

class Daddy:
    def __init__(self):
        print "Who's your daddy?"
        self.fish = []
    def push(self,dat):
        print "Daddy.push(%s)" % dat
        return self.fish.append(dat)
    def pop(self):
        print "Daddy.pop()"
        return self.fish.pop()

class Mommy:
    def __init__(self):
        print "Who's your mommy?"
        self.jello = "hello"
    def add(self,data):
        self.jello = self.jello + data
        return self.jello
    def takeaway(self,data):
        self.jello = self.jello[0:-len(data)]
        return self.jello

class Foo(Daddy,Mommy):
    def __init__(self):
        print "new Foo object being created"
        self.data = {}
        Daddy.__init__(self)
        Mommy.__init__(self)
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

$obj->push(12);
print "not " unless $obj->pop() == 12;
print "ok 3\n";

print "not " unless $obj->add("wink") eq "hellowink";
print "ok 4\n";

print "not " unless $obj->takeaway("fiddle") eq "hel";
print "ok 5\n";

