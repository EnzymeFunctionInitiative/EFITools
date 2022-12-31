
package EFI::JobManager;

use strict;
use warnings;

use JSON;
use Capture::Tiny qw(capture);
use File::Copy;
use Data::Dumper;


my $STATUS_TABLE = "job_info";
my $STATUS_COL = "job_info_status";
my $JOB_ID_COL = "job_info_id";
my $TYPE_COL = "job_info_type";
my $SLURM_ID_COL = "job_info_job_id";
my $MSG_COL = "job_info_msg";
my $UPDATE_TIME_COL = "job_info_time_updated";

my $S_RUNNING = "RUNNING";
my $S_NEW = "NEW";
my $S_FINISH = "FINISH";
my $S_ERROR = "FAILED";


use EFI::JobManager::Types;

use constant D_FINISH => 1;
use constant D_SHOW_NEW => 2;
use constant D_CREATE_NEW => 3;

use Exporter qw(import);
our @EXPORT = qw(D_FINISH D_SHOW_NEW D_CREATE_NEW);



sub new {
    my $class = shift;
    my %args = @_;

    my $generateInfo = new EFI::JobManager::Info(config => $args{config}, table => TYPE_GENERATE, dbh => $args{dbh});
    my $analysisInfo = new EFI::JobManager::Info(config => $args{config}, table => TYPE_ANALYSIS, dbh => $args{dbh});
    my $gnnInfo = new EFI::JobManager::Info(config => $args{config}, table => TYPE_GNN, dbh => $args{dbh});
    my $gndInfo = new EFI::JobManager::Info(config => $args{config}, table => TYPE_GND, dbh => $args{dbh});
    #my $cgfpIdInfo = new EFI::JobManager::Info(config => $args{config}, table => "cgfp_identify", dbh => $args{dbh});
    #my $cgfpQInfo = new EFI::JobManager::Info(config => $args{config}, table => "cgfp_quantify", dbh => $args{dbh});

    my $self = {
        debug => $args{debug},
        dbh => $args{dbh},
        config => $args{config}, 
        info => {
            &TYPE_GENERATE => $generateInfo,
            &TYPE_ANALYSIS => $analysisInfo,
            &TYPE_GNN => $gnnInfo,
            &TYPE_GND => $gndInfo,
            #cgfp_id => $cgfpIdInfo,
            #cgfp_q => $cgfpQInfo,
        },
    };
    bless $self, $class;

    return $self;
}


sub checkForJobFinish {
    my $self = shift;
    $self->checkForFinish($self->{info}->{&TYPE_GENERATE});
    $self->checkForFinish($self->{info}->{&TYPE_ANALYSIS});
    $self->checkForFinish($self->{info}->{&TYPE_GNN});
    $self->checkForFinish($self->{info}->{&TYPE_GND});
}


sub checkForFinish {
    my $self = shift;
    my $jobTypeInfo = shift;
    my $dbh = $self->{dbh};

    my $tableName = $jobTypeInfo->getTableName();
    my $jobType = $jobTypeInfo->getType();

    $self->log("Checking for job completion for $jobType");

    my $sql = "SELECT * FROM $STATUS_TABLE WHERE $STATUS_COL = '$S_RUNNING' AND $TYPE_COL = ?";

    my $sth = $dbh->prepare($sql);
    $sth->execute($jobType);

    while (my $row = $sth->fetchrow_hashref) {
        my $slurmId = $row->{$SLURM_ID_COL};
        my $jobId = $row->{$JOB_ID_COL};
        my $finishFile = $jobTypeInfo->getFinishFile($jobId);

        $self->log("\t$slurmId, $jobId, $finishFile");
        next if $self->isJobRunning($slurmId);

        $self->log("\tJob has stopped running $finishFile");

        my $jobStatus = -f $finishFile ? $S_FINISH : $S_ERROR;

        $self->log("\tJob state: $jobStatus");

        $self->setDbStatusVal($jobId, $tableName, undef, $jobStatus, undef);
    }
}


sub isJobRunning {
    my $self = shift;
    my $slurmId = shift;

    my @args = ("/usr/bin/squeue", "-h", "-o", "%A,%j,%t,%N,%M,%P", "-p", $self->{config}->{queue}.",".$self->{config}->{mem_queue});
    #$self->log("\t" . join(" ", @args));
    my ($output, $error) = capture {
        system(@args);
    };
    die "Can't run " . join(" ", @args) . " : $error" if $error;
    my @res = split(m/\n/s, $output);
    if (grep(m/^$slurmId,/, @res)) {
        return 1;
    } else {
        return 0;
    }
}


sub processNewJobs {
    my $self = shift;
    my $dbh = $self->{dbh};

    # Debug level == finish means we only check if the jobs have finished
    return if ($self->{debug} and $self->{debug} < D_SHOW_NEW);

    #my @tables = (TYPE_GENERATE, TYPE_ANALYSIS, TYPE_GNN, TYPE_GND);

    #foreach my $table (@tables) {
    {
        my $sql = "SELECT * FROM job_info WHERE job_info_status = '$S_NEW'";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        while (my $row = $sth->fetchrow_hashref) {
            my $jobId = $row->{job_info_id};
            my $jobType = $row->{job_info_type};
            my $typeCol = "${jobType}_type";
            my $jobTable = $jobType;
            my $idCol = "${jobType}_id";

            $self->log("Processing $jobId / $jobType");

            ## Now we need to check if it's already running, failed, or been run.  It will exist in the
            ## job_info table in some form or another if that's the case.
            #my $c_sql = "SELECT * FROM job_info WHERE job_info_type = '$jobTable' AND job_info_id = ?";
            #my $c_sth = $dbh->prepare($c_sql);
            #$c_sth->execute($jobId);
            #my $c_row = $c_sth->fetchrow_hashref;
            #next if $c_row;

            my $tSql = $self->getJobTableQuerySql($jobType, $jobTable, $idCol);
            my $sth = $self->{dbh}->prepare($tSql);
            $sth->execute($jobId);
            my $row = $sth->fetchrow_hashref;
            die "Invalid ID for $jobTable / $jobId" if not $row;

            my $info = $self->getJobParameters($jobId, $jobTable, $row);
            warn "Unable to process job $jobId in $jobTable" and next if not $info;

            $self->log(showNewDebug($info)) if $self->{debug} >= D_SHOW_NEW;
            next if $self->{debug} == D_SHOW_NEW;

            if (not -d $info->{job_dir}) {
                mkdir $info->{job_dir} or warn "Unable to make dir $info->{job_dir}: $!; continuing";
            }

            #if ($info->{source_file} and $info->{target_file}) {
            #    copy($info->{source_file}, $info->{target_file});
            #}

            my $mainScript = $info->{script};

            my $startScript = $info->{job_dir} . "/startup_$jobId.sh";
            open my $fh, ">", $startScript;
            if (not $fh) {
                $self->setDbError($jobId, $jobTable, 0, $S_ERROR, $!);
                warn "Unable to write to startup script $startScript: $!";
                next;
            }

            $fh->print($info->{env}, "\n");
            $fh->print("cd $info->{job_dir}\n");
            $fh->print(join(" ", $mainScript, @{ $info->{args} }), "\n");
            close $fh;

            print "\t/bin/bash $startScript\n" if $self->{debug} >= D_CREATE_NEW;
            next if $self->{debug} == D_CREATE_NEW;

            my ($output, $error) = capture {
                system("/bin/bash", $startScript);
            };

            $self->updateDatabases($jobId, $jobTable, $output, $error);
        }
    }
}


sub updateDatabases {
    my $self = shift;
    my $jobId = shift;
    my $table = shift;
    my $output = shift;
    my $error = shift;

    my $slurmId = 0;
    my $msg = "";
    my $status = $S_ERROR;
    if ($output and not $error) {
        $slurmId = $self->{info}->{$table}->parseForSlurmId($output);
        $msg = $error ? "JOB STARTUP ERROR: $error" : "";
        $status = $slurmId ? $S_RUNNING : $S_ERROR;
    }

    $self->setDbStatusVal($jobId, $table, $slurmId, $status, $error);
}


sub setDbStatusVal {
    my $self = shift;
    my $jobId = shift;
    my $table = shift;
    my $slurmId = shift;
    my $status = shift;
    my $msg = shift;
    my $dbh = $self->{dbh};

    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    $mon += 1;
    $year += 1900;
    my $updateTime = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec);

    my %updates;
    $updates{$SLURM_ID_COL} = $slurmId if defined $slurmId;
    $updates{$STATUS_COL} = $status if $status;
    $updates{$MSG_COL} = $msg // "";

    my @updateKeys = keys %updates;
    my $sets = join(", ", map { "$_ = ?" } @updateKeys);
    $sets .= ($sets ? ", " : "") . "$UPDATE_TIME_COL = ?";

    my @vals = map { $updates{$_} } @updateKeys;
    push @vals, $updateTime;
    my $sql = "UPDATE $STATUS_TABLE SET $sets WHERE $JOB_ID_COL = ? AND $TYPE_COL = ?";
    $self->log("    Update $jobId/$table with " . join(", ", map { "$_=$updates{$_}" } @updateKeys));
    $dbh->do($sql, undef, @vals, $jobId, $table);
}


sub showNewDebug {
    my $info = shift;
    my $args = join(" ", @{ $info->{args} });
    my $env = join(" && ", split(m/\n/s, $info->{env}));
    my $subType = $info->{sub_type} ? $info->{sub_type} : ""; 
    my $debug = "\ttype => $info->{type}/$subType, job_id => $info->{job_id}, results_dir => $info->{results_dir}, job_dir = $info->{job_dir}, env => $env\n";
    $debug .= "\t$info->{script} $args\n";
    return $debug;
}


sub makeArgs {
    my $self = shift;
    my $jobId = shift;
    my $type = shift;
    my $row = shift;
    my $info = shift;

    my $numProcessors = 64;
    my $evalue = 5; # TODO
    my $maxSeq = 100000000;
    my $defaultMaxBlastSeq = 1000; # TODO

    my $jobDir = $self->{info}->{$type}->getJobDir($jobId);

    my @args;

    if ($type eq TYPE_GENERATE) {
        my $parms = decode_json($row->{generate_params});

        my $subType = $row->{generate_type};
        $info->{sub_type} = $subType;
        push @args, "--queue", $self->{config}->{queue};
        push @args, "--memqueue", $self->{config}->{mem_queue};

        if ($subType eq TYPE_COLORSSN or $subType eq TYPE_CLUSTER or $subType eq TYPE_CONVRATIO or $subType eq TYPE_NBCONN) {
            my $sourceFile = $self->getUploadFile($type, $jobId);
            $info->{source_file} = $sourceFile->{file_path};
            #my $targetName = "$jobId.$sourceFile->{ext}";
            #$info->{target_file} = "$jobDir/$targetName";

            warn "Unable to generate $subType job because upload file doesn't exist" and next if not $sourceFile;
            push @args, "--ssn-in", $info->{source_file};
            #push @args, "--ssn-in", $info->{target_file};
            push @args, "--ssn-out", "ssn.xgmml";
            push @args, "--large-mem", "--extra-ram", $parms->{extra_ram} if $parms->{extra_ram};

            if ($subType eq TYPE_COLORSSN) {
                push @args, "--skip-fasta" if $parms->{skip_fasta};
            } elsif ($subType eq TYPE_CONVRATIO) {
                push @args, "--ascore", $parms->{ascore} if $parms->{ascore};
            } elsif ($subType eq TYPE_CLUSTER and $parms->{make_hmm}) {
                push @args, "--opt-msa-option", $parms->{make_hmm};
                if ($parms->{make_hmm} =~ m/CR/) {
                    push @args, "--opt-aa-list", $parms->{hmm_aa} if $parms->{hmm_aa};
                    push @args, "--opt-aa-threshold", $parms->{aa_threshold} if $parms->{aa_threshold};
                }
                if ($parms->{make_hmm} =~ m/(CR|HMM|WEBLOGO)/) {
                    push @args, "--opt-min-seq-msa", $parms->{min_seq_msa} if $parms->{min_seq_msa};
                    push @args, "--opt-max-seq-msa", $parms->{max_seq_msa} if $parms->{max_seq_msa};
                }
            } elsif ($subType eq TYPE_NBCONN) {
            }

            # Shared
            push @args, "--map-dir-name", "'cluster-data'";
            push @args, "--map-file-name", "mapping_table.txt",
            push @args, "--domain-map-file-name", "mapping_table_domain.txt";
            push @args, "--stats", "stats.txt";
            push @args, "--cluster-sizes", "cluster_sizes.txt";
            push @args, "--conv-ratio", "conv_ratio.txt";
            push @args, "--sp-clusters-desc", "swissprot_clusters_desc.txt";
            push @args, "--sp-singletons-desc", "swissprot_singletons_desc.txt";

        } else {
            push @args, ("--old-graphs", "--max-full-family", 1000000);

            print "$subType $jobId\n";
            push @args, "--np", $numProcessors;

            push @args, "--sim", $parms->{generate_sequence_identity} if $parms->{generate_sequence_identity};
            push @args, "--lengthdif", $parms->{generate_length_overlap} if $parms->{generate_length_overlap};
            push @args, "--uniref-version", $parms->{generate_uniref} if $parms->{generate_uniref};
            push @args, "--no-demux", $parms->{generate_no_demux} if $parms->{generate_no_demux};
            push @args, "--fraction", $parms->{generate_fraction} if $parms->{generate_fraction};
            push @args, "--evalue", $parms->{generate_evalue} if $parms->{generate_evalue};
            push @args, "--min-seq-len", $parms->{generate_min_seq_len} if $parms->{generate_min_seq_len};
            push @args, "--max-seq-len", $parms->{generate_max_seq_len} if $parms->{generate_max_seq_len};
            push @args, "--exclude-fragments" if $parms->{exclude_fragments};
            push @args, "--tax-search", "'$parms->{tax_search}'" if $parms->{tax_search};
            push @args, "--family-filter", $parms->{family_filter} if $parms->{family_filter};
            push @args, getDomainArgs($parms);
            push @args, getFamilyArgs($parms);
            push @args, "--maxsequence", $maxSeq;
            push @args, "--seq-count-file", "acc_counts.txt";

            #if ($subType eq TYPE_TAXONOMY) {
            if ($row->{generate_is_tax_job}) {
                push @args, "--tax-search-only", "--use-fasta-headers";
            }
            if ($subType eq TYPE_ACCESSION) {
                push @args, "--no-match-file", "no_accession_matches.txt";
                my $targetName = "";
                #TODO add domain
                if ($parms->{tax_job_id}) {
                    my $taxJobId = $parms->{tax_job_id};
                    my $taxTreeId = $parms->{tax_tree_id};
                    my $taxIdType = $parms->{tax_id_type};
                    my $sourceFile = $self->resultsFileExists($type, TYPE_TAXONOMY, $taxJobId);
                    if ($sourceFile) {
                        push @args, "--source-tax", join(",", $taxJobId, $taxTreeId, $taxIdType);
                        $targetName = $sourceFile; # the file that is input into create_generate_job.pl
                    }
                }
                if (not $parms->{tax_job_id}) {
                    my $sourceFile = $self->getUploadFile($type, $jobId);
                    warn "Unable to generate $subType job because upload file doesn't exist" and next if not $sourceFile;
                    #$targetName = "$jobId.$sourceFile->{ext}";
                    #$info->{source_file} = $sourceFile->{file_path};
                    $targetName = $sourceFile->{file_path};
                    #$info->{target_file} = "$jobDir/$targetName";
                }
                push @args, "--useraccession", $targetName;
            } elsif ($subType eq TYPE_FASTA or $subType eq TYPE_FASTA_ID) {
                if ($subType eq TYPE_FASTA_ID) {
                    push @args, "--use-fasta-headers";
                }
                my $sourceFile = $self->getUploadFile($type, $jobId);
                warn "Unable to generate $subType job because upload file doesn't exist" and next if not $sourceFile;
                #$info->{source_file} = $sourceFile->{file_path};
                #my $targetName = "$jobId.$sourceFile->{ext}";
                #$info->{target_file} = "$jobDir/$targetName";
                #push @args, "--userfasta", $targetName;
                push @args, "--userfasta", $sourceFile->{file_path};
            } elsif ($subType eq TYPE_FAMILIES) {
            } elsif ($subType eq TYPE_BLAST) {
                push @args, "--seq", $parms->{generate_blast};
                push @args, "--blast-evalue", $parms->{generate_blast_evalue};
                push @args, "--db-type", $parms->{blast_db_type} if $parms->{blast_db_type};
                push @args, "--nresults", ($parms->{generate_blast_max_sequence} ? $parms->{generate_blast_max_sequence} : $defaultMaxBlastSeq);
            }
        }
    } elsif ($type eq TYPE_ANALYSIS) {
        push @args, "--minlen", $row->{analysis_min_length};
        push @args, "--maxlen", $row->{analysis_max_length};
        push @args, "--minval", $row->{analysis_evalue};
        push @args, "--filter", $row->{analysis_filter};
        push @args, "--title", "'" . $row->{analysis_name} . "'";
        push @args, "--maxfull", $maxSeq;

        # Comes from generate job
        my $genParms = decode_json($row->{generate_params});
        my $unirefVersion = getUniRefVersion($genParms);
        push @args, "--uniref-version", $unirefVersion if $unirefVersion;

        # Comes from generate job
        # If job type is FASTA or FASTA_ID
        if ($row->{generate_type} eq TYPE_FASTA or $row->{generate_type} eq TYPE_FASTA_ID) {
            push @args, "--include-sequences";
            if ($genParms->{include_all_seq}) { # Comes from generate job
                push @args, "--include-all-sequences";
            }
        }

        my $parms = decode_json($row->{analysis_params});
        push @args, "--use-anno_spec" if $parms->{use_min_node_attr};
        push @args, "--use-min-edge-attr" if $parms->{use_min_edge_attr};
        push @args, "--compute-nc" if $parms->{compute_nc};
        push @args, "--no-repnode" if not $parms->{build_repnode};
        push @args, "--remove-fragments" if $parms->{remove_fragments};

        if ($parms->{tax_search}) {
            push @args, "--tax-search", "\"" . $parms->{tax_search} . "\"";
            push @args, "--tax-search-hash", $parms->{tax_search_hash};
        }
    } elsif ($type eq TYPE_GND) {
        push @args, "--queue", $self->{config}->{mem_queue};

    } elsif ($type eq TYPE_GNN) {
        my $parms = decode_json($row->{generate_params});
        push @args, "--queue", $self->{config}->{mem_queue};
        my $sourceFile = $self->getUploadFile($type, $jobId);
        warn "Unable to process $type job because upload file doesn't exist" and next if not $sourceFile;
        $info->{source_file} = $sourceFile->{file_path};
        push @args, "--ssn-in", $info->{source_file};

        push @args, "--nb-size", $parms->{neighborhood_size};
        push @args, "--cooc", $parms->{cooccurrence};
        push @args, "--gnn", "ssn_cluster_gnn.zip";
        push @args, "--ssnout", "coloredssn.zip";
        push @args, "--stats", "stats.txt";
        push @args, "--cluster-sizes", "cluster_sizes.txt";
        push @args, "--sp-clusters-desc", "swissprot_clusters_desc.txt";
        push @args, "--sp-singletons-desc", "swissprot_singletons_desc.txt";
        push @args, "--warning-file", "nomatches_noneighbors.txt";
        push @args, "--pfam", "pfam_family_gnn.zip";
        push @args, "--id-out", "mapping_table.txt";
        push @args, "--id-out-domain", "domain_mapping_table.txt";
        push @args, "--extra-ram" if $parms->{extra_ram};
 
        push @args, "--pfam-zip", "pfam_mapping.zip";
        push @args, "--all-pfam-zip", "all_pfam_mapping.zip";
        push @args, "--split-pfam-zip", "split_pfam_mapping.zip";
        push @args, "--all-split-pfam-zip", "all_split_pfam_mapping.zip";
        push @args, "--uniprot-id-zip", "UniProt_IDs.zip";
        push @args, "--uniprot-domain-id-zip", "UniProt_Domain_IDs.zip";
        push @args, "--uniref50-id-zip", "UniRef50_IDs.zip";
        push @args, "--uniref50-domain-id-zip", "UniRef50_Domain_IDs.zip";
        push @args, "--uniref90-id-zip", "UniRef90_IDs.zip";
        push @args, "--uniref90-domain-id-zip", "UniRef90_Domain_IDs.zip";
        push @args, "--none-zip", "nomatches_noneighbors.txt";
        push @args, "--fasta-zip", "FASTA.zip";
        push @args, "--fasta-domain-zip", "FASTA_Domain.zip";
        push @args, "--fasta-uniref90-zip", "FASTA_UniRef90.zip";
        push @args, "--fasta-uniref90-domain-zip", "FASTA_Domain_UniRef90.zip";
        push @args, "--fasta-uniref50-zip", "FASTA_UniRef50.zip";
        push @args, "--fasta-uniref50-domain-zip", "FASTA_Domain_UniRef50.zip";
        push @args, "--arrow-file", "arrow_data.zip";
        push @args, "--cooc-table", "cooc_table.txt";
        push @args, "--hub-count-file", "hub_count.txt";
    }

    return @args;
}


sub getUniRefVersion {
    my $parms = shift;

    my $uniref = 0;
    if ($parms->{generate_uniref}) {
        $uniref = $parms->{generate_uniref};
    } elsif ($parms->{blast_db_type} and $parms->{blast_db_type} =~ m/^uniref(.+)$/) {
        $uniref = $1;
    }

    return $uniref;
}


sub getDomainArgs {
    my $parms = shift;

    my @args;
    if ($parms->{generate_domain}) {
        push @args, $parms->{generate_domain};
        push @args, $parms->{generate_domain_region} if $parms->{generate_domain_region};
    }

    return @args;
}


sub getFamilyArgs {
    my $parms = shift;

    return if not $parms->{generate_families};

    my @fams = split(m/,/, $parms->{generate_families});

    my $pfams = join(",", grep {m/^(PF|CL)/i} @fams);
    my $ipros = join(",", grep {m/^(IP)/i} @fams);

    my @args;
    push @args, "--pfam", $pfams if $pfams;
    push @args, "--ipro", $ipros if $ipros;

    return @args;
}


sub getUploadFile {
    my $self = shift;
    my $type = shift;
    my $jobId = shift;

    my $tableName = $self->{info}->{$type}->getTableName();

    my $sql = "SELECT ${tableName}_params AS parms FROM $tableName WHERE ${tableName}_id = ?";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($jobId);
    my $row = $sth->fetchrow_hashref;

    #TODO
    return undef if not $row;

    my $parms = $row->{parms};

    my $fileInfo = $self->{info}->{$type}->getUploadedFilename($jobId, $parms);
    return undef if not $fileInfo;

    my $uploadsDir = $self->{info}->{$type}->getUploadsDir();

    return {file_path => "$uploadsDir/$fileInfo->{file}", ext => $fileInfo->{ext}};
}


sub resultsFileExists {
    my $self = shift;
    my $type = shift;
    my $subType = shift;
    my $jobId = shift;

    my $outputPath = $self->getResultsOutputPath($type, $jobId);

    if ($subType eq TYPE_TAXONOMY) {
        $outputPath .= "/tax.json";
    }

    return -f $outputPath ? $outputPath : "";
}


sub getResultsOutputPath {
    my $self = shift;
    my $type = shift;
    my $jobId = shift;
    my $resultsName = $self->{info}->{$type}->getResultsDirName($jobId);
    my $outputPath = $self->{info}->{$type}->getJobDir($jobId);
    $outputPath .= "/$resultsName";
    return $outputPath;
}


sub getJobParameters {
    my $self = shift;
    my $jobId = shift;
    my $type = shift;
    my $row = shift;

    my $info = {type => $type};
    $info->{env} = $self->getEnv($type);

    my $outputPath = "";;
    my $argJobId = $jobId;
    #    if ($type eq TYPE_ANALYSIS) {
    #        $outputPath = $self->{info}->{&TYPE_GENERATE}->getJobDir($row->{analysis_generate_id});
    #        $argJobId = $row->{analysis_generate_id};
    #    } else {
        $outputPath = $self->{info}->{$type}->getJobDir($jobId);
    #}

    $info->{job_id} = $jobId;
    $info->{job_dir} = $outputPath;
    $info->{script} = $self->getScript($type, $row);
    $info->{results_dir} = $self->{info}->{$type}->getResultsDirName($jobId);
    my $tmpDir = $self->{info}->{$type}->getTmpDirName();

    my @globalArgs = ("--scheduler", "slurm", "--job-id", $argJobId, "--remove-temp", "--output-path", $outputPath, "--output-dir", $outputPath, "--tmp", $tmpDir, "--out-dir", $info->{results_dir});

    my @args = $self->makeArgs($jobId, $type, $row, $info);

    $info->{args} = [@globalArgs, @args];

    return $info;
}


sub getJobTableQuerySql {
    my $self = shift;
    my $jobType = shift;
    my $jobTable = shift;
    my $idCol = shift;

    my $sql = "SELECT * FROM $jobTable WHERE $idCol = ?";
    if ($jobType eq TYPE_ANALYSIS) {
        $sql = "SELECT * FROM analysis LEFT JOIN generate ON analysis.analysis_generate_id = generate.generate_id WHERE analysis_id = ?";
    }

    return $sql;
}


sub getScript {
    my $self = shift;
    my $type = shift;
    my $row = shift;

    #TODO: fix hard coded

    my $genJob = "create_generate_job.pl";
    my $ssnJob = "make_colorssn_job.pl";

    my %mapping = (
        &TYPE_ACCESSION => $genJob,
        &TYPE_BLAST => "create_blast_job.pl",
        &TYPE_CLUSTER => $ssnJob,
        &TYPE_COLORSSN => $ssnJob,
        &TYPE_FAMILIES => $genJob,
        &TYPE_FASTA => $genJob,
        &TYPE_FASTA_ID => $genJob,
        &TYPE_CONVRATIO => "create_cluster_conv_ratio_job.pl",
        &TYPE_NBCONN => "create_nb_conn_job.pl",
        &TYPE_TAXONOMY => $genJob,
        &TYPE_GNN => "submit_gnn.pl",
        &TYPE_GND => "submit_diagram.pl",
        &TYPE_ANALYSIS => "create_analysis_job.pl",
    );

    my $script = "";

    if ($type eq TYPE_GENERATE) {
        my $subType = $row->{"generate_type"} // TYPE_FAMILIES;
        $script = $mapping{$subType};
    } elsif ($type eq TYPE_ANALYSIS) {
        return $mapping{$type};
    } elsif ($type eq TYPE_GNN) {
        return $mapping{$type};
    } elsif ($type eq TYPE_GND) {
        return $mapping{$type};
    }

    return $script;
}


sub getEnv {
    my $self = shift;
    my $type = shift;

    my @env;
    if (exists $self->{config}->{"$type.env"} and scalar @{ $self->{config}->{"$type.env"} }) {
        push @env, @{ $self->{config}->{"$type.env"} };
    }

    my $envStr = join("\n", @env) . "\n";
    return $envStr;
}


sub log {
    my $self = shift;
    my @msg = @_;
    map { print $_, "\n"; } @msg if $self->{debug};
}


1;

