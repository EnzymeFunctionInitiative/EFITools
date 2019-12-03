
package EFI::Util::CdHitParser;

use strict;

sub new {
    my $class = shift;
    my %args = @_;

    my $self = { tree => {}, head => "", children => [] };
    $self->{verbose} = exists $args{verbose} ? $args{verbose} : 0;
    bless $self, $class;

    return $self;
}


sub parse_line {
    my $self = shift;
    my $line = shift;

    chomp $line;
    if ($line =~ /^>/) {
        if ($self->{head}) {
            $self->{tree}->{$self->{head}} = $self->{children};
        }
        $self->{children} = [];
    } elsif ($line =~ / >(\w{6,10})\.\.\. \*$/ or $line =~ / >(\w{6,10}:\d+:\d+)\.\.\. \*$/) {
        my $name = trim_name($1);
        push @{$self->{children}}, $name;
        $self->{head} = $1;
    } elsif ($line =~ /^\d+.*>(\w{6,10})\.\.\. at/ or $line =~ /^\d+.*>(\w{6,10}:\d+:\d+)\.\.\. at/) {
        my $name = trim_name($1);
        push @{$self->{children}}, $name;
    } else {
        warn "no match in $line\n";
    }
}


sub trim_name {
    my $name = shift;
    return $name;
    # At one point we were truncating the name. I have no idea why this was happeneing, and it caused
    # problems later -- the node IDs for edges were truncated in some cases when the domain option was.
    #return substr($name, 0, 19);
}


sub finish {
    my $self = shift;
    
    $self->{tree}->{$self->{head}} = $self->{children};
}


sub child_exists {
    my $self = shift;
    my $key = shift;

    $key = trim_name($key);

    exists $self->{tree}->{$key} ? return 1 : 0;
}


sub get_children {
    my $self = shift;
    my $key = shift;

    $key = trim_name($key);

    return @{ $self->{tree}->{$key} };
}


sub get_clusters {
    my $self = shift;

    return keys %{ $self->{tree} };
}

sub parse_file {
    my $self = shift;
    my $clusterFile = shift;

    #parse cluster file to get parent/child sequence associations
    open CLUSTER, $clusterFile or die "cannot open cdhit cluster file $clusterFile: $!";
    
    while (<CLUSTER>) {
        $self->parse_line($_);
    }
    $self->finish;
    
    close CLUSTER;
}


1;

