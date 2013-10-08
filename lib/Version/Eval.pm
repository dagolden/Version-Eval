use v5.10;
use strict;
use warnings;

package Version::Eval;
# ABSTRACT: Safe parsing of module $VERSION lines
# VERSION

use Capture::Tiny qw/capture/;
use File::Temp 0.18;

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
    my ( $stdout, $stderr, $ok ) = capture {
        my $rc;
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            $rc = system( $^X, $temp );
            alarm 0;
        };
        return ( $@ eq '' && $rc == 0 ? 1 : 0 );
    };

    return if !$ok; # error condition

    # parse its output
    chomp( my $result = $stdout );

    return $result;
}

sub _pl_template {
    my ($string) = @_;
    return <<"HERE"
use 5.008001;
use version;

my \$RESULT = version->parse(
    do {
        $string
    }
);

print \$RESULT, "\\n";

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
