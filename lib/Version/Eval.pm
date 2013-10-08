use v5.10;
use strict;
use warnings;

package Version::Eval;
# ABSTRACT: Safe parsing of module $VERSION lines
# VERSION

use File::Spec;
use File::Temp 0.18;
use IO::Pipe;
use Proc::Fork;

use parent 'Exporter';
our @EXPORT_OK = qw/eval_version/;

# Win32 is slow to spawn processes
my $TIMEOUT = $^O eq 'MSWin32' ? 5 : 2;

sub eval_version {
    my ( $string, $timeout ) = @_;
    $timeout = $TIMEOUT unless defined $timeout;

    # create test file
    my $temp = File::Temp->new;
    print {$temp} _pl_template($string);
    close $temp;

    # run it with a timeout
    my $pipe = IO::Pipe->new;
    my $rc;
    run_fork {
        parent {
            my $child = shift;
            my $got   = eval {
                local $SIG{ALRM} = sub { die "alarm\n" };
                alarm $timeout;
                my $c = waitpid $child, 0;
                alarm 0;
                ( $c != $child ) || $?;
            };
            if ( $@ eq "alarm\n" ) {
                kill 'KILL', $child;
                waitpid $child, 0;
                $rc = $?;
            }
            else {
                $rc = $got;
            }
        }
        child {
            open STDOUT, "<&" . fileno $pipe->writer;
            open STDERR, File::Spec->devnull;
            close STDIN;
            exec $^X, $temp;
        }
    };

    my $result = readline $pipe->reader;

    return if $rc || !defined $result; # error condition

    chomp $result;

    return $result;
}

sub _pl_template {
    my ($string) = @_;
    return <<"HERE"
use 5.008001;
use version;
use Safe;

my \$comp = Safe->new;
\$comp->permit("entereval"); # for MBARBON/Module-Info-0.30.tar.gz
\$comp->share("*version::new");
\$comp->share("*version::numify");
\$comp->share_from('main', ['*version::',
                            '*Exporter::',
                            '*DynaLoader::']);
\$comp->share_from('version', ['&qv']);

my \$RESULT = version->parse(
    do {
        $string
    }
);

print version->parse(\$RESULT), "\\n";

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
