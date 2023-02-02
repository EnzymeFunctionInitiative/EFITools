
package EFI::JobManager::Info;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use EFI::JobManager::Types;
use EFI::JobManager::Info::TypeData;
use EFI::JobManager::Info::PathData;
use EFI::JobManager::Info::PathData::Analysis;
use EFI::JobManager::Info::PathData::Quantify;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {config => $args{config}, dbh => $args{dbh}};
    bless $self, $class;

    my $pathInfo = {};
    foreach my $type (EFI::JobManager::Types::get_all_types()) {
        if ($type eq TYPE_ANALYSIS) {
            $pathInfo->{$type} = new EFI::JobManager::Info::PathData::Analysis(config => $args{config}, type => $type, dbh => $args{dbh});
        } elsif ($type eq TYPE_CGFP_QUANTIFY) {
            $pathInfo->{$type} = new EFI::JobManager::Info::PathData::Quantify(config => $args{config}, type => $type, dbh => $args{dbh});
        } else {
            $pathInfo->{$type} = new EFI::JobManager::Info::PathData(config => $args{config}, type => $type, dbh => $args{dbh});
        }
    }
    $self->{path_info} = $pathInfo;

    return $self;
}


sub getTableName {
    my $self = shift;
    my $type = shift;
    return $type;
}


sub getJobDir {
    my $self = shift;
    my $type = shift;
    my $jobId = shift;
    my $row = shift;

    my $resultPath = $self->{path_info}->{$type}->getJobDir($jobId);
    print ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> $type $jobId $resultPath\n";
    return $resultPath;
}


# In the future this could return an absolute path
sub getResultsDirName {
    my $self = shift;
    my $type = shift;
    my $jobId = shift;
    my $checkForCompletion = shift || 0;

    my $dirName = $self->{config}->getResultsDirName($type);
    # Only for checking for job completion
    if ($type eq TYPE_ANALYSIS and $checkForCompletion) {
        $dirName .= "/$jobId";
    }

    return $dirName;
}


sub getAnalysisDirPath {
    my $self = shift;
    my $aid = shift;
    my $isSource = shift || 0;
    # If $isSource is true, then this function is being executed to get the source of an SSN (for input to GNT, for example).
    # If not, then it is a destination for a new analysis job.

    return $self->{path_info}->{&TYPE_ANALYSIS}->getResultsPath($aid, $isSource);
}


sub createInfo {
    my $type = shift;
    my $config = shift;
    my $info = createGeneric($config, $type);
    if ($type eq TYPE_GENERATE) {
        $info->{file_name_key} = "generate_fasta_file";
        $info->{uploads_dir} = $config->{"$type.uploads_dir"};
        $info->{table_name} = TYPE_GENERATE;
    } elsif ($type eq TYPE_ANALYSIS) {
        $info->{table_name} = TYPE_ANALYSIS;
    } elsif ($type eq TYPE_GNN) {
        $info->{file_name_key} = "filename";
        $info->{uploads_dir} = $config->{"$type.uploads_dir"};
        $info->{table_name} = TYPE_GNN;
    } elsif ($type eq TYPE_GND) {
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
    my $type = shift;
    my $jobId = shift;
    my $params = shift;
    my $subType = shift || "";
    my $dbRow = shift || undef;

    if ($type eq TYPE_GND) {
        my $ext = $subType eq "DIRECT" ? "sqlite" : "zip";
        return {file => "$jobId.$ext", ext => $ext};
    }

    my $info;
    if ($type eq TYPE_GENERATE and ($subType eq TYPE_COLORSSN or $subType eq TYPE_CLUSTER or $subType eq TYPE_NBCONN or $subType eq TYPE_CONVRATIO)) {
        # Create a color SSN job from an EST job
        my $aid = $params->{generate_color_ssn_source_id} // $params->{color_ssn_source_color_id};
        my $ssnIdx = $params->{generate_color_ssn_source_idx};
        if ($aid) {
            # This may not be a sub-job
            my $subJobInfo = $self->getSsnInfoFromSsnJob($aid, $ssnIdx, $dbRow); 
            # It was a sub-job, but the parameters were invalid.
            return undef if not defined $subJobInfo;
            return $subJobInfo if ref $subJobInfo eq "HASH";
        }
        # Else we continue on with the search.
    } elsif ($type eq TYPE_CGFP_IDENTIFY and $params->{est_id}) {
        my $estId = $params->{est_id};
        my $colorJobInfo = $self->getSsnInfoFromSsnJob($estId, undef, $dbRow); 
        return undef if not defined $colorJobInfo;
        return $colorJobInfo if ref $colorJobInfo eq "HASH";
    }

    if (not $info) {
        my $field = $self->{config}->getFileNameField($type);
        my $file = $params->{$field} // "";
        return {file => "$jobId.", ext => ""} if $file !~ m/\./;
        $file =~ s/^.*\.([^\.]+)$/$1/; # extension
        return {file => "$jobId.$file", ext => $file};
    }
}


# This may not be a sub-job; this function checks and returns 0 if it's
sub getSsnInfoFromSsnJob {
    my $self = shift;
    my $aid = shift;
    my $ssnIdx = shift;
    my $dbRow = shift;

    # If $ssnIdx is not defined and $aid is, then $aid is a Color SSN job. Else, if both are defined, then
    # the $aid is an analysis job.

    return undef if (not $aid);

    if ($aid and defined $ssnIdx) {
        my $aDirPath = $self->getAnalysisDirPath($aid, 1); # analysis job id
        my ($ssnFilePath, $ssnFileName) = $self->getSsnFileName($aDirPath, $ssnIdx);
        return $ssnFilePath ? {file_path => $ssnFilePath, file => $ssnFileName, ext => ""} : undef;
    # Create color SSN job from another color SSN job
    } elsif ($aid) { # $aid is a generate job ID
        my $estDirPath = $self->{path_info}->{&TYPE_GENERATE}->getResultsPath($aid);
        my $ssnFile = "ssn";
        my $ssnPath = "$estDirPath/$ssnFile";
        return -f "$ssnPath.xgmml" ? {file_path => "$ssnPath.xgmml", file => "$ssnFile.xgmml", ext => ""} : {file_path => "$ssnPath.zip", file => "$ssnFile.zip", ext => ""};
    }
}


sub getSsnFileName {
    my $self = shift;
    my $aDirPath = shift;
    my $ssnIdx = shift;

    # First try the AID version (where we put the analysis job ID instead of the folder name)
    my $statsFile = "$aDirPath/stats.tab";
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

    my $filePath = "$aDirPath/$ssnFile";
    if (-f $filePath) {
        return ($filePath, $ssnFile);
    } else {
        return ("$filePath.zip", "$ssnFile.zip");
    }
}


sub getPathData {
    my $self = shift;
    my $type = shift;
    return $self->{path_info}->{$type};
}


sub getTypeData {
    my $self = shift;
    my $type = shift;

    my $pathData = $self->getPathData($type);

    my $data = new EFI::JobManager::Info::TypeData(path_info => $pathData);
    my $fileName = $self->{config}->getValue($type, "finish_file");
    $data->{finish_file} = $fileName;
    $data->{type} = $type;
    $data->{table} = $type;

    return $data;
}


1;

