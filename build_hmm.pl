#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Capture::Tiny qw(:all);

# Create the logo if the module for creating it is available.
eval "use Bio::HMM::Logo";
my $makeLogo = not $@;


my ($fastaDir, $hmmDir, $logoList, $relHmmDir, $buildFast, $isDomain);
my $result = GetOptions(
    "fasta-dir=s"       => \$fastaDir,
    "hmm-dir=s"         => \$hmmDir,
    "logo-list=s"       => \$logoList,
    "rel-hmm-path=s"    => \$relHmmDir, # for logos
    "build-fast"        => \$buildFast,
    "domain"            => \$isDomain,
);

my $usage=<<USAGE
usage: $0 -data-dir <path_to_data_dir> -config <config_file>
    -fasta-dir      path to directory to that has fasta files for each cluster
    -hmm-dir        path to directory to output HMM files to
    -logo-list      path to file to list logos in
    -rel-hmm-path   relative (to job directory) path to HMM files
    -build-fast     also build HMMs using the fast options
    -domain         indicates that this is for sequence domains
USAGE
;


if (not $fastaDir or not -d $fastaDir) {
    die "The input FASTA directory must exist.";
}
if (not $hmmDir or not -d $hmmDir) {
    die "The output HMM directory must exist."
}


$isDomain = defined($isDomain);
$buildFast = defined($buildFast);


my $logoListFh = undef;
if ($makeLogo and $logoList and $relHmmDir) {
    open $logoListFh, ">>", $logoList or warn "Unable to write to logo list file $logoList: $!";
}


my @files = glob("$fastaDir/cluster_*.fasta");

foreach my $file (@files) {
    (my $filename = $file) =~ s%^.*(cluster_(domain_)?\d+)\.fasta%$1%;
    (my $clusterNum = $filename) =~ s/^.*?(\d+)$/$1/;
    my $normalFilename = "$hmmDir/normal/$filename";
    my $fastFilename = "$hmmDir/fast/$filename";
    print "Output $normalFilename\n";
    (my $numLines = `grep \\> $file | wc -l`) =~ s/\D//gs;
    if ($numLines > 50000) {
        print "Skipping $file due to $numLines lines > 50k\n";
        next;
    }
    my ($results, $error) = capture {
        system("muscle", "-quiet", "-in", $file, "-out", "$normalFilename.afa");
        system("muscle", "-quiet", "-in", $file, "-out", "$fastFilename.fast.afa", "-maxiters", "1", "-diags", "-sv", "-distance1", "kbit20_3") if $buildFast;
    };
    print "ERROR $error\n" and next if $error;
    ($results, $error) = capture {
        system("hmmbuild", "$normalFilename.hmm", "$normalFilename.afa");
        system("hmmbuild", "$fastFilename.fast.hmm", "$fastFilename.fast.afa") if $buildFast;
    };
    print "ERROR $error\n" and next if $error;

    if ($makeLogo and $logoListFh) {
        my $seqTypeLabel = $isDomain ? "domain" : "full";
        make_logo("$normalFilename.hmm", "$normalFilename.json", "$normalFilename.png");
        print $logoListFh "$clusterNum\t$seqTypeLabel\tnormal\t$relHmmDir/normal/$filename\n";
    
        if ($buildFast) {
            make_logo("$fastFilename.fast.hmm", "$fastFilename.fast.json", "$fastFilename.fast.png");
            print $logoListFh "$clusterNum\t$seqTypeLabel\tfast\t$relHmmDir/fast/$filename.fast\n";
        }
    }
}


close $logoListFh if $logoListFh;



sub make_logo {
    my ($hmmFile, $jsonFile, $pngFile) = @_;

    return if not $hmmFile;

    # create the logo object and pass it the path to the hmm file.
    my $logo = Bio::HMM::Logo->new({ hmmfile => $hmmFile });
    
    if ($jsonFile) {
        # generate the json string that can be used by the javascript
        # code to create an interactive graphic
        my $logo_json = $logo->as_json("info_content_above");
        open my $json_fh, ">", $jsonFile or warn "Unable to write to json file $jsonFile: $!" and return;
        print $json_fh $logo_json;
        close $json_fh;
    }
    
    if ($pngFile) {
        # create a static version of the logo and dump it to disk.
        my $logo_png = $logo->as_png("info_content_above");
        open my $image, ">", $pngFile or warn "Unable to write to png file $pngFile: $!" and return;
        binmode $image;
        print $image $logo_png;
        close $image;
    }
}


