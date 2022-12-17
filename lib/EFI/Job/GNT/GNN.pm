
package EFI::Job::GNT::GNN;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::GNT);

use EFI::Util qw(checkNetworkType computeRamReservation);
use EFI::GNN::Arrows;
use EFI::GNN::Base;
use EFI::GNN;

use constant JOB_TYPE => "gnn";
use constant CLUSTER_DATA_DIR => "cluster-data"; #relative for simplicity


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = $self->GetEfiOptions(
        $parms,
        "ssn-in|ssnin=s",
        "gnn=s",
        "gnn-zip=s",
        "ssn-out|ssnout=s",
        "ssn-out-zip|ssnout=s",

        "warning-file=s",
        "stats=s",
        "cluster-sizes=s",
        "sp-clusters-desc=s",
        "sp-singletons-desc=s",

        "pfam=s",
        "pfam-zip=s",
        "all-pfam=s",
        "all-pfam-zip=s",
        "split-pfam-zip=s",
        "all-split-pfam-zip=s",

        "id-out=s",
        "id-out-domain=s",

        "arrow-file-zip=s",
        "arrow-file=s",
        "cooc-table=s",
        "hub-count-file=s",
        "parent-dir=s",
        "nb-size|n=s",
        "cooc|incfrac=i",
        "suffix=s",
        "disable-nnm",
        "gnn-only",
        "extra-ram:s",
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

    #(my $inputFileBase = $conf->{ssn_in}) =~ s%^.*/([^/]+)$%$1%;
    #$inputFileBase =~ s/\.zip$//;
    #$inputFileBase =~ s/\.xgmml$//;
    my $inputFileBase = "";
    $conf->{input_file_base} = $inputFileBase;
    
    $conf->{zipped_ssn_in} = $conf->{ssn_in} if $conf->{ssn_in} =~ m/\.zip$/i;
    $conf->{ssn_in} =~ s/\.zip$//i;

    my $defaultNbSize = 10;
    my $defaultCooc = 20;
    $conf->{cooc} = $parms->{"cooc"} // $defaultCooc;
    $conf->{nb_size} = $parms->{"nb-size"} // $defaultNbSize;

    my $defaultSuffix = "_co$conf->{cooc}_ns$conf->{nb_size}";
    my $sfx = $parms->{"suffix"} ? "_".$parms->{"suffix"} : $defaultSuffix;
    $conf->{file_suffix} = $sfx;

    my $defaultGnn = "${inputFileBase}ssn_cluster_gnn$sfx.xgmml";
    my $defaultGnnZip = "${inputFileBase}ssn_cluster_gnn$sfx.zip";
    my $defaultSsnOut = "${inputFileBase}coloredssn$sfx.xgmml";
    my $defaultSsnOutZip = "${inputFileBase}coloredssn$sfx.zip";
    my $defaultPfamHubFile = "${inputFileBase}pfam_family_gnn$sfx.xgmml";
    my $defaultPfamHubFileZip = "${inputFileBase}pfam_family_gnn$sfx.zip";
    my $defaultArrowDataFile = "${inputFileBase}arrow_data$sfx.sqlite";
    my $defaultArrowDataFileZip = "${inputFileBase}arrow_data$sfx.zip";
    my $defaultWarningFile = "${inputFileBase}nomatches_noneighbors$sfx.txt";
    my $defaultCoocTableFile = "${inputFileBase}cooc_table$sfx.txt";
    my $defaultHubCountFile = "${inputFileBase}hub_count$sfx.txt";
    my $defaultStats = "${inputFileBase}stats$sfx.txt";
    my $defaultClusterSizeFile = "${inputFileBase}cluster_sizes$sfx.txt";
    my $defaultSwissprotClustersDescFile = "${inputFileBase}swissprot_clusters_desc$sfx.txt";
    my $defaultSwissprotSinglesDescFile = "${inputFileBase}swissprot_singles_desc$sfx.txt";
    my $defaultIdOutputFile = "${inputFileBase}mapping_table$sfx.txt";
    my $defaultIdOutputDomainFile = "${inputFileBase}mapping_table_domain$sfx.txt";

    my $defaultPfamMappingZip = "${inputFileBase}pfam_mapping$sfx.zip";
    my $defaultAllPfamMappingZip = "${inputFileBase}all_pfam_mapping$sfx.zip";
    my $defaultSplitPfamMappingZip = "${inputFileBase}split_pfam_mapping$sfx.zip";
    my $defaultAllSplitPfamMappingZip = "${inputFileBase}all_split_pfam_mapping$sfx.zip";
    my $defaultNoneZip = "${inputFileBase}no_pfam_neighbors$sfx.zip";

    $conf->{gnn_out} = $parms->{"gnn"} // $defaultGnn;
    $conf->{gnn_zip} = $parms->{"gnn-zip"} // $defaultGnnZip;
    $conf->{ssn_out} = $parms->{"ssn-out"} // $defaultSsnOut;
    $conf->{ssn_out_zip} = $parms->{"ssn-out-zip"} // $defaultSsnOutZip;
    $conf->{stats} = $parms->{"stats"} // $defaultStats;
    $conf->{warning_file} = $parms->{"warning-file"} // $defaultWarningFile;
    $conf->{cluster_sizes} = $parms->{"cluster-sizes"} // $defaultClusterSizeFile;
    $conf->{sp_clusters_desc} = $parms->{"sp-clusters-desc"} // $defaultSwissprotClustersDescFile;
    $conf->{sp_singletons_desc} = $parms->{"sp-singletons-desc"} // $defaultSwissprotSinglesDescFile;
    $conf->{pfamhubfile} = $parms->{"pfam"} // $defaultPfamHubFile;
    $conf->{pfamhubfile_zip} = $parms->{"pfam-zip"} // $defaultPfamHubFileZip;
    $conf->{arrow_file} = $parms->{"arrow-file"} // $defaultArrowDataFile;
    $conf->{arrow_zip} = $parms->{"arrow-file-zip"} // $defaultArrowDataFileZip;
    $conf->{cooc_table} = $parms->{"cooc-table"} // $defaultCoocTableFile;
    $conf->{hub_count_file} = $parms->{"hub-count-file"} // $defaultHubCountFile;

    $conf->{id_out} = $parms->{"id-out"} // $defaultIdOutputFile;
    $conf->{id_out_domain} = $parms->{"id-out-domain"} // $defaultIdOutputDomainFile;

    $conf->{pfam_zip} = $parms->{"pfam-zip"} // $defaultPfamMappingZip;
    $conf->{all_pfam_zip} = $parms->{"all-pfam-zip"} // $defaultAllPfamMappingZip;
    $conf->{split_pfam_zip} = $parms->{"split-pfam-zip"} // $defaultSplitPfamMappingZip;
    $conf->{all_split_pfam_zip} = $parms->{"all-split-pfam-zip"} // $defaultAllSplitPfamMappingZip;
    $conf->{none_zip} = $parms->{"none-zip"} // $defaultNoneZip;

    $conf->{parent_dir} = $parms->{"parent-dir"} // "";
    $conf->{disable_nnm} = defined $parms->{"disable-nnm"} ? 1 : 0;
    $conf->{full_gnt_run} = not (defined $parms->{"gnn-only"} ? 1 : 0);
    $conf->{extra_ram} = $parms->{"extra-ram"} // 0;

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
    push @$info, [pfam => $conf->{pfamhubfile}];

    return $info;
}


sub getInfo {
    my $self = shift;
    my $conf = shift;
    my $info = shift;
    my $wantFullPaths = shift || 0;

    my $toolPath = $self->getToolPath();
    my $outputDir = $wantFullPaths ? $self->getOutputDir() : "";
    my $useDomain = $conf->{use_domain};
    my $clusterDataDir = ($outputDir ? "$outputDir/" : "") . CLUSTER_DATA_DIR;
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

    $info->{pfam_zip} = $outputDir . $conf->{pfam_zip};
    $info->{all_pfam_zip} = $outputDir . $conf->{all_pfam_zip};
    $info->{split_pfam_zip} = $outputDir . $conf->{split_pfam_zip};
    $info->{all_split_pfam_zip} = $outputDir . $conf->{all_split_pfam_zip};
    $info->{none_zip} = $outputDir . $conf->{none_zip};

    $info->{ssn_out_zip} = $outputDir . $conf->{ssn_out_zip};
    $info->{gnn_zip} = $outputDir . $conf->{gnn_zip};
    $info->{pfamhubfile_zip} = $outputDir . $conf->{pfamhubfile_zip};
    $info->{arrow_zip} = $outputDir . $conf->{arrow_zip};
}


sub makeDirs {
    my $self = shift;
    my $conf = shift;
    my $info = shift;

    my $useDomain = $conf->{use_domain};

    my $outputDir = $self->getOutputDir();
    my $dryRun = $self->getDryRun();
    my $clusterDataDir = $outputDir . "/" . CLUSTER_DATA_DIR;

    # Since we're passing relative paths to the cluster_gnn script we need to create the directories with absolute paths.
    my $mkPath = sub {
        my $dir = $_[0];
        $dir = $outputDir . "/$dir" if $dir !~ m%^/%;
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
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{gnn};
    
    my $fileInfo = {};

    my $wantFullPaths = 0;
    if ($conf->{full_gnt_run}) {
        $self->getInfo($conf, $fileInfo, $wantFullPaths);
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
        " --pfam $conf->{pfamhubfile}" .
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
        $scriptArgs .= " --parent-dir $conf->{parent_dir}" if $conf->{parent_dir};
    }

    my $B = $self->getBuilder();

    if ($conf->{extra_ram} =~ m/^\d+$/) {
        my $ramReservation = $conf->{extra_ram};
        $self->requestResources($B, 1, 1, $ramReservation);
    } elsif ($conf->{extra_ram} eq "D" and not $conf->{zipped_ssn_in}) {
        my $fileSize = -s $conf->{ssn_in};
        my $ramReservation = computeRamReservation($fileSize);
        $self->requestResources($B, 1, 1, $ramReservation);
    } else {
        $self->requestResourcesByName($B, 1, 1, "gnn");
    }

    map { $B->addAction($_); } $self->getEnvironment("gnt");
    
    $B->addAction("cd $outputDir");
    $B->addAction("export EFI_DB_PATH=$blastDbDir");
    $B->addAction("$toolPath/unzip_file.pl --in $conf->{zipped_ssn_in} --out $conf->{ssn_in}") if $conf->{zipped_ssn_in};
    $B->addAction("$toolPath/cluster_gnn.pl $scriptArgs");
    $self->addFileActions($B, $fileInfo);
    $B->addAction("\n\n$toolPath/save_version.pl > $outputDir/$self->{completed_name}");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    return $B;
}

sub addFileActions {
    my $self = shift;
    my $B = shift;
    my $info = shift;

    $B->addAction("zip -jq $info->{ssn_out_zip} $info->{ssn_out}")                              if $info->{ssn_out} and $info->{ssn_out_zip};
    $B->addAction("zip -jq $info->{gnn_zip} $info->{gnn}")                                      if $info->{gnn} and $info->{gnn_zip};
    $B->addAction("zip -jq $info->{pfamhubfile_zip} $info->{pfamhubfile}")                      if $info->{pfamhubfile_zip} and $info->{pfamhubfile};
    $B->addAction("zip -jq -r $info->{pfam_zip} $info->{pfam_dir} -i '*'")                      if $info->{pfam_zip} and $info->{pfam_dir};
    $B->addAction("zip -jq -r $info->{all_pfam_zip} $info->{all_pfam_dir} -i '*'")              if $info->{all_pfam_zip} and $info->{all_pfam_dir};
    $B->addAction("zip -jq -r $info->{split_pfam_zip} $info->{split_pfam_dir} -i '*'")          if $info->{split_pfam_zip} and $info->{split_pfam_dir};
    $B->addAction("zip -jq -r $info->{all_split_pfam_zip} $info->{all_split_pfam_dir} -i '*'")  if $info->{all_split_pfam_zip} and $info->{all_split_pfam_dir};
    $B->addAction("zip -jq -r $info->{none_zip} $info->{none_dir}")                             if $info->{none_zip} and $info->{none_dir};
    $B->addAction("zip -jq $info->{arrow_zip} $info->{arrow_file}")                             if $info->{arrow_zip} and $info->{arrow_file};
}

1;

