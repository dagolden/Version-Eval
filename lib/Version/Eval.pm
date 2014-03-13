use strict;
use warnings;

package Version::Eval;
# ABSTRACT: Safe parsing of module $VERSION lines
# VERSION

use File::Spec;
use File::Temp 0.18;
use IPC::Open3 qw(open3);
use Symbol 'gensym';

use parent 'Exporter';
our @EXPORT_OK = qw/eval_version/;

# Win32 is slow to spawn processes
my $TIMEOUT = $^O eq 'MSWin32' ? 5 : 2;

=func eval_version

    my $version = eval_version( q[our $VERSION = "1.23"] );

Given a string that contains a C<$VERSION> declaration, this
function will evaluate it in a L<Safe> compartment in a
separate process.  If the C<$VERSION> is a valid version
string according to L<version>, it will return it as a string,
otherwise, it will return undef.

=cut

sub eval_version {
    my ( $string, $timeout ) = @_;
    $timeout = $TIMEOUT unless defined $timeout;

    # what $VERSION are we looking for?
    my ( $sigil, $var ) = $string =~ /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/;
    return unless $sigil && $var;

    # munge string: remove "use version" as we do that already and the "use"
    # will get stopped by the Safe compartment
    $string =~ s/(?:use|require)\s+version[^;]*/1/;

    # create test file
    my $temp = File::Temp->new;
    print {$temp} _pl_template( $string, $sigil, $var );
    close $temp;

    my $rc;
    my $result;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $temp);
    my $killer;
    if ($^O eq 'MSWin32') {
        $killer = fork;
        if (!defined $killer) {
            die "Can't fork: $!";
        }
        elsif ($killer == 0) {
            sleep $timeout;
            kill 'KILL', $pid;
            exit 0;
        }
    }
    my $got = eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        local $/;
        $result = readline $out;
        my $c = waitpid $pid, 0;
        alarm 0;
        ( $c != $pid ) || $?;
    };
    if ( $@ eq "alarm\n" ) {
        kill 'KILL', $pid;
        waitpid $pid, 0;
        $rc = $?;
    }
    else {
        $rc = $got;
    }
    if ($killer) {
        kill 'KILL', $killer;
        waitpid $killer, 0;
    }

    return if $rc || !defined $result; # error condition

##  print STDERR "# C<< $string >> --> $result" if $result =~ /^ERROR/;
    return if $result =~ /^ERROR/;

    $result =~ s/[\r\n]+\z//;

    return $result;
}

sub _pl_template {
    my ( $string, $sigil, $var ) = @_;
    return <<"HERE"
use 5.008001;
use version;
use Safe;
use File::Spec;
open STDERR, '>', File::Spec->devnull;
open STDIN, '<', File::Spec->devnull;

my \$comp = Safe->new;
\$comp->permit("entereval"); # for MBARBON/Module-Info-0.30.tar.gz
\$comp->share("*version::new");
\$comp->share("*version::numify");
\$comp->share_from('main', ['*version::',
                            '*Exporter::',
                            '*DynaLoader::']);
\$comp->share_from('version', ['&qv']);

my \$code = <<'END';
    local $sigil$var;
    \$$var = undef;
    do {
        $string
    };
    \$$var;
END

my \$result = \$comp->reval(\$code);
print "ERROR: \$@\n" if \$@;
exit unless defined \$result;

eval { \$result = version->parse(\$result)->stringify };
print \$result;

HERE
}

1;

=for Pod::Coverage BUILD

=head1 SYNOPSIS

    use Version::Eval qw/eval_version/;

    my $version = eval_version( $unsafe_string );

=head1 DESCRIPTION

Package versions are defined by a string such as this:

    package Foo;
    our $VERSION = "1.23";

If we want to know the version of a F<.pm> file, we can
load it and check C<Foo->VERSION> for the package.  But that means any
buggy or hostile code in F<Foo.pm> gets run.

The safe thing to do is to parse out a string that looks like an assignment
to C<$VERSION> and then evaluate it.  But even that could be hostile:

    package Foo;
    our $VERSION = do { my $n; $n++ while 1 }; # infinite loop

This module executes a potential version string in a separate process in
a L<Safe> compartment with a timeout to avoid as much risk as possible.

Hostile code might still attempt to consume excessive resources, but the
timeout should limit the problem.

=head1 SEE ALSO

=for :list
* L<Parse::PMFile>

=cut

# vim: ts=4 sts=4 sw=4 et:
