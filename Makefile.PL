use ExtUtils::MakeMaker;

#============================================================================
# What perl are we running?
#============================================================================
use Config;
$version = $Config{version};
#my $version = $];
#print $version,"\n";

#============================================================================
# Python libraries to look for
#============================================================================
my @py_libs = 
  (
   '/usr/lib/libpython2.0.a',
   '/usr/lib/libpython1.6.a',
   '/usr/lib/libpython1.5.a',
   '/usr/local/lib/libpython2.0.a',
   '/usr/local/lib/libpython1.6.a',
   '/usr/local/lib/libpython1.5.a',
   '/usr/lib/libpython2.0.so',
   '/usr/lib/libpython1.6.so',
   '/usr/lib/libpython1.5.so',
   '/usr/local/lib/libpython2.0.so',
   '/usr/local/lib/libpython1.6.so',
   '/usr/local/lib/libpython1.5.so',
   '/usr/local/ActivePython-2.0/lib/python2.0/config/libpython2.0.a',
   '/usr/local/ActivePython-1.6/lib/python1.6/config/libpython1.6.a',
   '/usr/local/ActivePython-1.5/lib/python1.5/config/libpython1.5.a',
   '/usr/local/ActivePython-2.0/lib/python2.0/config/libpython2.0.so',
   '/usr/local/ActivePython-1.6/lib/python1.6/config/libpython1.6.so',
   '/usr/local/ActivePython-1.5/lib/python1.5/config/libpython1.5.so',
  );

#============================================================================
# Python include files to look for
#============================================================================
my @py_incs = 
  (
   '/usr/local/ActivePython-2.0/include/python2.0',
   '/usr/local/ActivePython-1.6/include/python1.6',
   '/usr/local/ActivePython-1.5/include/python1.5',
   '/usr/include/python2.0',
   '/usr/include/python1.6',
   '/usr/include/python1.5',
   '/usr/local/include/python2.0',
   '/usr/local/include/python1.6',
   '/usr/local/include/python1.5',
  );

#============================================================================
# Search for libraries
#============================================================================
my @py_libs_found;
for my $loc (@py_libs) {
    push(@py_libs_found, $loc) if -f $loc;
}

#============================================================================
# Search for include directories
#============================================================================
my @py_incs_found;
for my $loc (@py_incs) {
    push(@py_incs_found, $loc) if -d $loc;
}

#============================================================================
# Prompt for library to use
#============================================================================
my $num = 1;
my $lib = prompt(join("\n",("Found these Python libraries: ",
			    map {$num++ . ". $_"} @py_libs_found))."\nUse? (or enter alternative)",
		 "1") if @py_libs_found;
$lib = prompt ("Please enter the Python library.", "")
  unless @py_libs_found;

$lib = $py_libs_found[$lib-1] if $lib =~ /^\d+$/;

#============================================================================
# Prompt for include directory to use
#============================================================================
$num = 1;
my $inc = prompt(join("\n",("Found these Python include dirs: ",
			    map {$num++ . ". $_"} @py_incs_found))."\nUse? (or enter alternative)",
		 "1") if @py_incs_found;
$inc = prompt ("Please enter the Python include directory.", "")
  unless @py_incs_found;

$inc = $py_incs_found[$inc-1] if $inc =~ /^\d+$/;

#============================================================================
# Does Python have Tkinter installed?
#============================================================================
my $tkinter = prompt("Does this Python have Tkinter installed? Hint: run \"python -c 'import Tkinter'\" and watch for error messages.", "no") eq "yes";

#============================================================================
# Linker hints
#============================================================================
my %hints =
  (
   'python2.0' => ['-lpython2.0',
		   '-ldb -lutil', # seems to always be required for 2.0
		   $version < 5.6 ? "-lpthread":"",
		   $tkinter ? "-ltcl -ltk -ltix":"",
		  ],
   'python1.6' => ['-lpython1.6',
		   $tkinter ? "-ltcl -ltk -ltix":"",
		  ],
   'python1.5' => ['-lpython1.5',
		   $tkinter ? "-ltcl -ltk -ltix":"",
		  ],
  );

my $pyver;
for my $py (keys %hints) {
    $pyver ||= (($lib =~ m|$py|i) ? $py : 0);
}

my $libs = join " ", @{$hints{$pyver}};

#============================================================================
# Write the makefile
#============================================================================
my $lib_path = substr($lib,0,rindex($lib,'/'));
my $lib = substr($lib,rindex($lib,'/lib')+4);
$lib = substr($lib,0,rindex($lib,'.'));

WriteMakefile(
	      INC => "-I$inc",
	      LIBS => "-L$lib_path $libs",
	      NAME => 'Inline::Python',
	      VERSION_FROM => 'Python.pm',
	      PREREQ_PM => {
			    Inline => 0.31,
			   },
	      clean => {FILES => 'blib_test/'},
	     );
