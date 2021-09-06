
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
use EFI::Job::CGFP::Identify;
use EFI::Job::CGFP::Quantify;

use EFI::SchedulerApi;

use EFI::Options;


our @EXPORT_OK = qw(create_est_job get_available_types);


sub create_est_job {
    my $jobType = shift;
    my $optionConfigType = shift || "getopt";
    my $optionConfigData = shift || {};

    return undef if not $jobType;

    my $job = undef;

    my $optionParser = new EFI::Options(type => $optionConfigType, config => $optionConfigData);

    if ($jobType eq EFI::Job::EST::Generate::Accession::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::Accession(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::EST::Generate::BLAST::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::BLAST(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::EST::Generate::Family::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::Family(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::EST::Generate::FASTA::JOB_TYPE) {
        $job = new EFI::Job::EST::Generate::FASTA(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::EST::Color::JOB_TYPE) {
        $job = new EFI::Job::EST::Color(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::EST::Analyze::JOB_TYPE) {
        $job = new EFI::Job::EST::Analyze(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::GNT::GNN::JOB_TYPE) {
        $job = new EFI::Job::GNT::GNN(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::GNT::GND::JOB_TYPE) {
        $job = new EFI::Job::GNT::GND(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::CGFP::Identify::JOB_TYPE) {
        $job = new EFI::Job::CGFP::Identify(option_parser => $optionParser);
    } elsif ($jobType eq EFI::Job::CGFP::Quantify::JOB_TYPE) {
        $job = new EFI::Job::CGFP::Quantify(option_parser => $optionParser);
    } else {
        return undef;
    }

    $job->getScheduler();

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
        EFI::Job::GNT::GNN::JOB_TYPE,
        EFI::Job::GNT::GND::JOB_TYPE,
        EFI::Job::CGFP::Identify::JOB_TYPE,
        EFI::Job::CGFP::Quantify::JOB_TYPE,
    );

    return @types;
}


1;

