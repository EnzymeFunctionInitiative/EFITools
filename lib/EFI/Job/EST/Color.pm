
package EFI::Job::EST::Color;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::EST);

use Getopt::Long qw(:config pass_through);

use EFI::Util qw(checkNetworkType);
use EFI::GNN::Base;

use constant JOB_TYPE => "color";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "ssn-in=s",
        "ssn-out=s",
        "map-file-name=s",
        "domain-map-file-name=s",
        "stats=s",
        "cluster-sizes=s",
        "sp-clusters-desc=s",
        "sp-singletons-desc=s",
        "extra-ram",
        "opt-msa-option=s",
        "opt-aa-threshold=s",
        "opt-aa-list=s",
        "opt-min-seq-msa=s",
    );

    my ($conf, $errors) = validateOptions($parms, $self);

    $self->setupDefaults($conf);

    $self->{conf}->{color} = $conf;

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my $outputDir = $self->getOutputDir();

    my @errors;

    my $conf = {};
    my $file = $parms->{"ssn-in"} // "";
    $conf->{ssn_out} = $parms->{"ssn-out"} // "";
    $conf->{map_file_name} = $parms->{"map-file-name"} // "mapping_table.txt";
    $conf->{domain_map_file_name} = $parms->{"domain-map-file-name"} // "domain_mapping_table.txt";
    $conf->{stats} = $parms->{"stats"} // "stats.txt";
    $conf->{cluster_sizes} = $parms->{"cluster-sizes"} // "cluster_size.txt";
    $conf->{sp_clusters_desc} = $parms->{"sp-clusters-desc"} // "swissprot_clusters_desc.txt";
    $conf->{sp_singletons_desc} = $parms->{"sp-singletons-desc"} // "swissprot_singletons_desc.txt";
    $conf->{extra_ram} = $parms->{"extra-ram"} // 0;

    $conf->{zipped_file} = $file if $file =~ m/\.zip$/i;
    $file =~ s/\.zip$//i;
    $conf->{ssn_in} = $file;

    if (not $conf->{ssn_out}) {
        ($conf->{ssn_out} = $conf->{ssn_in}) =~ s/^.*?([^\/]+)$/$1/;
        $conf->{ssn_out} =~ s/\.(xgmml|zip)$/_colored.xgmml/i;
    }

    $conf->{opt_msa_option} = $parms->{"opt-msa-option"} // 0;
    $conf->{opt_aa_threshold} = $parms->{"opt-aa-threshold"} // "";
    $conf->{opt_aa_list} = $parms->{"opt-aa-list"} // "";
    $conf->{opt_min_seq_msa} = $parms->{"opt-min-seq-msa"} // 5;

    $conf->{opt_msa_option} = 0 if $conf->{opt_msa_option} =~ m/CR/ and $conf->{opt_aa_list} !~ m/^[A-Z,]+$/;

    push @errors, "--ssn-in parameter must be specified." if not -f $conf->{ssn_in};

    return $conf, \@errors;
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    ($conf->{ssn_name} = $conf->{ssn_in}) =~ s/^.*?([^\/]+)\.(xgmml|zip)$/$1/;
    ($conf->{ssn_type}, $conf->{is_domain}) = checkNetworkType($conf->{ssn_in});
    $conf->{map_file_name} = "$conf->{ssn_name}_$conf->{map_file_name}";
    $conf->{domain_map_file_name} = "$conf->{ssn_name}_$conf->{domain_map_file_name}";

    my $clusterDataPath = $conf->{cluster_data_path} = "cluster-data";
    $conf->{uniprot_node_data_dir} = "$clusterDataPath/uniprot-nodes";
    $conf->{uniprot_domain_node_data_dir} = "$clusterDataPath/uniprot-domain-nodes";
    $conf->{uniref50_node_data_dir} = "$clusterDataPath/uniref50-nodes";
    $conf->{uniref50_domain_node_data_dir} = "$clusterDataPath/uniref50-domain-nodes";
    $conf->{uniref90_node_data_dir} = "$clusterDataPath/uniref90-nodes";
    $conf->{uniref90_domain_node_data_dir} = "$clusterDataPath/uniref90-domain-nodes";
}


sub createJobStructure {
    my $self = shift;
    my $dir = $self->getOutputDir();
    my $outDir = "$dir/output";
    mkdir $outDir;
    mkdir "$outDir/$self->{conf}->{color}->{cluster_data_path}";
    return ($outDir, $outDir, $outDir);
}


sub createJobs {
    my $self = shift;
    my $conf = $self->{conf}->{color};

    my $S = $self->getScheduler();
    die "Need scheduler" if not $S;

    my $fileInfo = $self->getFileInfo();

    my @jobs;

    my $job1 = $self->getColorSsnJob($S, $fileInfo);
    push @jobs, {job => $job1, deps => [], name => "color_ssn"};

    if ($conf->{opt_msa_option}) {
        my $job2 = $self->getHmmAndStuffJob($S, $fileInfo);
        push @jobs, {job => $job2, deps => [$job1], name => "hmm_and_stuff"};
    }

    return @jobs;
}


sub getFileInfo {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{color};

    my $outputDir = $self->getOutputDir();
    my $dryRun = $self->getDryRun();
    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();
    my $ssnName = $conf->{ssn_name};
    my $ssnType = $conf->{ssn_type};
    my $isDomain = $conf->{is_domain};

    my $domainMapFileName = $conf->{domain_map_file_name};
    my $mapFileName = $conf->{map_file_name};
    (my $ssnOutZip = $conf->{ssn_out}) =~ s/\.xgmml$/.zip/;

    my $clusterDataPath             = $conf->{cluster_data_path};
    my $fastaUniProtDataDir         = "$clusterDataPath/fasta";
    my $fastaUniProtDomainDataDir   = "$clusterDataPath/fasta-domain";
    my $fastaUniRef90DataDir        = "$clusterDataPath/fasta-uniref90";
    my $fastaUniRef90DomainDataDir  = "$clusterDataPath/fasta-uniref90-domain";
    my $fastaUniRef50DataDir        = "$clusterDataPath/fasta-uniref50";
    my $fastaUniRef50DomainDataDir  = "$clusterDataPath/fasta-uniref50-domain";
    my $hmmDataDir                  = "$clusterDataPath/hmm";
    
    my $uniprotIdZip = "$outputDir/${ssnName}_UniProt_IDs.zip";
    my $uniprotDomainIdZip = "$outputDir/${ssnName}_UniProt_Domain_IDs.zip";
    my $uniRef50IdZip = "$outputDir/${ssnName}_UniRef50_IDs.zip";
    my $uniRef50DomainIdZip = "$outputDir/${ssnName}_UniRef50_Domain_IDs.zip";
    my $uniRef90IdZip = "$outputDir/${ssnName}_UniRef90_IDs.zip";
    my $uniRef90DomainIdZip = "$outputDir/${ssnName}_UniRef90_Domain_IDs.zip";
    my $fastaZip = "$outputDir/${ssnName}_FASTA.zip";
    my $fastaDomainZip = "$outputDir/${ssnName}_FASTA_Domain.zip";
    my $fastaUniRef90Zip = "$outputDir/${ssnName}_FASTA_UniRef90.zip";
    my $fastaUniRef90DomainZip = "$outputDir/${ssnName}_FASTA_UniRef90_Domain.zip";
    my $fastaUniRef50Zip = "$outputDir/${ssnName}_FASTA_UniRef50.zip";
    my $fastaUniRef50DomainZip = "$outputDir/${ssnName}_FASTA_UniRef50_Domain.zip";
    my $hmmZip = "$outputDir/${ssnName}_HMMs.zip";

    # The if statements apply to the mkdir cmd, not the die().
    my $mkPath = sub {
       my $dir = "$outputDir/$_[0]";
       if ($dryRun) {
           print "mkdir $dir\n";
       } else {
           mkdir $dir or die "Unable to create output dir $dir: $!" if not -d $dir;
       }
    };
    my $absPath = sub {
        return $_[0] =~ m/^\// ? $_[0] : "$outputDir/$_[0]";
    };
    
    &$mkPath($conf->{uniprot_node_data_dir});
    &$mkPath($conf->{uniprot_domain_node_data_dir}) if not $ssnType or $ssnType eq "UniProt" and $isDomain;
    &$mkPath($fastaUniProtDataDir);
    &$mkPath($fastaUniProtDomainDataDir) if not $ssnType or $ssnType eq "UniProt" and $isDomain;
    
    &$mkPath($conf->{uniref50_node_data_dir});
    &$mkPath($conf->{uniref50_domain_node_data_dir}) if not $ssnType or $ssnType eq "UniRef50" and $isDomain;
    &$mkPath($fastaUniRef50DataDir);
    &$mkPath($fastaUniRef50DomainDataDir) if not $ssnType or $ssnType eq "UniRef50" and $isDomain;
    
    &$mkPath($conf->{uniref90_node_data_dir});
    &$mkPath($conf->{uniref90_domain_node_data_dir}) if not $ssnType or $ssnType eq "UniRef90" and $isDomain;
    &$mkPath($fastaUniRef90DataDir);
    &$mkPath($fastaUniRef90DomainDataDir) if not $ssnType or $ssnType eq "UniRef90" and $isDomain;
    
    &$mkPath($hmmDataDir) if $conf->{opt_msa_option};


    my $fileInfo = {
        color_only => 1,
        config_file => $configFile,
        tool_path => $toolPath,
        fasta_tool_path => "$toolPath/get_fasta.pl",
        cat_tool_path => "$toolPath/cat_files.pl",
        ssn_out => "$outputDir/$conf->{ssn_out}",
        ssn_out_zip => "$outputDir/$ssnOutZip",
    
        uniprot_node_data_dir => &$absPath($conf->{uniprot_node_data_dir}),
        fasta_data_dir => &$absPath($fastaUniProtDataDir),
        uniprot_node_zip => $uniprotIdZip,
        fasta_zip => $fastaZip,
    
        domain_map_file => "${ssnName}_$domainMapFileName",
        map_file => "${ssnName}_$mapFileName",
    };

    if ($conf->{opt_msa_option}) {
        $fileInfo->{hmm_tool_path} = "$toolPath/build_hmm.pl"; #TODO: remove this???
        $fileInfo->{hmm_tool_dir} = "$toolPath/hmm";
        $fileInfo->{hmm_data_dir} = &$absPath($hmmDataDir);
        $fileInfo->{hmm_zip} = $hmmZip;
        $fileInfo->{hmm_logo_list} = "$outputDir/hmm_logos.txt";
        $fileInfo->{hmm_weblogo_list} = "$outputDir/weblogos.txt";
        $fileInfo->{hmm_histogram_list} = "$outputDir/histograms.txt";
        $fileInfo->{hmm_alignment_list} = "$outputDir/alignments.txt";
        $fileInfo->{hmm_consensus_residue_info_list} = "$outputDir/consensus_residue.txt";
        $fileInfo->{hmm_rel_path} = $hmmDataDir;
        $fileInfo->{hmm_count_aa_tool_path} = "$toolPath/count_aa.pl";
        $fileInfo->{hmm_collect_id_tool_path} = "$toolPath/collect_aa_hmm_ids.pl";
   
        my $optAaThreshold = $conf->{opt_aa_threshold};
        $optAaThreshold = ($optAaThreshold and $optAaThreshold =~ m/^[0-9,\.]+$/) ? $optAaThreshold : 0;
        $fileInfo->{hmm_consensus_threshold} = $optAaThreshold;
        $fileInfo->{hmm_option} = $conf->{opt_msa_option};
        $fileInfo->{hmm_amino_acids} = [split(m/,/, $conf->{opt_aa_list})];
        my @colors = ("red", "blue", "orange", "DarkGreen", "Magenta", "Gray");
        $fileInfo->{hmm_weblogo_colors} = \@colors;
    
        my $optMinSeqMsa = $conf->{opt_min_seq_msa};
        $optMinSeqMsa = ($optMinSeqMsa and $optMinSeqMsa >= 1) ? $optMinSeqMsa : 5;
        $fileInfo->{hmm_min_seq_msa} = $optMinSeqMsa;
    
        $fileInfo->{output_path} = $outputDir;
        $fileInfo->{cluster_size_file} = $conf->{cluster_sizes};
        $fileInfo->{ssn_type} = $ssnType;
        $fileInfo->{hmm_zip_prefix} = "${ssnName}";
    }

    # In some cases we can't determine the type of the file in advance, so we write out all possible cases.
    # The 'not $ssnType or' statement ensures that this happens.
    if (not $ssnType or $ssnType eq "UniProt" and $isDomain) {
        $fileInfo->{uniprot_domain_node_data_dir} = &$absPath($conf->{uniprot_domain_node_data_dir});
        $fileInfo->{fasta_domain_data_dir} = &$absPath($fastaUniProtDomainDataDir);
        $fileInfo->{uniprot_domain_node_zip} = $uniprotDomainIdZip;
        $fileInfo->{fasta_domain_zip} = $fastaDomainZip;
    }
    
    if (not $ssnType or $ssnType eq "UniRef90" or $ssnType eq "UniRef50") {
        $fileInfo->{uniref90_node_data_dir} = &$absPath($conf->{uniref90_node_data_dir});
        $fileInfo->{fasta_uniref90_data_dir} = &$absPath($fastaUniRef90DataDir);
        $fileInfo->{uniref90_node_zip} = $uniRef90IdZip;
        $fileInfo->{fasta_uniref90_zip} = $fastaUniRef90Zip;
        if (not $ssnType or $isDomain and $ssnType eq "UniRef90") {
            $fileInfo->{uniref90_domain_node_data_dir} = &$absPath($conf->{uniref90_domain_node_data_dir});
            $fileInfo->{fasta_uniref90_domain_data_dir} = &$absPath($fastaUniRef90DomainDataDir);
            $fileInfo->{uniref90_domain_node_zip} = $uniRef90DomainIdZip;
            $fileInfo->{fasta_uniref90_domain_zip} = $fastaUniRef90DomainZip;
        }
    }
    
    if (not $ssnType or $ssnType eq "UniRef50") {
        $fileInfo->{uniref50_node_data_dir} = &$absPath($conf->{uniref50_node_data_dir});
        $fileInfo->{fasta_uniref50_data_dir} = &$absPath($fastaUniRef50DataDir);
        $fileInfo->{uniref50_node_zip} = $uniRef50IdZip;
        $fileInfo->{fasta_uniref50_zip} = $fastaUniRef50Zip;
        if (not $ssnType or $isDomain) {
            $fileInfo->{uniref50_domain_node_data_dir} = &$absPath($conf->{uniref50_domain_node_data_dir});
            $fileInfo->{fasta_uniref50_domain_data_dir} = &$absPath($fastaUniRef50DomainDataDir);
            $fileInfo->{uniref50_domain_node_zip} = $uniRef50DomainIdZip;
            $fileInfo->{fasta_uniref50_domain_zip} = $fastaUniRef50DomainZip;
        }
    }

    return $fileInfo;
}


sub getColorSsnJob {
    my $self = shift;
    my $S = shift;
    my $fileInfo = shift;
    my $conf = $self->{conf}->{color};

    my $outputDir = $self->getOutputDir();
    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();

    my $scriptArgs = 
        "-output-dir $outputDir " .
        "-ssnin $conf->{ssn_in} " .
        "-ssnout $conf->{ssn_out} " .
        "-uniprot-id-dir $conf->{uniprot_node_data_dir} " .
        "-uniprot-domain-id-dir $conf->{uniprot_domain_node_data_dir} " .
        "-uniref50-id-dir $conf->{uniref50_node_data_dir} " .
        "-uniref50-domain-id-dir $conf->{uniref50_domain_node_data_dir} " .
        "-uniref90-id-dir $conf->{uniref90_node_data_dir} " .
        "-uniref90-domain-id-dir $conf->{uniref90_domain_node_data_dir} " .
        "-id-out $conf->{map_file_name} " .
        "-id-out-domain $conf->{domain_map_file_name} " .
        "-config $configFile " .
        "-stats $conf->{stats} " .
        "-cluster-sizes $conf->{cluster_sizes} " .
        "-sp-clusters-desc $conf->{sp_clusters_desc} " .
        "-sp-singletons-desc $conf->{sp_singletons_desc} " .
        ""
        ;

    my $B = $S->getBuilder();
    
    my $ramReservation = $self->computeRamReservation();

    $B->resource(1, 1, "${ramReservation}gb");
    map { $B->addAction($_); } $self->getEnvironment("est-color");
    
    $B->addAction("cd $outputDir");
    $B->addAction("$toolPath/unzip_file.pl -in $conf->{zipped_file} -out $conf->{ssn_in}") if $conf->{zipped_file};
    $B->addAction("$toolPath/cluster_gnn.pl $scriptArgs");
    EFI::GNN::Base::addFileActions($B, $fileInfo);
    $B->addAction("touch $outputDir/1.out.completed");

    return $B;
}


sub computeRamReservation {
    my $self = shift;
    my $conf = $self->{conf}->{color};

    my $fileSize = 0;
    if ($conf->{zipped_file}) { # If it's a .zip we can't predict apriori what the size will be.
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

