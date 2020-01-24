
package EFI::Job::CGFP::Quantify;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use Getopt::Long qw(:config pass_through);

use parent qw(EFI::Job::CGFP);

use EFI::CGFP qw(getMetagenomeInfo);

use constant JOB_TYPE => "cgfp-quantify";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "metagenome-db=s",
        "metagenome-ids=s",
        "quantify-dir=s",
        "protein-file=s",
        "cluster-file=s",
        "parent-quantify-id=i",
        "search-type=s",
    );

    my $conf = $self->{conf}->{sb}; # Already exists
    my $err = validateOptions($self, $parms, $conf);
    
    push @{$self->{startup_errors}}, $err if $err;

    if (not $err) {
        $self->setupDefaults($conf);
    }

    $self->{conf}->{sb} = $conf;
    $self->{TYPE} = JOB_TYPE;

    return $self;
}


sub validateOptions {
    my $self = shift;
    my $parms = shift;
    my $conf = shift;

    $conf->{metagenome_db} = $parms->{"metagenome-db"} // "";
    $conf->{metagenome_ids} = $parms->{"metagenome-ids"} // "";
    $conf->{quantify_dir} = $parms->{"quantify-dir"} // "";
    $conf->{protein_file_name} = $parms->{"protein-file"} // "protein_abundance.txt";
    $conf->{cluster_file_name} = $parms->{"cluster-file"} // "cluster_abundance.txt";
    $conf->{parent_quantify_id} = $parms->{"parent-quantify-id"} // "";
    $conf->{search_type} = $parms->{"search-type"} // "";
    
    $conf->{search_type} = "usearch" if $conf->{search_type} ne "diamond";

    return "--quantify-dir for putting quantify results in is required" if not $conf->{quantify_dir};
    return "--metagenome-db required" if not $conf->{metagenome_db};
    return "--metagenome-ids required" if not $conf->{metagenome_ids};

    my $dbPath = $self->getConfigValue("cgfp.database", $conf->{metagenome_db});
    return "Invalid --metagenome-db" if not -f $dbPath;
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $jobId = $self->getJobId();
    
    # src_dir is the identify dir path/parent identify dir path
    # real_dir is the identify dir path
    #
    my $realDir = "$conf->{identify_real_dir}/quantify-$jobId";
    my $srcDir = $conf->{parent_quantify_id} ? "$conf->{identify_src_dir}/quantify-$conf->{parent_quantify_id}" : $realDir;

    $conf->{protein_file_median} = "$realDir/$conf->{protein_file_name}";
    $conf->{cluster_file_median} = "$realDir/$conf->{cluster_file_name}";
    ($conf->{protein_norm_median} = $conf->{protein_file_median}) =~ s/\.txt$/_normalized.txt/;
    ($conf->{cluster_norm_median} = $conf->{cluster_file_median}) =~ s/\.txt$/_normalized.txt/;
    ($conf->{protein_genome_norm_median} = $conf->{protein_file_median}) =~ s/\.txt$/_genome_normalized.txt/;
    ($conf->{cluster_genome_norm_median} = $conf->{cluster_file_median}) =~ s/\.txt$/_genome_normalized.txt/;

    $conf->{protein_file_mean} = $conf->{protein_file_median} . ".mean";
    $conf->{cluster_file_mean} = $conf->{cluster_file_median} . ".mean";
    $conf->{protein_norm_mean} = $conf->{protein_norm_median} . ".mean";
    $conf->{cluster_norm_mean} = $conf->{cluster_norm_median} . ".mean";
    $conf->{protein_genome_norm_mean} = $conf->{protein_genome_norm_median} . ".mean";
    $conf->{cluster_genome_norm_mean} = $conf->{cluster_genome_norm_median} . ".mean";

    $conf->{ssn_out} = "$realDir/$conf->{ssn_out_name}";
    $conf->{metadata_file} = "$realDir/metadata.tab";

    $conf->{real_dir} = $realDir;
    $conf->{src_dir} = $srcDir;
    $conf->{temp_dir_pat} = "$realDir/quantify-temp";
    
    $conf->{metagenome_ids} = $conf->{metagenome_ids} eq "\@all" ? "*" : [split(m/,/, $conf->{metagenome_ids})];
    $conf->{metagenome_db} = $self->getConfigValue("cgfp.database", $conf->{metagenome_db});

    # Use job arrays instead of a parallel implementation
    $conf->{use_tasks} = 1;

    $self->setupMgInfo($conf);
}


sub setupMgInfo {
    my $self = shift;
    my $conf = shift;

    $conf->{ags_file_path} = "";

    my ($metagenomeInfo, $mgMetadata) = getMetagenomeInfo($conf->{metagenome_db});
    $conf->{mg_info} = $metagenomeInfo;
    $conf->{mg_meta} = $mgMetadata;

    $conf->{metagenome_ids} = [keys %{$metagenomeInfo}] if $conf->{metagenome_ids} eq "*";

    # Get the specific avg genome size file, if present.
    my $agsFileName = "AvgGenomeSize.txt";
    my $mgDbDir = dirname($conf->{metagenome_db});
    if (-f "$mgDbDir/$agsFileName") {
        $conf->{ags_file_path} = "$mgDbDir/$agsFileName";
    }

    # Get the list of result files.  If this is a "child" job then the files already exist.
    my %resFilesMedian;
    my %resFilesMean;
    my %mgFiles;
    foreach my $mgId (@{$conf->{metagenome_ids}}) {
        if (not exists $metagenomeInfo->{$mgId}) {
            warn "Metagenome file does not exists for $mgId.";
            next;
        }
        my $mgFile = $metagenomeInfo->{$mgId}->{file_path};
        my $resFileMedian = "$conf->{src_dir}/$mgId.txt";
        my $resFileMean = "$resFileMedian.mean";
        $mgFiles{$mgId} = $mgFile;
        $resFilesMedian{$mgId} = $resFileMedian;
        $resFilesMean{$mgId} = $resFileMean;
    }

    $conf->{mgFiles} = \%mgFiles;
    $conf->{resFilesMedian} = \%resFilesMedian;
    $conf->{resFilesMean} = \%resFilesMean;
}


sub getUseResults {
    my $self = shift;
    return 1;
}


sub getUsage {
    my $self = shift;

    my $showDevSiteOpts = 0;

    my $usage = <<USAGE;
--ssn-in <PATH_TO_IDENTIFY_SSN_FILE> --ssn-out-name <FILE_NAME> --quantify-dir <DIR_NAME>
    --metagenome-db DB_NAME --metagenome-ids ID_LIST
    [--search-type diamond|blast --ref-db uniprot|uniref50|uniref90 --cdhit-sid]

    --ssn-in            path to input SSN file (relative or absolute)
    --ssn-out-name      what to name the output xgmml file (not a path)
    --quantify-dir      name of the directory to put quantify results in (sub dir of the main output dir)
    --metagenome-db     name of the metagenome database to use (available in the [cgfp.database] section
                        of the efi.conf file)
    --metagenome-ids    comma-separated list of metagenome IDs to use from the database;
                        this can be the value \@all to use all metagenomes in the dataset

    --cdhit-out-name    what to name the output cdhit mapping table file (not a path)

    --min-seq-len       minimum sequence length to use (to exclude fragments from UniRef90 SSNs)
    --max-seq-len       maximim sequence length to use (to exclude sequences from UniRef90 SSNs)
    --search-type       type of search to use (diamond or blast)
    --cdhit-sid         Sequence identity to use for CD-HIT clustering proteins into families for consensus
                        sequence determination; defaults to ShortBRED's default value
    --cons-thresh       Consensus threshold for assigning AA's in the family alignments to the consensus
                        sequences; defaults to ShortBRED's default value
    --ref-db            Which type of reference database to use (uniprot = full UniProt, uniref50 =
                        UniRef50, uniref90 = UniRef90); default uniprot

ADVANCED OPTIONS
    --diamond-sens      The type of DIAMOND sensitivity to use (normal, sensitive, more-sensitive). If not
                        specified, ShortBRED defaults to sensitive.
    --parent-job-id     the ID of the parent job (for using previously-computed markers with a new SSN
USAGE
    return $usage;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{sb};

    push @$info, [metagenome_db => $conf->{"metagenome-db"} // ""];
    push @$info, [metagenome_ids => $conf->{metagenome_ids}];
    push @$info, [quantify_dir => $conf->{quantify_dir}];
    push @$info, [protein_file_name => $conf->{protein_file_name}];
    push @$info, [cluster_file_name => $conf->{cluster_file_name}];
    push @$info, [parent_quantify_id => $conf->{parent_quantify_id}];
    push @$info, [search_type => $conf->{search_type}];

    return $info;
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{sb};
    
    mkdir $conf->{real_dir} if not -d $conf->{real_dir};

    my @jobs;
    my $B;
    my $job;

    my $job1;
    if (not $conf->{parent_quantify_id}) {
        $job1 = $self->getQuantifyJob();
        push @jobs, {job => $job1, deps => [], name => "quantify"};
    }

    my $job2Deps = $job1 ? [$job1] : [];
    my $job2 = $self->getMergeQuantifyJob();
    push @jobs, {job => $job2, deps => $job2Deps, name => "merge_quantify"};

    my $job3 = $self->getXgmmlJob();
    push @jobs, {job => $job3, deps => [$job2], name => "make_quantify_xgmml"};

    return @jobs;
}


sub getQuantifyJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};

    # Path to generic EFITools scripts
    my $toolPath = $self->getToolPath();

    #######################################################################################################################
    # Run ShortBRED-Quantify on the markers
    #
    # Don't run this if we are creating SSNs from another job's results.
    
    my $B = $self->getBuilder();
    $self->addStandardEnv($B);

    if ($conf->{use_tasks}) {
        $self->getQuantifyTasks($conf, $B);
    } else {
        $self->getQuantifyParallel($conf, $B);
    }

    return $B;
}


sub getQuantifyParallel {
    my $self = shift;
    my $conf = shift;
    my $B = shift;

    my $np = $self->getNodeNp();
    my $sbAppRepo = $self->getShortBREDRepo();
    my $sbQuantifyApp = "$sbAppRepo/shortbred_quantify.py";
    
    my $searchTypeArgs = $conf->{search_type} ? "--search_program $conf->{search_type}" : "";

    $self->requestResourcesByName($B, 1, $np, "sb_quantify_par");

    foreach my $mgId (@{$conf->{metagenome_ids}}) {
        my $mgFile = $conf->{mgFiles}->{$mgId};
        my $resFileMedian = $conf->{resFilesMedian}->{$mgId};
        my $resFileMean = $conf->{resFilesMean}->{$mgId};
        $B->addAction("python $sbQuantifyApp --threads $np $searchTypeArgs --markers $conf->{sb_marker_file} --wgs $mgFile --results $resFileMedian --results-mean $resFileMean --tmp $conf->{temp_dir_pat}-$mgId");
    }
}


sub getQuantifyTasks {
    my $self = shift;
    my $conf = shift;
    my $B = shift;

    my $np = $self->getNodeNp();
    my $sbAppRepo = $self->getShortBREDRepo();
    my $sbQuantifyApp = "$sbAppRepo/shortbred_quantify.py";

    my $searchTypeArgs = $conf->{search_type} ? "--search_program $conf->{search_type}" : "";

    my $numMg = scalar @{$conf->{metagenome_ids}};
    my $numFiles = $numMg < $np ? 1 : int($numMg / $np + 1);
    my $maxTask = $numMg >= $np ? $np : $numMg;
    if ($maxTask == $np) {
        my $excessTask = int(($numFiles * $np - $numMg) / $numFiles);
        $maxTask = $maxTask - $excessTask;
    }

    my $tmpMarker = "$conf->{real_dir}/markers.faa.{JOB_ARRAYID}";

    my $removeTemp = $self->getRemoveTemp();

    $B->jobArray("1-$maxTask");
    $self->requestResourcesByName($B, 1, 1, "sb_quantify_tasks");

    my $c = 0;
    foreach my $mgId (@{$conf->{metagenome_ids}}) {
        my $mgFile = $conf->{mgFiles}->{$mgId};
        my $resFileMedian = $conf->{resFilesMedian}->{$mgId};
        my $resFileMean = $conf->{resFilesMean}->{$mgId};
        if ($c % $numFiles == 0) {
            my $aid = int($c / $numFiles) + 1;
            if ($c > 0) {
                $B->addAction("    rm $tmpMarker");
                $B->addAction("fi");
            }
            $B->addAction("if [ {JOB_ARRAYID} == $aid ]; then");
            $B->addAction("    cp $conf->{sb_marker_file} $tmpMarker"); # Copy to possibly help performance out.
        }
        my $tempDir = "$conf->{temp_dir_pat}-$mgId";
        $B->addAction("    python $sbQuantifyApp $searchTypeArgs --markers $tmpMarker --wgs $mgFile --results $resFileMedian --results-mean $resFileMean --tmp $tempDir");
        $B->addAction("    rm -rf $tempDir") if $removeTemp;
        $c++;
    }
    if ($c > 1) {
        $B->addAction("    rm $tmpMarker");
        $B->addAction("fi");
    }
}


sub getMergeQuantifyJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};

    my $localMergeApp = "$conf->{tool_path}/merge_shortbred.py";

    #######################################################################################################################
    # Merge quantify outputs into one table.
    
    my $mgSortFn = makeMgSortFn($conf);

    # Sort the metagenome IDs according to a body site
    my @sortedMgIds = sort $mgSortFn @{$conf->{metagenome_ids}};
    
    my $resFileMedianList = join(" ", map { $conf->{resFilesMedian}->{$_} } @sortedMgIds);
    my $resFileMeanList = join(" ", map { $conf->{resFilesMean}->{$_} } @sortedMgIds);
    
    my $B = $self->getBuilder();
    $self->requestResourcesByName($B, 1, 1, "sb_merge");
    $self->addStandardEnv($B);

    $B->addAction("python $localMergeApp $resFileMedianList -C $conf->{cluster_file_median} -p $conf->{protein_file_median} -c $conf->{ssn_cluster_file}");
    $B->addAction("python $localMergeApp $resFileMedianList -C $conf->{cluster_norm_median} -p $conf->{protein_norm_median} -c $conf->{ssn_cluster_file} -n");
    if ($conf->{ags_file_path}) {
        $B->addAction("python $localMergeApp $resFileMedianList -C $conf->{cluster_genome_norm_median} -p $conf->{protein_genome_norm_median} -c $conf->{ssn_cluster_file} -g $conf->{ags_file_path}");
    }
    $B->addAction("python $localMergeApp $resFileMeanList -C $conf->{cluster_file_mean} -p $conf->{protein_file_mean} -c $conf->{ssn_cluster_file}");
    $B->addAction("python $localMergeApp $resFileMeanList -C $conf->{cluster_norm_mean} -p $conf->{protein_norm_mean} -c $conf->{ssn_cluster_file} -n");
    if ($conf->{ags_file_path}) {
        $B->addAction("python $localMergeApp $resFileMeanList -C $conf->{cluster_genome_norm_mean} -p $conf->{protein_genome_norm_mean} -c $conf->{ssn_cluster_file} -g $conf->{ags_file_path}");
    }

    if ($self->getRemoveTemp()) {
        $B->addAction("rm $resFileMedianList");
        $B->addAction("rm $resFileMeanList");
    }

    return $B;
}


sub getXgmmlJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};

    my $metagenomeIdList = join(",", @{$conf->{metagenome_ids}});

    #######################################################################################################################
    # Build the XGMML file with the marker attributes and the abundances added added
    
    my $B = $self->getBuilder();
    $B->setScriptAbortOnError(0); # Disable abort on error, so that we can disable the merged output lock.
    $self->requestResourcesByName($B, 1, 1, "sb_xgmml");
    $self->addStandardEnv($B);

    $B->addAction("MGIDS=\"$metagenomeIdList\"");
    $B->addAction("MGDB=\"$conf->{metagenome_db}\"");
    
    $B->addAction("$conf->{tool_path}/make_ssn.pl --ssn-in $conf->{ssn_in} --ssn-out $conf->{ssn_out} --protein-file $conf->{protein_genome_norm_median} --cluster-file $conf->{cluster_genome_norm_median} --cdhit-file $conf->{cdhit_table_file} --quantify --metagenome-db \$MGDB --metagenome-ids \$MGIDS");
    $B->addAction("OUT=\$?");
    $B->addAction("if [ \$OUT -ne 0 ]; then");
    $B->addAction("    echo \"make SSN failed.\"");
    $B->addAction("    echo \$OUT > $conf->{real_dir}/ssn.failed");
    $B->addAction("    exit 621");
    $B->addAction("fi");
    $B->addAction("zip -j $conf->{ssn_out}.zip $conf->{ssn_out}");
    $B->addAction("$conf->{tool_path}/create_quantify_metadata.pl --protein-abundance $conf->{protein_file_median} --metadata $conf->{metadata_file}");
    $B->addAction("touch $conf->{real_dir}/$self->{completed_name}");

    return $B;
}


sub makeMgSortFn {
    my $conf = shift;

    my $fn = sub {
        my $ag = $conf->{mg_info}->{$a}->{gender};
        my $bg = $conf->{mg_info}->{$b}->{gender};
        my $ab = $conf->{mg_info}->{$a}->{bodysite};
        my $bb = $conf->{mg_info}->{$b}->{bodysite};
        my $ao = exists $conf->{mg_meta}->{$ab} ? $conf->{mg_meta}->{$ab}->{order} : 0;
        my $bo = exists $conf->{mg_meta}->{$bb} ? $conf->{mg_meta}->{$bb}->{order} : 0;
    
        # Compare by order
        my $ocmp = $ao cmp $bo;
        return $ocmp if $ocmp;
    
        # Compare by body site
        my $bscmp = $ab cmp $bb;
        return $bscmp if $bscmp;
    
        # Compare by gender
        my $gcmp = $ag cmp $bg;
        return $gcmp if $gcmp;
    
        return $a cmp $b;
    };

    return $fn;
}


1;

