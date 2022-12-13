#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;
my ($seqFile, $outFile);
my $result = GetOptions(
    "seq-file=s"        => \$seqFile,
    "histo-file=s"      => \$outFile,
);



die "Need seq-file" if not $seqFile or not -f $seqFile;
die "Need histo-file" if not $outFile;


open my $seqFh, $seqFile or die "Unable to open seq-file $seqFile: $!";

my %counts;

my $seq = "";
my $len = 0;
my $max = 0;

while (<$seqFh>) {
    chomp;
    if (m/^\>([A-Z0-9]+)/) {
        $counts{$len}++ if $len;
        $max = $len if $len > $max;
        $len = 0;
        $seq = $1;
    } else {
        $len += length $_;
    }
}

close $seqFh;


open my $outFh, ">", $outFile or die "Unable to write to histo-file $outFile: $!";

for (my $i = 1; $i <= $max; $i++) {
    if ($counts{$i}) {
        print $outFh "$i\t$counts{$i}\n";
    } else {
        print $outFh "$i\t0\n";
    }
}

close $outFh;

