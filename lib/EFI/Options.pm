
package EFI::Options;

use strict;
use warnings;

use Getopt::Long qw(:config pass_through);


sub new {
    my ($class, %args) = @_;

    my $getopt = ($args{mode} // "") eq "args" ? 0 : 1;
    my $otherArgs = $args{config} // {};

    my $self = {getopt => $getopt, args => $otherArgs};
    bless $self, $class;

    return $self;
}


sub getOptions {
    my $self = shift;
    my $names = shift; #hashref, name of arg => type of arg (command line type)

    my %opts;
    if ($self->{getopt}) {
        my @names = map { $names->{$_} ? "$_=$names->{$_}" : $_ } keys %$names;
        my $result = GetOptions(\%opts, @names);
    } else {
        foreach my $name (keys %$names) {
            $opts{$name} = $self->{args}->{$name} // "";
        }
    }
    return \%opts;
}


1;

