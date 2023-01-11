
package EFI::JobManager::Info;

use strict;
use warnings;

use JSON;

use EFI::JobManager::Types;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {info => createInfo($args{table}, $args{config}), dbh => $args{dbh}};
    bless $self, $class;

    return $self;
}


sub getTableName {
    my $self = shift;
    return $self->{info}->{table_name};
}


sub getType() {
    my $self = shift;
    return $self->{info}->{type};
}


sub getFinishFile {
    my $self = shift;
    my $jobId = shift;
    my $jobDir = $self->getJobDir($jobId);
    my $suffix = $self->getResultsDirName($jobId, 1);
    my $resultsDir = "$jobDir/$suffix";
    my $finishFile = "$resultsDir/$self->{info}->{finish_file}";
    return $finishFile;
}


sub getJobDir {
    my $self = shift;
    my $jobId = shift;
    my $baseDir = $self->{info}->{base_dir};
    if ($self->{info}->{type} eq TYPE_ANALYSIS) {
        my $sql = "SELECT * FROM analysis WHERE analysis_id = ?";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($jobId);
        my $dbRow = $sth->fetchrow_hashref;
        $jobId = $dbRow->{analysis_generate_id};
    }
    my $resultsDir = "$baseDir/$jobId";
    return $resultsDir;
}


sub getTmpDirName {
    my $self = shift;
    my $dirName = $self->{info}->{results_dir_name};
    return $dirName;
}


sub getResultsDirName {
    my $self = shift;
    my $jobId = shift;
    my $expandIfAnalysis = shift || 0;

    my $dirName = $self->{info}->{results_dir_name};
    if ($self->{info}->{type} eq TYPE_ANALYSIS and $expandIfAnalysis) {
        my $aDir = getAnalysisDirName($self->{dbh}, $jobId);
        $dirName .= "/$aDir";
    }

    return $dirName;
}


sub getAnalysisDirName {
    my $dbh = shift;
    my $aid = shift;
    my ($dbRow, $params) = getAnalysisParams($dbh, $aid); 
    my $aDir = makeAnalysisDirName($dbRow, $params);
    return $aDir;
}


sub getAnalysisParams {
    my $dbh = shift;
    my $aid = shift;

    my $sql = "SELECT * FROM analysis WHERE analysis_id = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($aid);
    my $dbRow = $sth->fetchrow_hashref;
    warn "Unable to find $aid in analysis table" and return undef if not $dbRow;

    # Unfortunately this is a bit hacky.  We need to come up with a better way to share info
    # between the web app and this app.
    my $json = $dbRow->{analysis_params};
    my $params = decode_json($json);
    $params = {} if (not $params or ref $params ne "HASH"); # this can happen if there are no values

    return ($dbRow, $params);
}


sub makeAnalysisDirName {
    my $dbRow = shift;
    my $params = shift;

    my $taxSearch = $params->{tax_search_hash} ? "-" . $params->{tax_search_hash} : "";
    my $ncSuffix = $params->{compute_nc} ? "-nc" : "";
    my $nfSuffix = $params->{remove_fragments} ? "-nf" : "";
    my $aDir = $dbRow->{analysis_filter} . "-" .
        $dbRow->{analysis_evalue} . "-" .
        $dbRow->{analysis_min_length} . "-" .
        $dbRow->{analysis_max_length} . $taxSearch . $ncSuffix . $nfSuffix;

    return $aDir;
}


sub createInfo {
    my $type = shift;
    my $config = shift;
    my $info = createGeneric($config, $type);
    if ($type eq TYPE_GENERATE) {
        $info->{final_file} = ["cleanuperr", "graphs", "cleanup"];
        $info->{file_name_key} = "generate_fasta_file";
        $info->{uploads_dir} = $config->{"$type.uploads_dir"};
        $info->{table_name} = TYPE_GENERATE;
    } elsif ($type eq TYPE_ANALYSIS) {
        $info->{final_file} = ["stats"];
        $info->{table_name} = TYPE_ANALYSIS;
    } elsif ($type eq TYPE_GNN) {
        $info->{final_file} = [];
        $info->{file_name_key} = "filename";
        $info->{uploads_dir} = $config->{"$type.uploads_dir"};
        $info->{table_name} = TYPE_GNN;
    } elsif ($type eq TYPE_GND) {
        $info->{final_file} = [];
        $info->{uploads_dir} = $config->{"$type.uploads_dir"};
        $info->{table_name} = TYPE_GND;
    }
    return $info;
}


sub createGeneric {
    my $config = shift;
    my $type = shift;
    my $info = {
        type => $type,
        results_dir_name => $config->{"$type.results_dir_name"},
        finish_file => $config->{"$type.finish_file"},
        base_dir => $config->{"$type.output_dir"},
        file_name_key => "",
    };
    die "Need config value for $type.output_dir in config file" if not $info->{base_dir};
    return $info;
}


sub parseForSlurmId {
    my $self = shift;
    my $output = shift;

    my @lines = split(m/\n/, $output);
    my $lastLine = pop @lines // 0;
    $lastLine =~ s/^\s*(.*?)\s*$/$1/s;

    return $lastLine;
}


sub getUploadedFilename {
    my $self = shift;
    my $jobId = shift;
    my $parms = shift;
    my $subType = shift || "";
    my $dbRow = shift || undef;

    if ($self->{info}->{type} eq TYPE_GND) {
        my $ext = $subType eq "DIRECT" ? "sqlite" : "zip";
        return {file => "$jobId.$ext", ext => $ext};
    }

    my $type = $self->{info}->{type};
    my $info;
    if ($type eq TYPE_GENERATE and ($subType eq TYPE_COLORSSN or $subType eq TYPE_CLUSTER or $subType eq TYPE_NBCONN or $subType eq TYPE_CONVRATIO)) {
        # Create a color SSN job from an EST job
        if ($parms->{generate_color_ssn_source_id} and exists $parms->{generate_color_ssn_source_idx}) {
            my ($dbRow, $aparms) = getAnalysisParams($self->{dbh}, $parms->{generate_color_ssn_source_id}); 
            my $gid = $dbRow->{analysis_generate_id};
            return undef if not $gid;

            my $estDir = $self->getJobDir($gid) . "/" . $self->getResultsDirName();
            my $aDir = getAnalysisDirName($self->{dbh}, $parms->{generate_color_ssn_source_id});

            my $ssnFile = $self->getSsnFileName($estDir, $aDir, $parms->{generate_color_ssn_source_idx});
            return $ssnFile ? {file_path => "$estDir/$aDir/$ssnFile", file => $ssnFile, ext => ""} : undef;
        # Create color SSN job from another color SSN job
        } elsif ($parms->{color_ssn_source_color_id}) {
            my $estDir = $self->getJobDir($parms->{color_ssn_source_color_id}) . "/" . $self->getResultsDirName();
            my $ssnFile = "ssn";
            my $ssnPath = "$estDir/$ssnFile";
            return -f "$ssnPath.xgmml" ? {file_path => "$ssnPath.xgmml", file => "$ssnFile.xgmml", ext => ""} : {file_path => "$ssnPath.zip", file => "$ssnFile.zip", ext => ""};
        }
    }

    if (not $info) {
        my $file = $parms->{$self->{info}->{file_name_key}};
        return {file => "$jobId.", ext => ""} if $file !~ m/\./;
        $file =~ s/^.*\.([^\.]+)$/$1/; # extension
        return {file => "$jobId.$file", ext => $file};
    }
}


sub getSsnFileName {
    my $self = shift;
    my $estDir = shift;
    my $aDir = shift;
    my $ssnIdx = shift;

    my $statsFile = "$estDir/$aDir/stats.tab";
    return "" if not -f $statsFile;

    my $ssnFile = "";

    open my $fh, "<", $statsFile or return 0;
    my $line = <$fh>;
    my $lc = 0;
    while ($line = <$fh>) {
        chomp $line;
        if ($lc++ == $ssnIdx) {
            my @p = split(m/\t/, $line);
            $ssnFile = $p[0];
            last;
        }
    }
    close $fh;

    my $filePath = "$estDir/$aDir/$ssnFile";
    return -f $filePath ? $ssnFile : "$ssnFile.zip";
}


sub getUploadsDir {
    my $self = shift;
    return $self->{info}->{uploads_dir} // "";
}


1;

