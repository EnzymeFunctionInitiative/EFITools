#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

my ($blast, $out);
my $result = GetOptions(
    "blast=s"   => \$blast,
    "out=s"     => \$out,
);


if (not $blast or not -f $blast) {
    die "-blast blast file input must be specified";
}
if (not $out) {
    die "-out output file must be specified";
}


open (BLASTFILE, $blast) or die "cannot open blastfile $blast for reading: $!";
open (OUT, ">$out") or die "cannot write to output file $out: $!";

my ($first, $second) = ("", "");
while (my $line = <BLASTFILE>) {
    chomp $line;
    $line =~ /^([a-zA-Z0-9\:]+)\t([a-zA-Z0-9\:]+)/;
    if ($1 ne $first or $2 ne $second) {
        print OUT "$line\n";
        $first = $1;
        $second = $2;
    }
}

close BLASTFILE;


