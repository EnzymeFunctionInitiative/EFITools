
package EFI::Job::GNT::GNN;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use EFI::Util qw(checkNetworkType);
use EFI::GNN::Arrows;
use EFI::GNN::Base;
use EFI::GNN;
use EFI::Job::GNT::Shared;

use parent qw(EFI::Job::GNT);

use Getopt::Long qw(:config pass_through);

use constant JOB_TYPE => "gnn";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "ssn-in|ssnin=s",
        "nb-size|n=s",
        "warning-file=s",
        "gnn=s",
        "ssn-out|ssnout=s",
        "cooc|incfrac=i",
        "stats=s",
        "cluster-sizes=s",
        "sp-clusters-desc=s",
        "sp-singletons-desc=s",
        "pfam=s",
        "id-out=s",
        "id-out-domain=s",
        "arrow-file=s",
        "cooc-table=s",
        "hub-count-file=s",
        "parent-dir=s",
        "disable-nnm",
        "gnn-only",
    );

    my $conf = {};
    my $err = $self->validateOptions($parms, $conf);
    
    push @{$self->{startup_errors}}, $err if $err;

    if (not $err) {
        $self->setupDefaults($conf);
    }

    $self->{conf}->{gnn} = $conf;
    $self->{TYPE} = JOB_TYPE;

    return $self;
}


sub validateOptions {
    my $self = shift;
    my $parms = shift;
    my $conf = shift;

    $conf->{ssn_in} = $parms->{"ssn-in"} // "";

    return "No valid --ssn-in argument provided" if not -f $conf->{ssn_in};

    (my $inputFileBase = $conf->{ssn_in}) =~ s%^.*/([^/]+)$%$1%;
    $inputFileBase =~ s/\.zip$//;
    $inputFileBase =~ s/\.xgmml$//;
    $conf->{input_file_base} = $inputFileBase;
    
    $conf->{zipped_ssn_in} = $conf->{ssn_in} if $conf->{ssn_in} =~ m/\.zip$/i;
    $conf->{ssn_in} =~ s/\.zip$//i;

    my $defaultNbSize = 10;
    my $defaultCooc = 20;
    $conf->{cooc} = $parms->{"cooc"} // $defaultCooc;
    $conf->{nb_size} = $parms->{"nb-size"} // $defaultNbSize;

    my $sfx = "_co$conf->{cooc}_ns$conf->{nb_size}";
    $conf->{file_suffix} = $sfx;

    my $defaultGnn = "${inputFileBase}_ssn_cluster_gnn$sfx.xgmml";
    my $defaultSsnOut = "${inputFileBase}_coloredssn$sfx.xgmml";
    my $defaultPfamHubFile = "${inputFileBase}_pfam_family_gnn$sfx.xgmml";
    my $defaultWarningFile = "${inputFileBase}_nomatches_noneighbors$sfx.txt";
    my $defaultArrowDataFile = "${inputFileBase}_arrow_data$sfx.sqlite";
    my $defaultCoocTableFile = "${inputFileBase}_cooc_table$sfx.txt";
    my $defaultHubCountFile = "${inputFileBase}_hub_count$sfx.txt";
    my $defaultStats = "${inputFileBase}_stats$sfx.txt";
    my $defaultClusterSizeFile = "${inputFileBase}_cluster_sizes$sfx.txt";
    my $defaultSwissprotClustersDescFile = "${inputFileBase}_swissprot_clusters_desc$sfx.txt";
    my $defaultSwissprotSinglesDescFile = "${inputFileBase}_swissprot_singles_desc$sfx.txt";
    my $defaultIdOutputFile = "${inputFileBase}_mapping_table$sfx.txt";
    my $defaultIdOutputDomainFile = "${inputFileBase}_mapping_table_domain$sfx.txt";

    $conf->{gnn_out} = $parms->{"gnn"} // $defaultGnn;
    $conf->{ssn_out} = $parms->{"ssn-out"} // $defaultSsnOut;
    $conf->{stats} = $parms->{"stats"} // $defaultStats;
    $conf->{warning_file} = $parms->{"warning-file"} // $defaultWarningFile;
    $conf->{cluster_sizes} = $parms->{"cluster-sizes"} // $defaultClusterSizeFile;
    $conf->{sp_clusters_desc} = $parms->{"sp-clusters-desc"} // $defaultSwissprotClustersDescFile;
    $conf->{sp_singletons_desc} = $parms->{"sp-singletons-desc"} // $defaultSwissprotSinglesDescFile;
    $conf->{pfam_gnn_out} = $parms->{"pfam"} // $defaultPfamHubFile;
    $conf->{arrow_file} = $parms->{"arrow-file"} // $defaultArrowDataFile;
    $conf->{cooc_table} = $parms->{"cooc-table"} // $defaultCoocTableFile;
    $conf->{hub_count_file} = $parms->{"hub-count-file"} // $defaultHubCountFile;
    
    $conf->{id_out} = $parms->{"id-out"} // $defaultIdOutputFile;
    $conf->{id_out_domain} = $parms->{"id-out-domain"} // $defaultIdOutputDomainFile;
    
    $conf->{parent_dir} = $parms->{"parent-dir"} // "";
    $conf->{disable_nnm} = defined $parms->{"disable-nnm"} ? 1 : 0;
    $conf->{full_gnt_run} = not (defined $parms->{"gnn-only"} ? 1 : 0);

    my $err = checkInputs($conf);
    return $err if $err;

    return "";
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $outputDir = $self->getOutputDir();

    ($conf->{ssn_type}, $conf->{is_domain}) = checkNetworkType($conf->{zipped_ssn_in} ? $conf->{zipped_ssn_in} : $conf->{ssn_in});
    $conf->{use_domain} = (not $conf->{ssn_type} or $conf->{is_domain});
}


sub checkInputs {
    my $conf = shift;

    my @keys = (
        "gnn", "ssn_out", "stats", "warning_file", "cluster_sizes", "sp_clusters_desc", "sp_singletons_desc", "pfam",
        "arrow_file", "cooc_table", "hub_count_file", "id_out", "id_out_domain", "parent_dir",
    );

    return "Invalid --nb-size" if $conf->{nb_size} =~ m/\D/;
    return "Invalid --cooc" if $conf->{cooc} =~ m/\D/;
    foreach my $file (@keys) {
        (my $arg = $file) =~ s/_/-/g;
        return "Invalid --$arg" if $conf->{$file} and not EFI::Job::checkSafeFileName($conf->{$file});
    }

    return "";
}


sub getUsage {
    my $self = shift;

    my $showDevSiteOpts = 0;

    my $usage = <<USAGE;
--ssn-in <PATH_TO_SSN_FILE> [--ssn-out <FILE> --gnn <GNN_OUTPUT_XGMML> --pfam <PFAM_OUTPUT_XGMML>
    --nb-size # --cooc #]
USAGE

    if ($showDevSiteOpts) { #dev site only, disable for now
        $usage .= <<USAGE;
    [--gnn-only]
USAGE
    }

    $usage .= <<USAGE;

    --ssn-in            path to uncolored SSN
    --ssn-out           path to output SSN, colored, numbered, and including GNN info;
                        defaults to <INPUT_FILENAME>_coloredssn.xgmml
    --gnn               path to output cluster-centered GNN;
                        defaults to <INPUT_FILENAME>_ssn_cluster_gnn.xgmml
    --pfam              path to output Pfam-centered GNN
                        defaults to <INPUT_FILENAME>_pfam_family_gnn.xgmml
    --nb-size           neighborhood size, the number of neighbors to collect on either side;
                        default 10
    --cooc              minimal co-occurrence percentage lower limit; default 20
USAGE

    if ($showDevSiteOpts) { #dev site only, disable for now
        $usage .= <<USAGE;
    --gnn-only          only create the GNN; don't retrieve FASTA files, etc.
USAGE
    }
    return $usage;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{gnn};

    push @$info, [nb_size => $conf->{nb_size}];
    push @$info, [cooc => $conf->{cooc}];
    push @$info, [gnn => $conf->{gnn_out}];
    push @$info, [ssn_out => $conf->{ssn_out}];
    push @$info, [pfam => $conf->{pfam_gnn_out}];

    return $info;
}


sub getInfo {
    my $self = shift;
    my $conf = shift;
    my $info = shift;

    my $toolPath = $self->getToolPath();
    my $outputDir = $self->getOutputDir();
    my $useDomain = $conf->{use_domain};
    my $clusterDataDir = "$outputDir/" . CLUSTER_DATA_DIR;
    my $sfx = $conf->{file_suffix};

    $info->{color_only} = 0;
    $info->{output_dir} = $self->getOutputDir();
    $info->{config_file} = $self->getConfigFile();
    $info->{fasta_tool_path} = "$toolPath/get_fasta.pl";
    $info->{cat_tool_path} = "$toolPath/cat_files.pl";
    
    $info->{pfam_dir} = "$clusterDataDir/pfam-data";
    $info->{all_pfam_dir} = "$clusterDataDir/all-pfam-data";
    $info->{split_pfam_dir} = "$clusterDataDir/split-pfam-data";
    $info->{all_split_pfam_dir} = "$clusterDataDir/all-split-pfam-data";
    $info->{none_dir} = "$clusterDataDir/pfam-none";

    $info->{pfam_zip} = "$outputDir/$conf->{input_file_base}_pfam_mapping$sfx.zip";
    $info->{all_pfam_zip} = "$outputDir/$conf->{input_file_base}_all_pfam_mapping$sfx.zip";
    $info->{split_pfam_zip} = "$outputDir/$conf->{input_file_base}_split_pfam_mapping$sfx.zip";
    $info->{all_split_pfam_zip} = "$outputDir/$conf->{input_file_base}_all_split_pfam_mapping$sfx.zip";
    $info->{none_zip} = "$outputDir/$conf->{input_file_base}_no_pfam_neighbors$sfx.zip";

    ($info->{ssn_out_zip} = $conf->{ssn_out}) =~ s/\.xgmml$/.zip/;
    ($info->{gnn_zip} = $conf->{gnn_out}) =~ s/\.xgmml$/.zip/;
    ($info->{pfamhubfile_zip} = $conf->{pfam_gnn_out}) =~ s/\.xgmml$/.zip/;
    ($info->{arrow_zip} = $conf->{arrow_file}) =~ s/\.xgmml$/.zip/;

    # Shared.pm
    getClusterDataDirInfo($conf, $info, $outputDir, $clusterDataDir);
}


sub makeDirs {
    my $self = shift;
    my $conf = shift;
    my $info = shift;

    my $useDomain = $conf->{use_domain};

    my $outputDir = $self->getOutputDir();
    my $dryRun = $self->getDryRun();
    my $clusterDataDir = "$outputDir/" . CLUSTER_DATA_DIR;

    # Since we're passing relative paths to the cluster_gnn script we need to create the directories with absolute paths.
    my $mkPath = sub {
        my $dir = $_[0];
        $dir = "$outputDir/$dir" if $dir !~ m%^/%;
        if ($dryRun) {
            print "mkdir $dir\n";
        } else {
            mkdir $dir or die "Unable to create output dir $dir: $!" if not -d $dir;
        }
    };
    
    &$mkPath($clusterDataDir);

    &$mkPath($info->{pfam_dir});
    &$mkPath($info->{all_pfam_dir});
    &$mkPath($info->{split_pfam_dir});
    &$mkPath($info->{all_split_pfam_dir});
    &$mkPath($info->{none_dir});

    # Shared.pm
    makeClusterDataDirs($conf, $info, $outputDir, $dryRun, $mkPath);
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{gnn};
    
    my $fileInfo = {};

    if ($conf->{full_gnt_run}) {
        $self->getInfo($conf, $fileInfo);
        $self->makeDirs($conf, $fileInfo);
    }

    my @jobs;
    my $B;
    my $job;

    my $job1 = $self->getGnnJob($fileInfo);
    push @jobs, {job => $job1, deps => [], name => "submit_gnn"};

    return @jobs;
}


sub getGnnJob {
    my $self = shift;
    my $fileInfo = shift;
    my $conf = $self->{conf}->{gnn};

    my $outputDir = $self->getOutputDir();
    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();
    my $blastDbDir = $self->getBlastDbDir();
    my $removeTemp = $self->getRemoveTemp();
    my $diagramVersion = $EFI::GNN::Arrows::Version;

    my $scriptArgs =
        " --config $configFile" .
        " --output-dir $outputDir" .
        " --nb-size $conf->{nb_size}" .
        " --cooc $conf->{cooc}" .
        " --ssnin $conf->{ssn_in}" .
        " --ssnout $conf->{ssn_out}" .
        " --gnn $conf->{gnn_out}" .
        " --pfam $conf->{pfam_gnn_out}" .
        " --stats $conf->{stats}" .
        " --cluster-sizes $conf->{cluster_sizes}" .
        " --sp-clusters-desc $conf->{sp_clusters_desc}" .
        " --sp-singletons-desc $conf->{sp_singletons_desc}" .
        " --warning-file $conf->{warning_file}" .
        ""
        ;
    
    if ($conf->{full_gnt_run}) {
        $scriptArgs .= 
            " --pfam-dir $fileInfo->{pfam_dir}" .
            " --all-pfam-dir $fileInfo->{all_pfam_dir}" .
            " --split-pfam-dir $fileInfo->{split_pfam_dir}" .
            " --all-split-pfam-dir $fileInfo->{all_split_pfam_dir}" .
            " --none-dir $fileInfo->{none_dir}" .
            " --id-out $conf->{id_out}" .
            " --id-out-domain $conf->{id_out_domain}" .
            " --arrow-file $conf->{arrow_file}" .
            " --cooc-table $conf->{cooc_table}" .
            " --hub-count-file $conf->{hub_count_file}" .
            "";
        $scriptArgs .= getClusterDataDirArgs($fileInfo);
        $scriptArgs .= " --parent-dir $conf->{parent_dir}" if $conf->{parent_dir};
    }

    my $B = $self->getBuilder();
    
    my $ramReservation = computeRamReservation($conf);
    $ramReservation = $self->getMemorySize("gnn"); #TODO: compute deterministically
    $self->requestResources($B, 1, 1, $ramReservation);

    map { $B->addAction($_); } $self->getEnvironment("gnt");
    
    $B->addAction("cd $outputDir");
    $B->addAction("export EFI_DB_PATH=$blastDbDir");
    $B->addAction("$toolPath/unzip_file.pl --in $conf->{zipped_ssn_in} --out $conf->{ssn_in}") if $conf->{zipped_ssn_in};
    $B->addAction("$toolPath/cluster_gnn.pl $scriptArgs");
    EFI::GNN::Base::addFileActions($B, $fileInfo, $removeTemp);
    $B->addAction("\n\n$toolPath/save_version.pl > $outputDir/$self->{completed_name}");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    return $B;
}


1;

