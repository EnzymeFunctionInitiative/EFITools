
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
    }

    $job->getScheduler();
    if ($job->hasErrors()) {
        die join("\n", $job->getErrors()), "\n";
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
    );

    return @types;
}


1;

