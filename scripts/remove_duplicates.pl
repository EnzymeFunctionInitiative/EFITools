#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;


my ($in, $out);
my $result = GetOptions(
    "in=s"  => \$in,
    "out=s" => \$out,
);

die "need in" if not $in or not -f $in;
die "need out" if not $out;


open IN, $in or die "could not open input file $in.\n";
open OUT, ">", $out or die "could not write to output file $out.";

while (<IN>) {
    my $line = $_;
    $line =~ /^(\w{6,10})\t(\w{6,10})/;
    if ($1 ne $2) {
        print OUT $line;
    }
}

close OUT;
close IN;

