package Inline::Python;

use strict;
use Carp;
require Inline;
require DynaLoader;
require Exporter;

use vars qw(@ISA $VERSION @EXPORT_OK);
@ISA = qw(Inline DynaLoader Exporter);
$VERSION = '0.10';

@EXPORT_OK = qw(eval_python);

#==============================================================================
# Load (and initialize) the Python Interpreter
#==============================================================================
Inline::Python->bootstrap($VERSION);

#==============================================================================
# Allow 'use Inline::Python qw(eval_python)'
#==============================================================================
sub import {
    Inline::Python->export_to_level(1,@_);
}

#==============================================================================
# Register Python.pm as a valid Inline language
#==============================================================================
sub eval_python {
    if (scalar @_ == 1) {
	return _eval_python(@_);
    }
    elsif ((scalar @_ < 3) or not (ref $_[2] =~ /::/)) {
	return _eval_python_function(@_);
    }
    elsif ((scalar @_ >= 3) and (ref $_[2] =~ /::/)) {
	return _eval_python_method(@_);
    }
    else {
	croak "Invalid use of eval_python()." .
	  " See 'perldoc Inline::Python' for details";
    }
}

#==============================================================================
# Register Python.pm as a valid Inline language
#==============================================================================
sub register {
    return {
	    language => 'Python',
	    aliases => ['py', 'python'],
	    type => 'interpreted',
	    suffix => 'pydat',
	   };
}

#==============================================================================
# Validate the Python config options
#==============================================================================
sub validate {
    my $o = shift;

    $o->{Python} = {};
    $o->{Python}{AUTO_INCLUDE} = {};
    $o->{Python}{PRIVATE_PREFIXES} = [];
    $o->{Python}{built} = 0;
    $o->{Python}{loaded} = 0;

    while (@_) {
	my ($key, $value) = (shift, shift);

	if ($key eq 'AUTO_INCLUDE') {
	    add_string($o->{Python}{AUTO_INCLUDE}, $key, $value, '');
	    warn "AUTO_INCLUDE has not been implemented yet!\n";
	}
	elsif ($key eq 'PRIVATE_PREFIXES') {
	    add_list($o->{Python}, $key, $value, []);
	}
	else {
	    croak "$key is not a valid config option for Python\n";
	}
	next;
    }
}

sub add_list {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    push @{$ref->{$key}}, $_;
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

sub add_string {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    $ref->{$key} .= ' ' . $_;
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

sub add_text {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    chomp;
	    $ref->{$key} .= $_ . "\n";
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

###########################################################################
# Print a short information section if PRINT_INFO is enabled.
###########################################################################
sub info {
    my $o = shift;
    my $info =  "";

    $o->build unless $o->{Python}{built};
    $o->load unless $o->{Python}{loaded};

    my @functions = @{$o->{Python}{namespace}{functions}||[]};
    $info .= "The following Python functions have been bound to Perl:\n"
      if @functions;
    for my $function (sort @functions) {
	$info .= "\tdef $function()\n";
    }
    my %classes = %{$o->{Python}{namespace}{classes}||{}};
    $info .= "The following Python classes have been bound to Perl:\n";
    for my $class (sort keys %classes) {
	$info .= "\tclass $class:\n";
	for my $method (sort @{$o->{Python}{namespace}{classes}{$class}}) {
	    $info .= "\t\tdef $method(...)\n";
	}
    }

    return $info;
}

###########################################################################
# Use Python to Parse the code, then extract all newly created functions
# and save them for future loading
###########################################################################
sub build {
    my $o = shift;
    return if $o->{Python}{built};

    croak "Couldn't parse your Python code.\n" 
      unless _eval_python($o->{code});

    my %namespace = _Inline_parse_python_namespace();

    my @filtered;
    for my $func (@{$namespace{functions}}) {
	my $private = 0;
	for my $prefix (@{$o->{Python}{PRIVATE_PREFIXES}}) {
	    ++$private and last
	      if substr($func, 0, length($prefix)) eq $prefix;
	}
	push @filtered, $func
	  unless $private;
    }
    $namespace{functions} = \@filtered;

    for my $class(keys %{$namespace{classes}}) {
	my @filtered;
	for my $method (@{$namespace{classes}{$class}}) {
	    my $private = 0;
	    for my $prefix (@{$o->{Python}{PRIVATE_PREFIXES}}) {
		++$private and last
		  if substr($method, 0, length($prefix)) eq $prefix;
	    }
	    push @filtered, $method 
	      unless $private;
	}
	$namespace{classes}{$class} = \@filtered;
    }

    warn "No functions or classes found!"
      unless ((length @{$namespace{functions}}) > 0 and
	      (length keys %{$namespace{classes}}) > 0);

    require Data::Dumper;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    my $namespace = Data::Dumper::Dumper(\%namespace);

    # if all was successful
    $o->mkpath("$o->{install_lib}/auto/$o->{modpname}");

    open PYDAT, "> $o->{location}" or
      croak "Inline::Python couldn't write parse information!";
    print PYDAT <<END;
%namespace = %{$namespace};
END
    close PYDAT;

    $o->{Python}{built}++;
}

#==============================================================================
# Load and Run the Python Code, then export all functions from the pydat 
# file into the caller's namespace
#==============================================================================
sub load {
    my $o = shift;
    return if $o->{Python}{loaded};

    open PYDAT, $o->{location} or 
      croak "Couldn't open parse info!";
    my $pydat = join '', <PYDAT>;
    close PYDAT;

    eval <<END;
;package Inline::Python::namespace;
no strict;
$pydat
END

    croak "Unable to parse $o->{location}\n$@\n" if $@;
    $o->{Python}{namespace} = \%Inline::Python::namespace::namespace;
    delete $main::{Inline::Python::namespace::};
    $o->{Python}{loaded}++;

    _eval_python($o->{code});

    # bind some perl functions to the caller's namespace
    for my $function (@{$o->{Python}{namespace}{functions}||{}}) {
	my $s = "*::" . "$o->{pkg}";
	$s .= "::$function = sub { ";
	$s .= "Inline::Python::_eval_python_function";
	$s .= "(__PACKAGE__,\"$function\", \@_) }";
	eval $s;
	croak $@ if $@;
    }

    for my $class (keys %{$o->{Python}{namespace}{classes}||{}}) {
	my $s = <<END;
package $o->{pkg}::$class;
require AutoLoader;

sub AUTOLOAD {
    no strict;
    use Data::Dumper;
    \$AUTOLOAD =~ s|.*::(\\w+)|\$1|;
    Inline::Python::_eval_python_method(__PACKAGE__,\$AUTOLOAD,\@_);
}

sub new {
    Inline::Python::_eval_python_function(shift,\"$class\",\@_);
}

sub DESTROY {
    Inline::Python::_destroy_python_object(\@_);
}

END

	for my $method ( @{$o->{Python}{namespace}{classes}{$class}}) {
	    next if $method eq '__init__';
	    $s .= "sub $method {Inline::Python::_eval_python_method";
	    $s .= "(__PACKAGE__,\"$method\",\@_)} ";
	}

	eval $s;
	croak $@ if $@;
    }
}

1;

__END__
