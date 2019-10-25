#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;

use EFI::Fasta::Headers qw(get_fasta_header_ids);
use EFI::IdMapping::Util;


my ($inputFile, $outputFile, $configFile);
my $result = GetOptions(
    "fasta-file=s"          => \$inputFile,
    "output-file=s"         => \$outputFile,
    "config=s"              => \$configFile,
);

my $usage = <<USAGE;
$0 -fasta-file INPUT_FILE -output-file OUTPUT_FILE [-config CONFIG_FILE]

    -fasta-file         path to input FASTA file
    -output-file        path to output file containing a list of UniProt IDs detected;
                        if non-UniProt IDs are detected, they are reverse mapped to UniProt IDs
    -config             path to config file; taken from environment if not present
USAGE

die "$usage" if not $inputFile or not -f $inputFile or not $outputFile;
die "Config file required in environment or as a parameter.\n$usage"
    if not -f $configFile and not exists $ENV{EFI_CONFIG} and not -f $ENV{EFI_CONFIG};

$configFile = $ENV{EFI_CONFIG} if not -f $configFile;



open INFASTA, $inputFile;
open OUTPUT, ">$outputFile";


my $id;
while (my $line = <INFASTA>) {
    $line =~ s/[\r\n]+$//;

    next if ($line !~ m/^>/);

    my @potentialIds = get_fasta_header_ids($line);

    foreach my $pid (@potentialIds) {
        my $idType = check_id_type($pid);
        if ($idType ne EFI::IdMapping::Util::UNKNOWN) {
            print OUTPUT "$pid\n";
        }
    }
}

close OUTPUT;
close INFASTA;


