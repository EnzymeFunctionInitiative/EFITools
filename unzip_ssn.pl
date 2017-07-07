#!/usr/bin/env perl

use Getopt::Long;
use Capture::Tiny ':all';
use File::Find;
use File::Copy;
use File::Path 'rmtree';


my ($zipFile, $outFile);
my $result = GetOptions(
    "in=s"          => \$zipFile,
    "out=s"         => \$outFile,
);

$usage=<<USAGE
usage: $0 -in <filename> -out <filename>
extracts the first .xgmml file in the input archive.
    -in         path to compressed zip file
    -out        output file path to extract the first xgmml to
USAGE
;


if (not -f $zipFile or not $outFile) {
    die $usage;
}


my $tempDir = "$outFile.tempunzip";

mkdir $tempDir or die "Unable to extract the zip file to $tempDir: $!";

my ($out, $err) = capture {
    system("unzip $zipFile -d $tempDir");
};

my $firstFile = "";

find(\&wanted, $tempDir);

if (-f $outFile) {
    unlink $outFile or die "Unable to remove existing destination file $outFile: $!";
}

copy $firstFile, $outFile or die "Unable to copy the first xgmml file $firstFile to $outFile: $!";

rmtree $tempDir or die "Unable to remove temp dir: $tempDir: $!";


sub wanted {
    if (not $firstFile and $_ =~ /\.xgmml$/i) {
        $firstFile = $File::Find::name;
    }
}


