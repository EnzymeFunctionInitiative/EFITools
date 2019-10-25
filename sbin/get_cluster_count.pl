#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use List::MoreUtils qw(uniq);
use Getopt::Long;

use CdHitParser;


my ($cluster, $seqId, $seqLen);
my $result = GetOptions(
    "cluster=s"     => \$cluster,
    "id=s"          => \$seqId,
    "len=s"         => \$seqLen,
);


die "Need cluster input" if not $cluster or not -f $cluster;
die "Need id input" if not $seqId;
die "Need len input" if not $seqLen;

my $cp = new CdHitParser();

#parse cluster file to get parent/child sequence associations
open CLUSTER, $cluster or die "cannot open cdhit cluster file $cluster\n";

my $line = "";
while (<CLUSTER>) {
    $line=$_;
    chomp $line;
    $cp->parse_line($line);
}
$cp->finish;

close CLUSTER;


print join("\t", $seqId, $seqLen, scalar($cp->get_clusters)), "\n";


