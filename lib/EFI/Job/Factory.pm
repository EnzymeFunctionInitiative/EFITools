
package EFI::Job::Factory;

use strict;
use warnings;

use Exporter qw(import);

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../";

use EFI::Job::EST::Generate::Accession;
use EFI::Job::EST::Generate::BLAST;
use EFI::Job::EST::Generate::Family;
use EFI::Job::EST::Generate::FASTA;
use EFI::Job::EST::Color;
use EFI::Job::EST::Analyze;
use EFI::Job::GNT::GNN;
use EFI::Job::GNT::GND;

use EFI::SchedulerApi;


our @EXPORT_OK = qw(create_est_job get_available_types);


sub create_est_job {
    my $jobType = shift;

    return undef if not $jobType;

    my $job = undef;

    if ($jobType eq EFI::Job::EST::Generate::Accession::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::Accession();
    } elsif ($jobType eq EFI::Job::EST::Generate::BLAST::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::BLAST();
    } elsif ($jobType eq EFI::Job::EST::Generate::Family::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::Family();
    } elsif ($jobType eq EFI::Job::EST::Generate::FASTA::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::FASTA();
    } elsif ($jobType eq EFI::Job::EST::Color::JOB_TYPE) {
        $job = new EFI::Job::EST::Color();
    } elsif ($jobType eq EFI::Job::EST::Analyze::JOB_TYPE) {
        $job = new EFI::Job::EST::Analyze();
    } elsif ($jobType eq EFI::Job::GNT::GNN::JOB_TYPE) {
        $job = new EFI::Job::GNT::GNN();
    } elsif ($jobType eq EFI::Job::GNT::GND::JOB_TYPE) {
        $job = new EFI::Job::GNT::GND();
    } else {
        die "Invalid Job type\n";
    }

    $job->getScheduler();
    if ($job->hasErrors()) {
        my $msg = join("\n", $job->getErrors()) . "\n\n";
        $msg .= "usage: " . $job->getUsage();
        die $msg . "\n";
    }

    return $job;
}


sub get_available_types {
    my @types = (
        EFI::Job::EST::Generate::Accession::JOB_TYPE,
        EFI::Job::EST::Generate::BLAST::JOB_TYPE,
        EFI::Job::EST::Generate::Family::JOB_TYPE,
        EFI::Job::EST::Generate::FASTA::JOB_TYPE,
        EFI::Job::EST::Color::JOB_TYPE,
        EFI::Job::EST::Analyze::JOB_TYPE,
    );

    return @types;
}


1;

