#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFI_SHARED};
    use lib $ENV{EFI_SHARED};
}

use strict;

use FindBin;
use Getopt::Long;
use Capture::Tiny qw(capture);

use lib $FindBin::Bin . "/lib";

use EFI::GNN::Arrows;


my ($idFile, $outputFile);
my $result = GetOptions(
    "id-file=s"             => \$idFile,
    "output=s"              => \$outputFile,
);

my $usage = <<USAGE
usage: $0 --output <filename> --id-file <filename>

    --id-file           file containing a list of IDs to use to generate the diagrams
    --output            output sqlite file for Options A-D
USAGE
;

my $diagramVersion = $EFI::GNN::Arrows::Version;


if (not $ENV{"EFI_GNN"}) {
    die "The efignt module must be loaded.";
}

if (not $ENV{"EFI_DB_MOD"}) {
    die "The efidb module must be loaded.";
}


my $outputDir = $ENV{PWD};
my $toolpath = $ENV{"EFI_GNN"};
my $efiGnnMod = $ENV{"EFI_GNN_MOD"};
my $dbMod = $ENV{"EFI_DB_MOD"};

my $stderrFile = "$outputDir/stderr.log";

my $jobType = "ID_LOOKUP";
my $nbSize = 20;
my $cmd = <<CMD;
module load $efiGnnMod
module load $dbMod
$toolpath/create_diagram_db.pl --id-file $idFile --db-file $outputFile --job-type $jobType --nb-size $nbSize
CMD


my ($stdout, $stderr) = capture {
    `$cmd`;
};

print $stdout;
print $stderr;

