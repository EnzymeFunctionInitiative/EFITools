
package EFI::SchedulerApi;

use strict;
use warnings;

use constant SLURM  => 2;

use File::Basename;
use Cwd 'abs_path';
use lib abs_path(dirname(__FILE__) . "/../");

#TODO: use an automatic loading mechanism here (eventually)
#TODO: move the submit() code to the specific scheduler implementations.

use EFI::SchedulerApi::Builder::Pbs::Torque;
use EFI::SchedulerApi::Builder::Pbs::Pro;
use EFI::SchedulerApi::Builder::Slurm;
use EFI::SchedulerApi::Builder::Serial;


sub new {
    my ($class, %args) = @_;
    
    my $self = bless({}, $class);
    $self->{type} = validateSchedulerType($args{type});

    $self->{extra_path} = $args{extra_path} ? $args{extra_path} : "";

    $self->{node} = $args{node} ? $args{node} : "";
    
    $self->{queue} = $args{queue};

    if (exists $args{resource}) {
        $self->{resource} = $args{resource};
    } else {
        $self->{resource} = [];
    }
    
    push(@{ $self->{resource} }, 1) if scalar @{ $self->{resource} } < 1;
    push(@{ $self->{resource} }, 1) if scalar @{ $self->{resource} } < 2;
    push(@{ $self->{resource} }, "20gb") if scalar @{ $self->{resource} } < 3;

    if (exists $args{dryrun}) {
        $self->{dry_run} = $args{dryrun};
    } elsif (exists $args{dry_run}) {
        $self->{dry_run} = $args{dry_run};
    } else {
        $self->{dry_run} = 0;
    }

    if (exists $args{default_working_dir}) {
        $self->{default_working_dir} = $args{default_working_dir};
    }

    if (exists $args{output_base_filepath}) {
        $self->{output_base_filepath} = $args{output_base_filepath};
    }

    if (exists $args{output_base_dirpath}) {
        $self->{output_base_dirpath} = $args{output_base_dirpath};
    }

    if (exists $args{abort_script_on_action_fail}) {
        $self->{abort_script_on_action_fail} = $args{abort_script_on_action_fail};
    }

    if (exists $args{default_wall_time}) {
        $self->{default_wall_time} = $args{default_wall_time};
    }

    # Array reference
    if (exists $args{extra_headers}) {
        $self->{extra_headers} = [@{$args{extra_headers}}];
    }

    $self->{run_serial} = $self->{type} eq EFI::SchedulerApi::Builder::Serial::TYPE ? 1 : 0;

    return $self;
}

sub getType {
    my $self = shift;
    return $self->{type};
}

sub supportsMultiQueue {
    my $self = shift;
    return $self->getType() eq EFI::SchedulerApi::Builder::Slurm::TYPE;
}

sub validateSchedulerType {
    my $type = shift || "";
    $type = autoDetectScheduler() if not $type;
    if ($type eq EFI::SchedulerApi::Builder::Slurm::TYPE) {
        return EFI::SchedulerApi::Builder::Slurm::TYPE;
    } elsif ($type eq EFI::SchedulerApi::Builder::Pbs::Torque::TYPE) {
        return EFI::SchedulerApi::Builder::Pbs::Torque::TYPE;
    } elsif ($type eq EFI::SchedulerApi::Builder::Pbs::Pro::TYPE) {
        return EFI::SchedulerApi::Builder::Pbs::Pro::TYPE;
    } else {
        return EFI::SchedulerApi::Builder::Serial::TYPE;
    }
    return "";
}

sub isSerialScheduler {
    my $type = shift || "";
    return $type eq EFI::SchedulerApi::Builder::Serial::TYPE;
}

sub getSerialScheduler {
    return EFI::SchedulerApi::Builder::Serial::TYPE;
}

sub autoDetectScheduler {
    return EFI::SchedulerApi::Builder::Slurm::TYPE          if `command -v sbatch`;
    return EFI::SchedulerApi::Builder::Pbs::Torque::TYPE    if `command -v qsub`;
    return EFI::SchedulerApi::Builder::Serial::TYPE;
}

sub getSubmitCmd {
    my $self = shift;

    return $self->{submit_cmd} if $self->{submit_cmd};

    if ($self->{type} eq EFI::SchedulerApi::Builder::Slurm::TYPE) {
        return EFI::SchedulerApi::Builder::Slurm::SUBMIT_CMD;
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Pbs::Torque::TYPE) {
        return EFI::SchedulerApi::Builder::Pbs::Torque::SUBMIT_CMD;
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Pbs::Pro::TYPE) {
        return EFI::SchedulerApi::Builder::Pbs::Pro::SUBMIT_CMD;
    }
    return "";
}

sub getSubmitId {
    my $self = shift;
    my $result = shift;

    if ($self->{type} eq EFI::SchedulerApi::Builder::Slurm::TYPE) {
        $result =~ s/[^0-9\[\]]//g;
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Pbs::Torque::TYPE) {
        $result =~ s/^(\d+)(\..*)?$/$1/;
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Pbs::Pro::TYPE) {
        $result =~ s/^(\d+)(\..*)?$/$1/;
    }

    return $result;
}

sub getBuilder {
    my ($self) = @_;

    my %args = ("dry_run" => $self->{dry_run});
    $args{extra_path} = $self->{extra_path} if $self->{extra_path};
    $args{run_serial} = $self->{run_serial};
    $args{default_wall_time} = $self->{default_wall_time} if $self->{default_wall_time};
    $args{extra_headers} = $self->{extra_headers} if $self->{extra_headers};

    my $b;
    if ($self->{type} eq EFI::SchedulerApi::Builder::Slurm::TYPE) {
        $b = new EFI::SchedulerApi::Builder::Slurm(%args);
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Pbs::Torque::TYPE) {
        $b = new EFI::SchedulerApi::Builder::Pbs::Torque(%args);
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Pbs::Pro::TYPE) {
        $b = new EFI::SchedulerApi::Builder::Pbs::Pro(%args);
    } elsif ($self->{type} eq EFI::SchedulerApi::Builder::Serial::TYPE) {
        $b = new EFI::SchedulerApi::Builder::Serial(%args);
    } else {
        die "Invalid scheduler type $self->{type}\n";
    }

    $b->queue($self->{queue}) if defined $self->{queue};
    $b->node($self->{node}) if $self->{node};
    $b->resource($self->{resource}[0], $self->{resource}[1], $self->{resource}[2]) if defined $self->{resource};
    $b->workingDirectory($self->{default_working_dir}) if exists $self->{default_working_dir} and -d $self->{default_working_dir};
    $b->outputBaseFilepath($self->{output_base_filepath}) if exists $self->{output_base_filepath} and length $self->{output_base_filepath};
    $b->outputBaseDirpath($self->{output_base_dirpath}) if exists $self->{output_base_dirpath} and length $self->{output_base_dirpath};
    $b->setScriptAbortOnError($self->{abort_script_on_action_fail}) if exists $self->{abort_script_on_action_fail};

    return $b;
}

sub submit {
    my ($self, $script) = @_;

    my $result = "1.biocluster\n";
    if (not $self->{dry_run} and not $self->{run_serial}) {
        my $submit = $self->getSubmitCmd();
        $result = `$submit $script`;
        $result = $self->getSubmitId($result) if $result;
    }

    return $result;
}


1;

