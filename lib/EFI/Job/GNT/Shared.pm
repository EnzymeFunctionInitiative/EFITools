
package EFI::Job::GNT::Shared;

use strict;
use warnings;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(getClusterDataDirInfo makeClusterDataDirs getClusterDataDirArgs computeRamReservation CLUSTER_DATA_DIR);

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use EFI::Job;

use constant CLUSTER_DATA_DIR => "cluster-data"; #relative for simplicity


#TODO: remove this
#sub checkZipFileInputs {
#    my $conf = shift;
#
#    my @keys = (
#        "uniprot_node_zip",
#        "uniprot_domain_node_zip", "fasta_zip", "fasta_domain_zip", "uniref50_node_zip", "uniref50_domain_node_zip",
#        "fasta_uniref50_zip", "fasta_uniref50_domain_zip", "uniref90_node_zip", "uniref90_domain_node_zip",
#        "fasta_uniref90_zip", "fasta_uniref90_domain_zip",
#    );
#
#    foreach my $file (@keys) {
#        (my $arg = $file) =~ s/_/-/g;
#        return "Invalid --$arg" if $conf->{$file} and not EFI::Job::checkSafeFileName($conf->{$file});
#    }
#    return "";
#}


sub getClusterDataDirInfo {
    my $conf = shift;
    my $info = shift;
    my $outputDir = shift;
    my $clusterDataDir = shift;

    my $inputFileBase = $conf->{input_file_base};
    my $sfx = $conf->{file_suffix} // "";
    my $useDomain = $conf->{use_domain};

    $info->{uniprot_node_data_dir} = "$clusterDataDir/uniprot-nodes";
    $info->{fasta_data_dir} = "$clusterDataDir/fasta";
    $info->{uniprot_node_zip} = "$outputDir/${inputFileBase}_UniProt_IDs$sfx.zip";
    $info->{fasta_zip} = "$outputDir/${inputFileBase}_FASTA$sfx.zip";
    if ($useDomain and $conf->{ssn_type} eq "UniProt") {
        $info->{uniprot_domain_node_data_dir} = "$clusterDataDir/uniprot-domain-nodes";
        $info->{fasta_uniprot_domain_data_dir} = "$clusterDataDir/fasta-domain";
        $info->{uniprot_domain_node_zip} = "$outputDir/${inputFileBase}_UniProt_Domain_IDs$sfx.zip";
        $info->{fasta_domain_zip} = "$outputDir/${inputFileBase}_FASTA_Domain$sfx.zip";
    }
    
    if (not $conf->{ssn_type} or $conf->{ssn_type} eq "UniRef90" or $conf->{ssn_type} eq "UniRef50") {
        $info->{uniref90_node_data_dir} = "$clusterDataDir/uniref90-nodes";
        $info->{fasta_uniref90_data_dir} = "$clusterDataDir/fasta-uniref90";
        $info->{uniref90_node_zip} = "$outputDir/${inputFileBase}_UniRef90_IDs$sfx.zip";
        $info->{fasta_uniref90_zip} = "$outputDir/${inputFileBase}_FASTA_UniRef90$sfx.zip";
        if ($useDomain and $conf->{ssn_type} eq "UniRef90") {
            $info->{uniref90_domain_node_data_dir} = "$clusterDataDir/uniref90-domain-nodes";
            $info->{fasta_uniref90_domain_data_dir} = "$clusterDataDir/fasta-uniref90-domain";
            $info->{uniref90_domain_node_zip} = "$outputDir/${inputFileBase}_UniRef90_Domain_IDs$sfx.zip";
            $info->{fasta_uniref90_domain_zip} = "$outputDir/${inputFileBase}_FASTA_UniRef90_Domain$sfx.zip";
        }
    }
    
    if (not $conf->{ssn_type} or $conf->{ssn_type} eq "UniRef50") {
        $info->{uniref50_node_data_dir} = "$clusterDataDir/uniref50-nodes";
        $info->{fasta_uniref50_data_dir} = "$clusterDataDir/fasta-uniref50";
        $info->{uniref50_node_zip} = "$outputDir/${inputFileBase}_UniRef50_IDs$sfx.zip";
        $info->{fasta_uniref50_zip} = "$outputDir/${inputFileBase}_FASTA_UniRef50$sfx.zip";
        if ($useDomain and $conf->{ssn_type} eq "UniRef50") {
            $info->{uniref50_domain_node_data_dir} = "$clusterDataDir/uniref50-domain-nodes";
            $info->{fasta_uniref50_domain_data_dir} = "$clusterDataDir/fasta-uniref50-domain";
            $info->{uniref50_domain_node_zip} = "$outputDir/${inputFileBase}_UniRef50_Domain_IDs$sfx.zip";
            $info->{fasta_uniref50_domain_zip} = "$outputDir/${inputFileBase}_FASTA_UniRef50_Domain$sfx.zip";
        }
    }
}


sub makeClusterDataDirs {
    my $conf = shift;
    my $info = shift;
    my $outputDir = shift;
    my $dryRun = shift;
    my $mkPath = shift;

    &$mkPath($info->{uniprot_domain_node_data_dir}) if $info->{uniprot_domain_node_data_dir};
    &$mkPath($info->{uniprot_node_data_dir});
    &$mkPath($info->{fasta_data_dir});
    &$mkPath($info->{fasta_uniprot_domain_data_dir}) if $info->{fasta_uniprot_domain_data_dir};
    
    if (not $conf->{ssn_type} or $conf->{ssn_type} eq "UniRef90" or $conf->{ssn_type} eq "UniRef50") {
        &$mkPath($info->{uniref90_node_data_dir});
        &$mkPath($info->{uniref90_domain_node_data_dir}) if $info->{uniref90_domain_node_data_dir};
        &$mkPath($info->{fasta_uniref90_data_dir});
        &$mkPath($info->{fasta_uniref90_domain_data_dir}) if $info->{fasta_uniref90_domain_data_dir};
    }
    
    if (not $conf->{ssn_type} or $conf->{ssn_type} eq "UniRef50") {
        &$mkPath($info->{uniref50_node_data_dir});
        &$mkPath($info->{uniref50_domain_node_data_dir}) if $info->{uniref50_domain_node_data_dir};
        &$mkPath($info->{fasta_uniref50_data_dir});
        &$mkPath($info->{fasta_uniref50_domain_data_dir}) if $info->{fasta_uniref50_domain_data_dir};
    }
}


sub getClusterDataDirArgs {
    my $info = shift;

    my $scriptArgs = "";
    $scriptArgs .= " --uniprot-id-dir $info->{uniprot_node_data_dir}" if $info->{uniprot_node_data_dir};
    $scriptArgs .= " --uniprot-domain-id-dir $info->{uniprot_domain_node_data_dir}" if $info->{uniprot_domain_node_data_dir};
    $scriptArgs .= " --uniref50-id-dir $info->{uniref50_node_data_dir}" if $info->{uniref50_node_data_dir};
    $scriptArgs .= " --uniref50-domain-id-dir $info->{uniref50_domain_node_data_dir}" if $info->{uniref50_domain_node_data_dir};
    $scriptArgs .= " --uniref90-id-dir $info->{uniref90_node_data_dir}" if $info->{uniref90_node_data_dir};
    $scriptArgs .= " --uniref90-domain-id-dir $info->{uniref90_domain_node_data_dir}" if $info->{uniref90_domain_node_data_dir};

    return $scriptArgs;
}


sub computeRamReservation {
    my $conf = shift;

    my $fileSize = 0;
    if ($conf->{zipped_ssn_in}) { # If it's a .zip we can't predict apriori what the size will be.
        $fileSize = -s $conf->{ssn_in};
    }
    
    # Y = MX+B, M=emperically determined, B = safety factor; X = file size in MB; Y = RAM reservation in GB
    my $ramReservation = $conf->{extra_ram} ? 800 : 150;
    if ($fileSize) {
        my $ramPredictionM = 0.03;
        my $ramSafety = 10;
        $fileSize = $fileSize / 1024 / 1024; # MB
        $ramReservation = $ramPredictionM * $fileSize + $ramSafety;
        $ramReservation = int($ramReservation + 0.5);
    }

    return $ramReservation;
}


1;

