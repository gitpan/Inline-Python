package Inline::Python;

use strict;
use Carp;
require Inline;
require DynaLoader;
require Exporter;

use vars qw(@ISA $VERSION @EXPORT_OK);
@ISA = qw(Inline DynaLoader Exporter);
$VERSION = '0.15';

@EXPORT_OK = qw(eval_python);

#==============================================================================
# Load (and initialize) the Python Interpreter
#==============================================================================
sub dl_load_flags { 0x01 }
Inline::Python->bootstrap($VERSION);

#==============================================================================
# Allow 'use Inline::Python qw(eval_python)'
#==============================================================================
sub import {
    Inline::Python->export_to_level(1,@_);
}

#==============================================================================
# Provide an overridden function for evaluating Python code
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

    $o->{ILSM} = {};
    $o->{ILSM}{FILTERS} = [];
    $o->{ILSM}{AUTO_INCLUDE} = {};
    $o->{ILSM}{PRIVATE_PREFIXES} = [];
    $o->{ILSM}{built} = 0;
    $o->{ILSM}{loaded} = 0;

    while (@_) {
	my ($key, $value) = (shift, shift);

	if ($key eq 'AUTO_INCLUDE') {
	    add_string($o->{ILSM}{AUTO_INCLUDE}, $key, $value, '');
	    warn "AUTO_INCLUDE has not been implemented yet!\n";
	}
	elsif ($key eq 'PRIVATE_PREFIXES') {
	    add_list($o->{ILSM}, $key, $value, []);
	}
	elsif ($key eq 'FILTERS') {
	    next if $value eq '1' or $value eq '0'; # ignore ENABLE, DISABLE
	    $value = [$value] unless ref($value) eq 'ARRAY';
	    my %filters;
	    for my $val (@$value) {
		if (ref($val) eq 'CODE') {
		    $o->add_list($o->{ILSM}, $key, $val, []);
	        }
		else {
		    eval { require Inline::Filters };
		    croak "'FILTERS' option requires Inline::Filters to be installed."
		      if $@;
		    %filters = Inline::Filters::get_filters($o->{API}{language})
		      unless keys %filters;
		    if (defined $filters{$val}) {
			my $filter = Inline::Filters->new($val, 
							  $filters{$val});
			$o->add_list($o->{ILSM}, $key, $filter, []);
		    }
		    else {
			croak "Invalid filter $val specified.";
		    }
		}
	    }
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

    $o->build unless $o->{ILSM}{built};
    $o->load unless $o->{ILSM}{loaded};

    my @functions = @{$o->{ILSM}{namespace}{functions}||[]};
    $info .= "The following Python functions have been bound to Perl:\n"
      if @functions;
    for my $function (sort @functions) {
	$info .= "\tdef $function()\n";
    }
    my %classes = %{$o->{ILSM}{namespace}{classes}||{}};
    $info .= "The following Python classes have been bound to Perl:\n";
    for my $class (sort keys %classes) {
	$info .= "\tclass $class:\n";
	for my $method (sort @{$o->{ILSM}{namespace}{classes}{$class}}) {
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
    return if $o->{ILSM}{built};

    $o->{ILSM}{code} = $o->filter(@{$o->{ILSM}{FILTERS}});

    croak "Couldn't parse your Python code.\n" 
      unless _eval_python($o->{ILSM}{code});

    my %namespace = _Inline_parse_python_namespace();

    my @filtered;
    for my $func (@{$namespace{functions}}) {
	my $private = 0;
	for my $prefix (@{$o->{ILSM}{PRIVATE_PREFIXES}}) {
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
	    for my $prefix (@{$o->{ILSM}{PRIVATE_PREFIXES}}) {
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

    require Inline::denter;
    my $namespace = Inline::denter->new
      ->indent(
	       *namespace => \%namespace,
	       *filtered => $o->{ILSM}{code},
	      );

    # if all was successful
    $o->mkpath("$o->{API}{install_lib}/auto/$o->{API}{modpname}");

    open PYDAT, "> $o->{API}{location}" or
      croak "Inline::Python couldn't write parse information!";
    print PYDAT $namespace;
    close PYDAT;

    $o->{ILSM}{built}++;
}

#==============================================================================
# Load and Run the Python Code, then export all functions from the pydat 
# file into the caller's namespace
#==============================================================================
sub load {
    my $o = shift;
    return if $o->{ILSM}{loaded};

    open PYDAT, $o->{API}{location} or 
      croak "Couldn't open parse info!";
    my $pydat = join '', <PYDAT>;
    close PYDAT;

    require Inline::denter;
    my %pydat = Inline::denter->new->undent($pydat);
    $o->{ILSM}{namespace} = $pydat{namespace};
    $o->{ILSM}{code} = $pydat{filtered};
    $o->{ILSM}{loaded}++;

    _eval_python($o->{ILSM}{code});

    # bind some perl functions to the caller's namespace
    for my $function (@{$o->{ILSM}{namespace}{functions}||{}}) {
	my $s = "*::" . "$o->{API}{pkg}";
	$s .= "::$function = sub { ";
	$s .= "Inline::Python::_eval_python_function";
	$s .= "(__PACKAGE__,\"$function\", \@_) }";
	eval $s;
	croak $@ if $@;
    }

    for my $class (keys %{$o->{ILSM}{namespace}{classes}||{}}) {
	my $s = <<END;
package $o->{API}{pkg}::$class;

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

	for my $method ( @{$o->{ILSM}{namespace}{classes}{$class}}) {
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
