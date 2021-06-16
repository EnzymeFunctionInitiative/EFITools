
package EFI::Util::NeighborhoodConnectivity;

use Exporter 'import';
our @EXPORT = qw(getConnectivity);


sub getConnectivity {
    my $file = shift;
    
    my %degree;
    my %N; # neighbors
    
    open my $fh, "<", $file or return {};
    while (<$fh>) {
        my ($source, $target) = split(m/\t/);
        $degree{$source}++;
        $degree{$target}++;
        push @{$N{$source}}, $target;
        push @{$N{$target}}, $source;
    }
    close $fh;

    my %NC;

    foreach my $id (keys %degree) {
        my $k = $degree{$id};
        my $nc = 0;
        foreach my $n (@{$N{$id}}) {
            $nc += $degree{$n};
        }
        $NC{$id} = int($nc * 100 / $k) / 100;
    }

    return \%NC;
}


1;

