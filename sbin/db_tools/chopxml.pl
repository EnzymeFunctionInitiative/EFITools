#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

my ($inFile, $outDir);
my $result = GetOptions(
    "in=s"      => \$inFile,
    "outdir=s"  => \$outDir,
);

die "Invalid arguments" if not defined $inFile or not -f $inFile or not $outDir or not -d $outDir;

my $batchsize = 1000000;

my $head = <<END;
<?xml version="1.0" encoding="ISO-8859-1"?>
<!DOCTYPE interpromatch SYSTEM "match_complete.dtd">
<interpromatch>
END
my $tail = "</interpromatch>\n";

my $releaseStart = 0;
my $releaseEnd = 0;
my $protCount = 0;
my $file = 0;
my $protStart = 0;
my $prot = "";

open XML, $inFile or die "could not open XML file '$inFile' for fragmentation\n";

while (<XML>) {
    my $line = $_;
    if ($line =~ /<release>/) {
        $releaseStart = 1;
    } elsif ($line =~ /<\/release>/) {
        $releaseEnd = 1;
        $line =~ s/<\/release>//;
        if ($line =~ /<prot/) {
            $prot = $line;
            $protStart = 1;
            $protCount = 1;
        }
    } elsif ($releaseStart > 0 and $releaseEnd < 1) {
        print $line;
    } elsif ($line =~ /<prot/) {
        $protStart = 1;
        if ($protCount >= $batchsize) {
            #print $prot;
            print "$file\n";
            open OUT, ">$outDir/$file.xml" or die "could not create xml fragment $outDir/$file.xml\n";
            print OUT "$head$prot$tail";
            close OUT;
            $file++;
            $prot = $line;
            $protCount = 1;      
        } else {
            $prot.=$line;
            $protCount++;
            #print "$protCount\n";
        }
    } elsif ($protStart) {
        $prot .= $line;
    }
}
open OUT, ">", "$outDir/$file.xml" or die "could not create xml fragment $outDir/$file.xml: $!";;
print OUT "$head$prot";
close OUT;

