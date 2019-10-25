#!/usr/bin/env perl

# This is a replacement for the cat command.  We cannot glob thousands of files and pass them
# as arguments to the Linux 'cat' command so we need to chunk them here.

use Getopt::Long;
use File::Slurp;
use Capture::Tiny qw(:all);

my ($result, $inputPattern, $outputFile);
$result = GetOptions(
    "input-file-pattern=s"      => \$inputPattern,
    "output-file=s"             => \$outputFile,
);

my $usage=<<USAGE
usage: $0 -input-file-pattern "globbable_file_pattern_in_quotes" -output-file path_to_merged_output_file
USAGE
;


die $usage if not $inputPattern or not $outputFile;

unlink $outputFile or die "Unable to delete exiting $outputFile" if -f $outputFile;



my @files = glob($inputPattern);

foreach my $file (@files) {
    my $text = read_file($file);
    write_file($outputFile, {append => 1}, $text);
}

#if (not scalar @files) { # no files
#    write_file($outputFile, "");
#}


