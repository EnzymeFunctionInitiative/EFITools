
package EFI::Job::CGFP;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../";

use Getopt::Long qw(:config pass_through);

use parent qw(EFI::Job);


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "ssn-in=s",
        "ssn-out-name=s",
        "parent-identify-id|parent-job-id=i",
    );

    my $conf = {};
    my $err = validateOptions($parms, $conf);
    
    push @{$self->{startup_errors}}, $err if $err;

    setupDefaults($self, $conf);

    $self->{conf}->{sb} = $conf;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $conf = shift;

    $conf->{ssn_in} = $parms->{"ssn-in"} // "";
    $conf->{ssn_out_name} = $parms->{"ssn-out-name"} // "";
    $conf->{parent_job_id} = $parms->{"parent-job-id"} // 0;
    
    return "No valid --ssn-in argument provided" if not -f $conf->{ssn_in};
    return "No valid --ssn-out-name argument provided" if not $conf->{ssn_out_name};

}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    #$self->getOutputDir() returns the identify job output directory.
    my $outputDir = $self->getOutputDir();

    my $srcDir = $outputDir; # read stuff from here for child jobs
    my $realDir = $outputDir; # output goes here both for regular and child jobs
    if ($conf->{parent_job_id}) {
        #TODO: fix this hack
        $srcDir =~ s%/(\d+)/*$%/$conf->{parent_job_id}%;
    }

    $conf->{identify_src_dir} = $srcDir;
    $conf->{identify_real_dir} = $realDir;

    $conf->{ssn_cluster_file} = "$realDir/cluster";
    $conf->{sb_marker_file} = "$srcDir/markers.faa";
    $conf->{cdhit_table_file} = "$realDir/cdhit.txt";

    my $toolPath = $self->getToolPath();
    $conf->{tool_path} = "$toolPath/efi_cgfp";
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{sb};

    push @$info, [parent_identify_id => $conf->{parent_job_id}];

    return $info;
}


sub addStandardEnv {
    my $self = shift;
    my $B = shift;
    
    my $func = $B;
    if (ref($B) ne "CODE") {
        $func = sub { $B->addAction(shift); };
    }

    my @mods = $self->getEnvironment("cgfp");
    map { $func->($_); } @mods;
}


sub getShortBREDRepo {
    my $self = shift;
    my $repo = $self->getConfigValue("cgfp", "shortbred_repo");
    $repo = $self->getHomePath() . "/$repo" if $repo !~ m%^/%;
    return $repo;
}


1;

