#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;


my ($fastaIn, $fastaOut, $maxSeq);
my $result = GetOptions(
    "fasta-in=s"        => \$fastaIn,
    "fasta-out=s"       => \$fastaOut,
    "max-seq=i"         => \$maxSeq,
);

die "Need --fasta-in" if not $fastaIn or not -f $fastaIn;
die "Need --fasta-out" if not $fastaOut;

$maxSeq = 1000 if not defined $maxSeq;


open my $in, "<", $fastaIn or die "Unable to read --fasta-in $fastaIn: $!";

my @seq;
while (<$in>) {
    my $nextIndex = m/^>/ ? 1 : 0;
    push @{$seq[$#seq + $nextIndex]}, $_;
}

close $in;

my $numSeq = scalar @seq;
my $step = $numSeq / $maxSeq;
$step = $step < 1 ? 1 : $step;

$numSeq = ($step == 1 and $maxSeq < $numSeq) ? $maxSeq : $numSeq;


# THIS ALGORITHM DOESN'T ALWAYS GIVE THE EXACT NUMBER OF SEQUENCES REQUESTED.
# BUT I DON'T CARE.

my @idx;
for (my $i = 0; $i < $numSeq; $i += $step) {
    push @idx, int($i);
}


open my $out, ">", $fastaOut or die "Unable to write to --fasta-out $fastaOut: $!";
map { print $out join("", @{$seq[$_]}); } @idx;
close $out;


#print scalar @seq;
#print "\n";
#print join("", @{$seq[0]});
#print join("", @{$seq[$#seq]});


