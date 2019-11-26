
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
use EFI::Job::GNT::Shared;

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

    if (not scalar @$errors) {
        $self->setupDefaults($conf);
    }

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

    $conf->{zipped_ssn_in} = $file if $file =~ m/\.zip$/i;
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


sub getUsage {
    my $self = shift;

    my $showAllFileOpts = 1;
    my $showDevSiteOpts = 0;

    my $usage = <<USAGE;
--ssn-in <PATH_TO_SSN_FILE> [--ssn-out <FILE>]
USAGE
    if ($showAllFileOpts) { #disable for now
        $usage .= <<USAGE;
        [--map-file-name <FILE> --domain-map-file-name <FILE> --stats <FILE> --cluster-sizes <FILE>
         --sp-clusters-desc <FILE> --sp-singletons-desc <FILE>]
USAGE
    }
    if ($showDevSiteOpts) { #dev site only, disable for now
        $usage .= <<USAGE;
        [--extra-ram --opt-msa-option HIST|WEBLOGO|HMM|CR --opt-aa-threshold #
         --opt-aa-list *[,*,*...] --opt-min-seq-msa #]
USAGE
    }
    $usage .= <<USAGE;

    --ssn-in            path to uncolored SSN
    --ssn-out           path to output SSN, colored and numbered
USAGE
    if ($showAllFileOpts) {
        $usage .= <<USAGE;
    --map-file-name     path to output file mapping UniProt IDs to clusters
    --domain-map-file-name  path to output file mapping UniProt IDs to clusters, with domain info;
                        only valid when the input SSN contains domain-length sequences
    --stats             path to statistics file containing various node counts
    --cluster-sizes     path to file that lists cluster sizes
    --sp-clusters-desc  path to file that lists Swiss-Prot IDs and the corresponding cluster number
    --sp-singletons-desc    path to file that lists Swiss-Prot IDs in singletons
USAGE
    }
    return $usage;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{color};

    push @$info, [ssn_out => $conf->{ssn_out}];

    return $info;
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    ($conf->{ssn_name} = $conf->{ssn_in}) =~ s/^.*?([^\/]+)\.(xgmml|zip)$/$1/;
    ($conf->{ssn_type}, $conf->{is_domain}) = checkNetworkType($conf->{ssn_in});
    $conf->{map_file_name} = "$conf->{ssn_name}_$conf->{map_file_name}";
    $conf->{domain_map_file_name} = "$conf->{ssn_name}_$conf->{domain_map_file_name}";
    $conf->{use_domain} = (not $conf->{ssn_type} or $conf->{is_domain});
    
    (my $inputFileBase = $conf->{ssn_in}) =~ s%^.*/([^/]+)$%$1%;
    $inputFileBase =~ s/\.zip$//;
    $inputFileBase =~ s/\.xgmml$//;
    $conf->{input_file_base} = $inputFileBase;
    
    my $outputDir = $self->getOutputDir();
    $conf->{cluster_data_dir} = "$outputDir/" . CLUSTER_DATA_DIR;
}


sub createJobStructure {
    my $self = shift;
    my @dirs = $self->SUPER::createJobStructure();
    my $outDir = $self->getOutputDir();
    mkdir $self->{conf}->{color}->{cluster_data_dir};
    return @dirs;
}


sub createJobs {
    my $self = shift;
    my $conf = $self->{conf}->{color};

    my $S = $self->getScheduler();
    die "Need scheduler" if not $S;

    my $fileInfo = $self->getFileInfo();
    $self->makeDirs($conf, $fileInfo);

    my @jobs;

    my $job1 = $self->getColorSsnJob($S, $fileInfo);
    push @jobs, {job => $job1, deps => [], name => "color_ssn"};

    if ($conf->{opt_msa_option}) {
        my $job2 = $self->getHmmAndStuffJob($S, $fileInfo);
        push @jobs, {job => $job2, deps => [$job1], name => "hmm_and_stuff"};
    }

    return @jobs;
}


sub makeDirs {
    my $self = shift;
    my $conf = shift;
    my $info = shift;

    my $useDomain = $conf->{use_domain};

    my $outputDir = $self->getOutputDir();
    my $dryRun = $self->getDryRun();
    my $hmmDataDir = "$conf->{cluster_data_dir}/hmm";

    # Since we're passing relative paths to the cluster_gnn script we need to create the directories with absolute paths.
    my $mkPath = sub {
        my $dir = $_[0];
        $dir = "$outputDir/$dir" if $dir !~ m%^/%;
        #my $dir = "$outputDir/$_[0]";
        if ($dryRun) {
            print "mkdir $dir\n";
        } else {
            mkdir $dir or die "Unable to create output dir $dir: $!" if not -d $dir;
        }
    };
    
    &$mkPath($conf->{cluster_data_dir});
    &$mkPath($hmmDataDir) if $conf->{opt_msa_option};

    # Shared.pm
    makeClusterDataDirs($conf, $info, $outputDir, $dryRun, $mkPath);
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

    my $hmmDataDir = "$conf->{cluster_data_dir}/hmm";
    my $hmmZip = "$outputDir/${ssnName}_HMMs.zip";

    my $absPath = sub {
        return $_[0] =~ m/^\// ? $_[0] : "$outputDir/$_[0]";
    };

    my $fileInfo = {
        color_only => 1,
        config_file => $configFile,
        tool_path => $toolPath,
        fasta_tool_path => "$toolPath/get_fasta.pl",
        cat_tool_path => "$toolPath/cat_files.pl",
        ssn_out => "$outputDir/$conf->{ssn_out}",
        ssn_out_zip => "$outputDir/$ssnOutZip",
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

    # Shared.pm
    getClusterDataDirInfo($conf, $fileInfo, $outputDir, $conf->{cluster_data_dir});

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
    my $blastDbDir = $self->getBlastDbDir();

    my $scriptArgs = 
        " --config $configFile" .
        " --output-dir $outputDir" .
        " --ssnin $conf->{ssn_in}" .
        " --ssnout $conf->{ssn_out}" .
        " --id-out $conf->{map_file_name}" .
        " --id-out-domain $conf->{domain_map_file_name}" .
        " --stats $conf->{stats}" .
        " --cluster-sizes $conf->{cluster_sizes}" .
        " --sp-clusters-desc $conf->{sp_clusters_desc}" .
        " --sp-singletons-desc $conf->{sp_singletons_desc}" .
        ""
        ;
    $scriptArgs .= getClusterDataDirArgs($fileInfo);

    my $B = $S->getBuilder();
    
    my $ramReservation = computeRamReservation($self->{conf}->{color});

    $B->resource(1, 1, "${ramReservation}gb");
    map { $B->addAction($_); } $self->getEnvironment("est-color");
    
    $B->addAction("cd $outputDir");
    $B->addAction("export EFI_DB_PATH=$blastDbDir");
    $B->addAction("$toolPath/unzip_file.pl --in $conf->{zipped_ssn_in} --out $conf->{ssn_in}") if $conf->{zipped_ssn_in};
    $B->addAction("$toolPath/cluster_gnn.pl $scriptArgs");
    EFI::GNN::Base::addFileActions($B, $fileInfo);
    $B->addAction("touch $outputDir/1.out.completed");

    return $B;
}


1;

