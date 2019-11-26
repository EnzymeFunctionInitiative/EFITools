#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;


my ($source, $parts, $outputDir);
my $result = GetOptions (
    "source=s" => \$source,
    "parts=i"  => \$parts,
    "tmp=s"    => \$outputDir);

die "Input sequence file to split up not valid or not provided" if not $source or not -f $source;
die "Number of parts to split paramter not provided" if not $parts;
die "Output directory not provided" if not $outputDir or not -d $outputDir;


#open all the filehandles and store them in an arry of $parts elements
my @filehandles;
for(my $i = 0; $i < $parts; $i++){
    my $filenumber = $i + 1;
    local *FILE;
    open(FILE, ">$outputDir/fracfile-$filenumber.fa") or die "could not create fractional blast file $outputDir/fracfile-$filenumber.fa\n";
    push(@filehandles, *FILE);
}

#ready through sequences.fa and write each sequence to different filehandle in @filehandles in roundrobin fashion
open(SEQUENCES, $source) or die "could not open sequence file $source\n";
my $sequence = "";
my $arrayid = 0;
while (<SEQUENCES>){
#  print "$arrayid\n"; #for troubleshooting
    my $line = $_;
    if($line =~ /^>/ and $sequence ne ""){
        print {$filehandles[$arrayid]} $sequence;
        $sequence = $line;
        $arrayid++;
        if($arrayid >= scalar @filehandles){
            $arrayid = 0;
        }
    }else{
        $sequence .= $line;
    }
}
close SEQUENCES;

print {$filehandles[$arrayid]} $sequence;


