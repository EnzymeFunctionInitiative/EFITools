




package EFI::SchedulerApi::Builder;

sub new {
    my ($class, %args) = @_;

    my $self = bless({}, $class);
    $self->{output} = "";
    $self->{array} = "";
    $self->{shell} = "";
    $self->{queue} = "";
    $self->{res} = [];
    $self->{mail} = "";
    $self->{deps} = "";
    $self->{sched_prefix} = "";
    $self->{actions} = [];
    $self->{working_dir} = "";
    $self->{dryrun} = exists $args{dryrun} ? $args{dryrun} : 0;

    return $self;
}

sub mailEnd {
    my ($self, $clear) = @_;
}

sub jobArray {
    my ($self, $array) = @_;
}

sub queue {
    my ($self, $queue) = @_;
}

sub resource {
    my ($self, $numNodes, $procPerNode) = @_;
}

sub dependency {
    my ($self, $isArray, $jobId) = @_;
}

sub workingDirectory {
    my ($self, $workingDir) = @_;
}

sub addAction {
    my ($self, $actionLine) = @_;

    push(@{$self->{actions}}, $actionLine);
}

sub render {
    my ($self, $fh) = @_;

    print $fh ("#!/bin/bash\n");
    my $pfx = $self->{sched_prefix};
    print $fh ("$pfx " . $self->{array} . "\n") if length($self->{array});
    print $fh ("$pfx " . $self->{output} . "\n") if length($self->{output});
    print $fh ("$pfx " . $self->{shell} . "\n") if length($self->{shell});
    print $fh ("$pfx " . $self->{queue} . "\n") if length($self->{queue});
    foreach my $res (@{ $self->{res} }) {
        print $fh ("$pfx " . $res . "\n") if length($res);
    }
    print $fh ("$pfx " . $self->{deps} . "\n") if length($self->{deps});
    print $fh ("$pfx " . $self->{mail} . "\n") if length($self->{mail});
    print $fh ("$pfx " . $self->{working_dir} . "\n") if length($self->{working_dir});
    foreach my $action (@{$self->{actions}}) {
        print $fh "$action\n";
    }
}

sub renderToFile {
    my ($self, $filePath) = @_;

    if (not $self->{dryrun}) {
        open(FH, "> $filePath") or die "Unable to open job script file $filePath for writing: $!";
        $self->render(\*FH);
        close(FH);
    } else {
        $self->render(\*STDOUT);
    }
}


package EFI::SchedulerApi::TorqueBuilder;

use base qw(EFI::SchedulerApi::Builder);

sub new {
    my ($class, %args) = @_;

    my $self = EFI::SchedulerApi::Builder->new(%args);
    $self->{output} = "-j oe";
    $self->{shell} = "-S /bin/bash";
    $self->{sched_prefix} = "#PBS";

    return bless($self, $class);
}


sub mailEnd {
    my ($self, $clear) = @_;
    if (defined($clear)) {
        $self->{mail} = "";
    } else {
        $self->{mail} = "-m e";
    }
}

sub jobArray {
    my ($self, $array) = @_;

    if (length($array)) {
        $self->{array} = "-t $array";
    } else {
        $self->{array} = "";
    }
}

sub queue {
    my ($self, $queue) = @_;

    $self->{queue} = "-q $queue";
}

sub resource {
    my ($self, $numNodes, $procPerNode) = @_;

    $self->{res} = ["-l nodes=$numNodes:ppn=$procPerNode"];
}

sub dependency {
    my ($self, $isArray, $jobId) = @_;

    my $okStr = $isArray ? "afterokarray" : "afterok";
    $self->{deps} = "-W depend=$okStr:$jobId";
}

sub workingDirectory {
    my ($self, $workingDir) = @_;
    $self->{working_dir} = "-d $workingDir";
}







package EFI::SchedulerApi::SlurmBuilder;

use base qw(EFI::SchedulerApi::Builder);

sub new {
    my ($class, %args) = @_;

    my $self = EFI::SchedulerApi::Builder->new(%args);
    $self->{sched_prefix} = "#SBATCH";

    return bless($self, $class);
}


sub mailEnd {
    my ($self, $clear) = @_;
    if (defined($clear)) {
        $self->{mail} = "";
    } else {
        $self->{mail} = "--mail-type=END";
    }
}

sub jobArray {
    my ($self, $array) = @_;

    if (length($array)) {
        $self->{array} = "--array=$array";
    } else {
        $self->{array} = "";
    }
}

sub queue {
    my ($self, $queue) = @_;

    $self->{queue} = "--partition=$queue";
}

sub resource {
    my ($self, $numNodes, $procPerNode) = @_;

    $self->{res} = ["--nodes=$numNodes", "--tasks-per-node=$procPerNode"];
}

sub dependency {
    my ($self, $isArray, $jobId) = @_;

    my $okStr = "afterok";
    $self->{deps} = "--dependency=$okStr:$jobId";
}

sub workingDirectory {
    my ($self, $workingDir) = @_;
    $self->{working_dir} = "-D $workingDir";
}







package EFI::SchedulerApi;

use strict;
use warnings;
use constant TORQUE => 1;
use constant SLURM  => 2;

use File::Basename;
use Cwd 'abs_path';
use lib abs_path(dirname(__FILE__) . "/../");
use EFI::Util qw(usesSlurm);



sub new {
    my ($class, %args) = @_;
    
    my $self = bless({}, $class);
    if ((exists $args{type} and lc $args{type} eq "slurm") or not exists $args{type} and usesSlurm()) {
        $self->{type} = SLURM;
    } else {
        $self->{type} = TORQUE;
    }
    
    $self->{queue} = $args{queue};

    if (exists $args{resource}) {
        $self->{resource} = $args{resource};
    } else {
        $self->{resource} = [1, 1];
    }

    if (exists $args{dryrun}) {
        $self->{dryrun} = $args{dryrun};
    } else {
        $self->{dryrun} = 0;
    }

    return $self;
}

sub getBuilder {
    my ($self) = @_;

    my %args = ("dryrun" => $self->{dryrun});

    my $b;
    if ($self->{type} == SLURM) {
        $b = new EFI::SchedulerApi::SlurmBuilder(%args);
    } else {
        $b = new EFI::SchedulerApi::TorqueBuilder(%args);
    }

    $b->queue($self->{queue}) if defined $self->{queue};
    $b->resource($self->{resource}[0], $self->{resource}[1]) if defined $self->{resource};

    return $b;
}

sub submit {
    my ($self, $script) = @_;

    my $result = "1.biocluster\n";
    if (not $self->{dryrun}) {
        my $submit = $self->{type} == SLURM ? "sbatch" : "qsub";
        $result = `$submit $script`;
    }

    return $result;
}


1;

