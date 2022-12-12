#!/bin/env perl


use strict;
use warnings;

use Getopt::Long;

my ($protFile, $metadataFile);

my $result = GetOptions(
    "protein-abundance=s"   => \$protFile,
    "metadata=s"            => \$metadataFile,
);

print "missing protFile $protFile\n" and exit(0) if not $protFile or not -f $protFile;
print "missing metadataFile\n" and exit(0) if not $metadataFile;


my $metadata = {
    num_cons_seq_with_hits => 0,
};

my $numConsensusWithHits = computeHits($protFile);

$metadata->{num_cons_seq_with_hits} = $numConsensusWithHits;


open METADATA, ">", $metadataFile or die "Unable to write to metadata file $metadataFile: $!";
foreach my $key (keys %$metadata) {
    print METADATA "$key\t", $metadata->{$key}, "\n";
}
close METADATA;











# Gets the node and edge objects, as well as writes any sequences in the XGMML to the sequence file.
sub computeHits {
    my $file = shift;

    my $numHits = 0;

    open FILE, $file or die "Unable to open file $file: $!";

    my $header = <FILE>;

    while (<FILE>) {
        chomp;

        my ($idPart, @parts) = split(m/\t/);
        my ($cluster, $id) = split(m/\|/, $idPart);

        my $sum = 0;
        foreach my $num (@parts) {
            $sum += $num;
        }

        $numHits++ if ($sum > 0);
    }

    close FILE;
    
    return $numHits;
}



