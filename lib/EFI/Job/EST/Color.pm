
package EFI::Job::EST::Color;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Data::Dumper;
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::EST);

use EFI::Util qw(checkNetworkType computeRamReservation);
use EFI::Job::EST::Color::HMM;

use constant JOB_TYPE => "color";
use constant CLUSTER_DATA_DIR => "cluster-data"; #relative for simplicity


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = $self->GetEfiOptions(
        $parms,
        "ssn-in=s",
        "ssn-out=s",
        "ssn-out-zip=s",

        "map-file-name=s",
        "domain-map-file-name=s",
        "stats=s",
        "conv-ratio=s",
        "cluster-sizes=s",
        "cluster-num-map=s",
        "sp-clusters-desc=s",
        "sp-singletons-desc=s",

        "opt-msa-option=s",
        "opt-aa-threshold=s",
        "opt-aa-list=s",
        "opt-min-seq-msa=s",
        "opt-max-seq-msa=s",
        "hmm-zip=s",

        "uniprot-node-zip=s",
        "fasta-zip=s",
        "uniprot-domain-node-zip=s",
        "fasta-domain-zip=s",
        "uniref90-node-zip=s",
        "fasta-uniref90-zip=s",
        "uniref90-domain-node-zip=s",
        "fasta-uniref90-domain-zip=s",
        "uniref50-node-zip=s",
        "fasta-uniref50-zip=s",
        "uniref50-domain-node-zip=s",
        "fasta-uniref50-domain-zip=s",

        "extra-ram:s",
        "cleanup",
        "skip-fasta",
    );

    my $conf = {};
    my ($errors) = $self->validateOptions($parms, $conf);

    if (not scalar @$errors) {
        $self->setupDefaults($conf);
    }

    $self->{conf}->{color} = $conf;
    $self->{TYPE} = JOB_TYPE;

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $self = shift;
    my $parms = shift;
    my $conf = shift;

    # After the script has been created, the file is copied into the directory structure and that version is
    # used.  This path is no longer relevant at that point.
    $conf->{ssn_in} = $parms->{"ssn-in"} // "";

    return ["No valid --ssn-in argument provided"] if not -f $conf->{ssn_in};

    my @errors;

    my $inputFileBase = "";
    $conf->{input_file_base} = $inputFileBase;

    my $defaultSsnOut = $inputFileBase . "coloredssn.xgmml";
    my $defaultSsnOutZip = $inputFileBase . "coloredssn.zip";
    my $defaultMappingTable = $inputFileBase . "mapping_table.txt";
    my $defaultDomainMappingTable = $inputFileBase . "domain_mapping_table.txt";
    my $defaultStats = $inputFileBase . "stats.txt";
    my $defaultClusterSizes = $inputFileBase . "cluster_size.txt";
    my $defaultClusterNumMap = $inputFileBase . "cluster_num_map.txt";
    my $defaultSpClustersDesc = $inputFileBase . "swissprot_clusters_desc.txt";
    my $defaultSpSingletonsDesc = $inputFileBase . "swissprot_singletons_desc.txt";
    my $defaultConvRatio = $inputFileBase . "conv_ratio.txt";
    my $defaultUniprotIdZip = $inputFileBase . "UniProt_IDs.zip";
    my $defaultUniprotDomainIdZip = $inputFileBase . "UniProt_Domain_IDs.zip";
    my $defaultUniRef50IdZip = $inputFileBase . "UniRef50_IDs.zip";
    my $defaultUniRef50DomainIdZip = $inputFileBase . "UniRef50_Domain_IDs.zip";
    my $defaultUniRef90IdZip = $inputFileBase . "UniRef90_IDs.zip";
    my $defaultUniRef90DomainIdZip = $inputFileBase . "UniRef90_Domain_IDs.zip";
    my $defaultFastaZip = $inputFileBase . "FASTA.zip";
    my $defaultFastaDomainZip = $inputFileBase . "FASTA_Domain.zip";
    my $defaultFastaUniRef90Zip = $inputFileBase . "FASTA_UniRef90.zip";
    my $defaultFastaUniRef90DomainZip = $inputFileBase . "FASTA_UniRef90_Domain.zip";
    my $defaultFastaUniRef50Zip = $inputFileBase . "FASTA_UniRef50.zip";
    my $defaultFastaUniRef50DomainZip = $inputFileBase . "FASTA_UniRef50_Domain.zip";
    my $defaultHmmZip = $inputFileBase . "HMMs.zip";
    my $defaultInputSequencesFile = $inputFileBase . "ssn-sequences.fa";

    $conf->{zipped_ssn_in} = $conf->{ssn_in} if $conf->{ssn_in} =~ m/\.zip$/i;
    $conf->{ssn_in} =~ s/\.zip$//i;

    $conf->{ssn_out} = $parms->{"ssn-out"} // $defaultSsnOut;
    $conf->{ssn_out_zip} = $parms->{"ssn-out-zip"} // $defaultSsnOutZip;
    $conf->{map_file_name} = $parms->{"map-file-name"} // $defaultMappingTable;
    $conf->{domain_map_file_name} = $parms->{"domain-map-file-name"} // $defaultDomainMappingTable;
    $conf->{stats} = $parms->{"stats"} // $defaultStats;
    $conf->{cluster_sizes} = $parms->{"cluster-sizes"} // $defaultClusterSizes;
    $conf->{cluster_num_map} = $parms->{"cluster-num-map"} // $defaultClusterNumMap;
    $conf->{sp_clusters_desc} = $parms->{"sp-clusters-desc"} // $defaultSpClustersDesc;
    $conf->{sp_singletons_desc} = $parms->{"sp-singletons-desc"} // $defaultSpSingletonsDesc;
    $conf->{conv_ratio} = $parms->{"conv-ratio"} // $defaultConvRatio;
    $conf->{input_sequences_file} = $parms->{"input-sequences-file"} // $defaultInputSequencesFile;

    $conf->{opt_msa_option} = $parms->{"opt-msa-option"} // 0;
    $conf->{opt_aa_threshold} = $parms->{"opt-aa-threshold"} // "";
    $conf->{opt_aa_list} = $parms->{"opt-aa-list"} // "";
    $conf->{opt_min_seq_msa} = $parms->{"opt-min-seq-msa"} // 5;
    $conf->{opt_max_seq_msa} = $parms->{"opt-max-seq-msa"} // 700;
    $conf->{hmm_zip} = $parms->{"hmm-zip"} // $defaultHmmZip;
    $conf->{opt_msa_option} = 0 if $conf->{opt_msa_option} =~ m/CR/ and $conf->{opt_aa_list} !~ m/^[A-Z,]+$/;

    $conf->{uniprot_node_zip} = $parms->{"uniprot-id-zip"} // $defaultUniprotIdZip;
    $conf->{uniprot_domain_node_zip} = $parms->{"uniprot-domain-id-zip"} // $defaultUniprotDomainIdZip;
    $conf->{uniref50_node_zip} = $parms->{"uniref50-id-zip"} // $defaultUniRef50IdZip;
    $conf->{uniref50_domain_node_zip} = $parms->{"uniref50-domain-id-zip"} // $defaultUniRef50DomainIdZip;
    $conf->{uniref90_node_zip} = $parms->{"uniref90-id-zip"} // $defaultUniRef90IdZip;
    $conf->{uniref90_domain_node_zip} = $parms->{"uniref90-domain-id-zip"} // $defaultUniRef90DomainIdZip;

    $conf->{fasta_zip} = $parms->{"fasta-zip"} // $defaultFastaZip;
    $conf->{fasta_domain_zip} = $parms->{"fasta-domain-zip"} // $defaultFastaDomainZip;
    $conf->{fasta_uniref90_zip} = $parms->{"fasta-uniref90-zip"} // $defaultFastaUniRef90Zip;
    $conf->{fasta_uniref90_domain_zip} = $parms->{"fasta-uniref90-domain-zip"} // $defaultFastaUniRef90DomainZip;
    $conf->{fasta_uniref50_zip} = $parms->{"fasta-uniref50-zip"} // $defaultFastaUniRef50Zip;
    $conf->{fasta_uniref50_domain_zip} = $parms->{"fasta-uniref50-domain-zip"} // $defaultFastaUniRef50DomainZip;

    $conf->{extra_ram} = $parms->{"extra-ram"} // 0;
    $conf->{cleanup} = $parms->{"cleanup"} // 0;
    $conf->{skip_fasta} = $parms->{"skip-fasta"} // 0;

    return \@errors;
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
    ($conf->{ssn_type}, $conf->{is_domain}) = checkNetworkType($conf->{ssn_in});
    $conf->{use_domain} = (not $conf->{ssn_type} or $conf->{is_domain});
    $conf->{cluster_data_dir} = CLUSTER_DATA_DIR;
}


sub createJobStructure {
    my $self = shift;
    my $conf = $self->{conf}->{color};
    my @dirs = $self->SUPER::createJobStructure();
    return @dirs;
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{color};

    my $fileInfo = $self->getFileInfo();
    $self->makeDirs($fileInfo);

    my @jobs;

    my $job1 = $self->getColorSsnJob($fileInfo);
    push @jobs, {job => $job1, deps => [], name => "color_ssn"};

    my $job2;
    if ($conf->{opt_msa_option}) {
        $job2 = $self->getHmmAndStuffJob($fileInfo);
        push @jobs, {job => $job2, deps => [$job1], name => "hmm_and_stuff"};
    }

    if ($conf->{cleanup}) {
        my $job3 = $self->getCleanupJob($fileInfo);
        my $deps = $job2 ? [$job2] : [$job1];
        push @jobs, {job => $job3, deps => $deps, name => "color_cleanup"};
    }

    return @jobs;
}


sub absPath {
    my $self = shift;
    my $dir = shift;
    my $outputPath = $self->getOutputDir();
    return $dir =~ m/^\// ? $dir : "$outputPath/$dir";
}


sub makeDirs {
    my $self = shift;
    my $conf = $self->{conf}->{color};
    my $info = shift;

    my $useDomain = $conf->{use_domain};

    my $outputPath = $self->getOutputDir();
    my $dryRun = $self->getDryRun();

    # Since we're passing relative paths to the cluster_gnn script we need to create the directories with absolute paths.
    my $mkPath = sub {
        my $dir = $_[0];
        $dir = "$outputPath/$dir" if $dir !~ m%^/%;
        #my $dir = "$outputPath/$_[0]";
        if ($dryRun) {
            print "mkdir $dir\n";
        } else {
            mkdir $dir or die "Unable to create output dir $dir: $!" if not -d $dir;
        }
    };
    
    &$mkPath($conf->{cluster_data_dir});
    &$mkPath($info->{hmm_data_dir}) if $conf->{opt_msa_option};

    $self->makeClusterDataDirs($info, $outputPath, $dryRun, $mkPath);
}


sub getFileInfo {
    my $self = shift;
    my $conf = $self->{conf}->{color};

    my $outputPath = $self->getOutputDir(); # intermediate output
    my $resultsPath = $self->getResultsDir(); # final output
    my $dryRun = $self->getDryRun();
    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();
    my $ssnType = $conf->{ssn_type};
    my $useDomain = $conf->{is_domain};

    my $domainMapFileName = $conf->{domain_map_file_name};
    my $mapFileName = $conf->{map_file_name};
    (my $ssnOutZip = $conf->{ssn_out}) =~ s/\.xgmml$/.zip/;

    my $hmmZip = $conf->{hmm_zip};
    my $hmmDataDirName = "$conf->{cluster_data_dir}/hmm";
    my $hmmDataDir = $self->absPath($hmmDataDirName);

    my $fileInfo = {
        color_only => 1,
        config_file => $configFile,
        tool_path => $toolPath,
        fasta_tool_path => "$toolPath/get_fasta.pl",
        cat_tool_path => "$toolPath/cat_files.pl",
        ssn_out => $conf->{ssn_out},
        ssn_out_zip => $ssnOutZip,

        domain_map_file => $domainMapFileName,
        map_file => $mapFileName,

        input_seqs_file => $conf->{input_sequences_file},
        results_path => $resultsPath,

        hmm_data_dir => $hmmDataDir,
    };

    if ($conf->{opt_msa_option}) {
        $fileInfo->{hmm_tool_path} = "$toolPath/build_hmm.pl"; #TODO: remove this???
        $fileInfo->{hmm_tool_dir} = "$toolPath/hmm";
        $fileInfo->{hmm_zip} = $hmmZip;
        $fileInfo->{hmm_logo_list} = "$outputPath/hmm_logos.txt";
        $fileInfo->{hmm_weblogo_list} = "$outputPath/weblogos.txt";
        $fileInfo->{hmm_histogram_list} = "$outputPath/histograms.txt";
        $fileInfo->{hmm_alignment_list} = "$outputPath/alignments.txt";
        $fileInfo->{hmm_consensus_residue_info_list} = "$outputPath/consensus_residue.txt";
        $fileInfo->{hmm_rel_path} = $hmmDataDirName;
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
    
        $fileInfo->{output_path} = $outputPath;
        $fileInfo->{cluster_size_file} = $conf->{cluster_sizes};
        $fileInfo->{ssn_type} = $ssnType;
        $fileInfo->{hmm_zip_prefix} = $conf->{input_file_base};

        $fileInfo->{compute_pim} = 1;

        $fileInfo->{weblogo_bin} = "$toolPath/weblogo";
    }

    $self->getClusterDataDirInfo($fileInfo, $outputPath);

    return $fileInfo;
}


sub getColorSsnJob {
    my $self = shift;
    my $fileInfo = shift;
    my $conf = $self->{conf}->{color};

    my $B = $self->getBuilder();

    my $outputPath = $self->getOutputDir();
    my $resultsDir = $self->getResultsDir();
    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();
    my $blastDbDir = $self->getBlastDbDir();
    my $removeTemp = $self->getRemoveTemp();
    my $skipFasta = $conf->{skip_fasta};

    # Copy things around
    my $targetSsn = "$outputPath/input_ssn.xgmml";
    if ($conf->{zipped_ssn_in}) {
        my $targetZip = "$outputPath/input_ssn.zip";
        $B->addAction("cp $conf->{zipped_ssn_in} $targetZip");
        $B->addAction("$toolPath/unzip_file.pl --in $targetZip --out $targetSsn");
    } else {
        $B->addAction("cp $conf->{ssn_in} $targetSsn");
    }

    my $scriptArgs = 
        " --config $configFile" .
        " --output-dir $outputPath" .
        " --results-dir $resultsDir" .
        " --ssn-in $targetSsn" .
        " --ssn-out $conf->{ssn_out}" .
        " --id-out $conf->{map_file_name}" .
        " --id-out-domain $conf->{domain_map_file_name}" .
        " --stats $conf->{stats}" .
        " --cluster-sizes $conf->{cluster_sizes}" .
        " --sp-clusters-desc $conf->{sp_clusters_desc}" .
        " --sp-singletons-desc $conf->{sp_singletons_desc}" .
        ""
        ;
    $scriptArgs .= $self->getClusterDataDirArgs($fileInfo);

    if ($conf->{extra_ram} =~ m/^\d+$/) {
        my $ramReservation = $conf->{extra_ram};
        $self->requestResources($B, 1, 1, $ramReservation);
    } elsif ($conf->{extra_ram} eq "D" and not $conf->{zipped_ssn_in}) {
        my $fileSize = -s $conf->{ssn_in};
        my $ramReservation = computeRamReservation($fileSize);
        $self->requestResources($B, 1, 1, $ramReservation);
    } else {
        $self->requestResourcesByName($B, 1, 1, "color");
    }

    map { $B->addAction($_); } $self->getEnvironment("est-color");

    $B->addAction("cd $outputPath");
    $B->addAction("export EFI_DB_PATH=$blastDbDir");

    $B->addAction("$toolPath/cluster_gnn.pl $scriptArgs");
    $self->addFileActions($B, $fileInfo, $skipFasta);

    $B->addAction("touch $outputPath/$self->{completed_name}") if (not $conf->{opt_msa_option} and not $conf->{cleanup});

    return $B;
}


sub getClusterDataDirArgs {
    my $self = shift;
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


sub getHmmAndStuffJob {
    my $self = shift;
    my $info = shift;
    my $conf = $self->{conf}->{color};

    my $outputPath = $self->getOutputDir();
    my $np = $info->{num_tasks} ? $info->{num_tasks} : 1;

    my $B = $self->getBuilder();
    $B->setScriptAbortOnError(0); # don't abort on error

    $self->requestResourcesByName($B, 1, $np, "hmm");

    map { $B->addAction($_); } $self->getEnvironment("color-hmm-pim") if $info->{compute_pim};
    map { $B->addAction($_); } $self->getEnvironment("color-hmm");

    EFI::Job::EST::Color::HMM::makeJob($B, $info);

    $B->addAction("touch $outputPath/$self->{completed_name}") if not $conf->{cleanup};

    return $B;
}


sub getCleanupJob {
    my $self = shift;
    my $info = shift;
    my $conf = $self->{conf}->{color};

    my $outputPath = $self->getOutputDir();

    my $B = $self->getBuilder();

    $self->requestResources($B, 1, 1, 1);

    my @dirs;
    my $get = sub { return ($_->{id_dir}, $_->{fasta_dir}) };
    push @dirs, &$get($info->{uniprot});
    push @dirs, &$get($info->{uniprot_domain});
    push @dirs, &$get($info->{uniref50});
    push @dirs, &$get($info->{uniref50_domain});
    push @dirs, &$get($info->{uniref90});
    push @dirs, &$get($info->{uniref90_domain});
    my $paths = join(" ", grep { -d $_ } map { "$outputPath/$_" } @dirs);

    $B->addAction("cd $outputPath");
    $B->addAction("rm -rf $paths");
    $B->addAction("touch $outputPath/$self->{completed_name}");

    return $B;
}


sub addFileActions {
    my $self = shift;
    my $B = shift; # This is an EFI::SchedulerApi::Builder object
    my $info = shift;
    my $skipFasta = shift || 0;

    my $fastaTool = "$info->{fasta_tool_path} --config $info->{config_file}";
    my $extraFasta = $info->{input_seqs_file} ? " --input-sequences $info->{input_seqs_file}" : "";

    my $writeBashZipIf = sub {
        my ($inDir, $outZip, $testFile, $extraFn) = @_;
        if ($outZip and $inDir) {
            $B->addAction("if [[ -s $inDir/$testFile ]]; then");
            $B->addAction("    zip -jq -r $outZip $inDir");
            &$extraFn() if $extraFn;
            $B->addAction("fi");
            $B->addAction("");
        }
    };

    my $writeGetFastaIf = sub {
        my ($inDir, $outZip, $testFile, $domIdDir, $outDir, $domOutDir, $extraFasta) = @_;
        $extraFasta = "" if not defined $extraFasta;
        if ($outZip and $inDir) {
            my $outDirArg = " -out-dir $outDir";
            my $extraFn = sub {
                if (not $skipFasta) {
                    $B->addAction("    $fastaTool -node-dir $inDir $outDirArg $extraFasta");
                }
            };
            if ($domIdDir and $domOutDir) {
                $extraFn = sub {
                    if (not $skipFasta) {
                        $B->addAction("    $fastaTool -domain-out-dir $domOutDir -node-dir $domIdDir $outDirArg $extraFasta");
                    }
                };
            }
            &$writeBashZipIf($inDir, $outZip, $testFile, $extraFn);
        }
    };

    $B->addAction("zip -jq $info->{ssn_out_zip} $info->{ssn_out}") if $info->{ssn_out} and $info->{ssn_out_zip};
    $B->addAction("HMM_FASTA_DIR=\"\"");
    $B->addAction("HMM_FASTA_DOMAIN_DIR=\"\"");

    my $outFn = sub {
        my ($dirs, $domDirs, $type, $extraFasta) = @_;
        my @args = ($dirs->{id_dir}, $dirs->{id_zip}, "cluster_All_${type}_IDs.txt", $domDirs->{id_dir}, $dirs->{fasta_dir}, $domDirs->{fasta_dir});
        push @args, $extraFasta if $extraFasta;
        &$writeGetFastaIf(@args);
    };
    &$outFn($info->{uniprot}, $info->{uniprot_domain}, "UniProt", $extraFasta);
    &$outFn($info->{uniref90}, $info->{uniref90_domain}, "UniRef90");
    &$outFn($info->{uniref50}, $info->{uniref50_domain}, "UniRef50");

    $outFn = sub {
        my ($dirs, $type) = @_;
        &$writeBashZipIf($dirs->{id_dir}, $dirs->{id_zip}, "cluster_All_${type}.txt");
    };
    &$outFn($info->{uniprot_domain}, "UniProt_Domain");
    &$outFn($info->{uniref90_domain}, "UniRef90_Domain");
    &$outFn($info->{uniref50_domain}, "UniRef50_Domain");

    $outFn = sub {
        my ($dirs, $varType) = @_;
        &$writeBashZipIf($dirs->{fasta_dir}, $dirs->{fasta_zip}, "all.fasta", sub { $B->addAction("    HMM_FASTA${varType}_DIR=$dirs->{fasta_dir}"); });
    };
    &$outFn($info->{uniprot}, "");
    &$outFn($info->{uniprot_domain}, "_DOMAIN");
    &$outFn($info->{uniref90}, "");
    &$outFn($info->{uniref90_domain}, "_DOMAIN");
    &$outFn($info->{uniref50}, "");
    &$outFn($info->{uniref50_domain}, "_DOMAIN");
}


sub makeClusterDataDirs {
    my $self = shift;
    my $info = shift;
    my $outputPath = shift;
    my $dryRun = shift;
    my $mkPath = shift;
    my $conf = $self->{conf}->{color};

    my $doMake = sub {
        my $s = $_[0];
        my $path1 = ($s->{id_dir} =~ m/^\// ? $s->{id_dir} : "$outputPath/$s->{id_dir}");
        &$mkPath($path1) if -d $path1;
        my $path2 = ($s->{fasta_dir} =~ m/^\// ? $s->{fasta_dir} : "$outputPath/$s->{fasta_dir}");
        &$mkPath($path2) if -d $path2;
    };

    &$doMake($info->{uniprot});
    &$doMake($info->{uniprot_domain}) if $info->{uniprot_domain};
    &$doMake($info->{uniref50}) if $info->{uniref50};
    &$doMake($info->{uniref50_domain}) if $info->{uniref50_domain};
    &$doMake($info->{uniref90}) if $info->{uniref90};
    &$doMake($info->{uniref90_domain}) if $info->{uniref90_domain};
}


sub getClusterDataDirInfo {
    my $self = shift;
    my $fileInfo = shift;
    my $conf = $self->{conf}->{color};

    my $resultsDir = $self->getResultsDir();

    my $clusterDataDir = $conf->{cluster_data_dir};
    my $ssnType = $conf->{ssn_type};

    my $inputFileBase = $conf->{input_file_base};
    my $useDomain = $conf->{use_domain};

    my $uniprotNodeDataDir          = "$clusterDataDir/uniprot-nodes";
    my $uniprotDomainNodeDataDir    = "$clusterDataDir/uniprot-domain-nodes";
    my $uniRef50NodeDataDir         = "$clusterDataDir/uniref50-nodes";
    my $uniRef50DomainNodeDataDir   = "$clusterDataDir/uniref50-domain-nodes";
    my $uniRef90NodeDataDir         = "$clusterDataDir/uniref90-nodes";
    my $uniRef90DomainNodeDataDir   = "$clusterDataDir/uniref90-domain-nodes";
    my $fastaUniProtDataDir         = "$clusterDataDir/fasta";
    my $fastaUniProtDomainDataDir   = "$clusterDataDir/fasta-domain";
    my $fastaUniRef90DataDir        = "$clusterDataDir/fasta-uniref90";
    my $fastaUniRef90DomainDataDir  = "$clusterDataDir/fasta-uniref90-domain";
    my $fastaUniRef50DataDir        = "$clusterDataDir/fasta-uniref50";
    my $fastaUniRef50DomainDataDir  = "$clusterDataDir/fasta-uniref50-domain";

    my $uniprotIdZip = "$resultsDir/$conf->{uniprot_node_zip}";
    my $uniprotDomainIdZip = "$resultsDir/$conf->{uniprot_domain_node_zip}";
    my $uniRef50IdZip = "$resultsDir/$conf->{uniref50_node_zip}";
    my $uniRef50DomainIdZip = "$resultsDir/$conf->{uniref50_domain_node_zip}";
    my $uniRef90IdZip = "$resultsDir/$conf->{uniref90_node_zip}";
    my $uniRef90DomainIdZip = "$resultsDir/$conf->{uniref90_domain_node_zip}";

    my $fastaZip = "$resultsDir/$conf->{fasta_zip}";
    my $fastaDomainZip = "$resultsDir/$conf->{fasta_domain_zip}";
    my $fastaUniRef90Zip = "$resultsDir/$conf->{fasta_uniref90_zip}";
    my $fastaUniRef90DomainZip = "$resultsDir/$conf->{fasta_uniref90_domain_zip}";
    my $fastaUniRef50Zip = "$resultsDir/$conf->{fasta_uniref50_zip}";
    my $fastaUniRef50DomainZip = "$resultsDir/$conf->{fasta_uniref50_domain_zip}";

    $fileInfo->{uniprot} = {
        id_dir => $uniprotNodeDataDir,
        fasta_dir => $self->absPath($fastaUniProtDataDir),
        id_zip => $uniprotIdZip,
        fasta_zip => $fastaZip,
    };

    # The 'not $ssnType or' statement ensures that this happens.
    if (not $ssnType or $ssnType eq "UniProt" and $useDomain) {
        $fileInfo->{uniprot_domain} = {
            id_dir => $uniprotDomainNodeDataDir,
            fasta_dir => $self->absPath($fastaUniProtDomainDataDir),
            id_zip => $uniprotDomainIdZip,
            fasta_zip => $fastaDomainZip,
        };
    }
    
    if (not $ssnType or $ssnType eq "UniRef90" or $ssnType eq "UniRef50") {
        $fileInfo->{uniref90} = {
            id_dir => $uniRef90NodeDataDir,
            fasta_dir => $self->absPath($fastaUniRef90DataDir),
            id_zip => $uniRef90IdZip,
            fasta_zip => $fastaUniRef90Zip,
        };
        if (not $ssnType or $useDomain and $ssnType eq "UniRef90") {
            $fileInfo->{uniref90_domain} = {
                id_dir => $uniRef90DomainNodeDataDir,
                fasta_dir => $self->absPath($fastaUniRef90DomainDataDir),
                id_zip => $uniRef90DomainIdZip,
                fasta_zip => $fastaUniRef90DomainZip,
            };
        }
    }
    
    if (not $ssnType or $ssnType eq "UniRef50") {
        $fileInfo->{uniref50} = {
            id_dir => $uniRef50NodeDataDir,
            fasta_dir => $self->absPath($fastaUniRef50DataDir),
            id_zip => $uniRef50IdZip,
            fasta_zip => $fastaUniRef50Zip,
        };
        if (not $ssnType or $useDomain) {
            $fileInfo->{uniref50_domain} = {
                id_dir => $uniRef50DomainNodeDataDir,
                fasta_dir => $self->absPath($fastaUniRef50DomainDataDir),
                id_zip => $uniRef50DomainIdZip,
                fasta_zip => $fastaUniRef50DomainZip,
            };
        }
    }
}


1;

