#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use Cwd qw(abs_path);
use Getopt::Long;

use lib "$FindBin::Bin/../../lib";

use EFI::SchedulerApi;
use EFI::Util::FileHandle;
use EFI::Database;
use EFI::Config qw(database_configure parseConfigFile);

use constant BUILD_ENA => 2;
use constant BUILD_COUNTS => 4;


my $WorkingDir;
my $doDownload = 0;
my $interactive = 0;
my $logFile = "";
my $dryRun = 0;
my $skipIfExists = 0;
my $scheduler = "";
my $queue;
my $configFile;
my $sql;
my $batchMode;
my $noSubmit;
my $dbName;
my $buildEna;
my $enaDir;
my $buildCountsOnly;
my $doPdbBlast;
my $dbType;

my $result = GetOptions("dir=s"         => \$WorkingDir,
                        "download"      => \$doDownload,
                        "interactive"   => \$interactive,
                        "log=s"         => \$logFile,
                        "dry-run|dryrun"    => \$dryRun,
                        "exists"        => \$skipIfExists,
                        "scheduler=s"   => \$scheduler,     # to set the scheduler to slurm
                        "queue=s"       => \$queue,
                        "build-config=s"    => \$configFile,
                        "sql"           => \$sql,           # only output the SQL commands for importing data. no other args are required to use this option.
                        "no-prompt"     => \$batchMode,     # run without the GOLD version prompt
                        "no-submit"     => \$noSubmit,      # create the job scripts but don't submit them
                        "db-name=s"     => \$dbName,        # the name of the database
                        "build-ena"     => \$buildEna,      # if this is present, build the ENA table only. the database must have
                                                            # been already created, and the idmapping table must be present.
                        "ena-dir=s"     => \$enaDir,
                        "build-counts"  => \$buildCountsOnly,   # build the family count table only
                        "pdb-blast"     => \$doPdbBlast,
                        "db-type=s"     => \$dbType,
                       );

my $usage = <<USAGE;
Usage: $0
    --dir=working_dir [-download --interactive --log=log_file --dryrun --exists --scheduler=scheduler
    --queue=queue --config=config_file --sql --no-prompt --no-submit --db-name=database_name --build-ena]

    --download      only create the script for downloading the input files
    --build-ena     build the ENA database table only, db-name must already be created and idmapping table
                    must have been imported into the database
    --sql           only output sql commands used for importing data into database, nothing else is done
    --build-counts  build the family count table that needs to be imported into the EFI web server database
                    (not the database that the rest of the files here get imported into)

    --dir           directory to create build structure and download/build database tables in
    --ena-dir       the directory that contains the ENA mirror (should have folders pro, std, etc. in it)
    --db-name       the name of the database to create/use
     
    --log           path to log file (defaults to build directory)
    --dryrun        don't do anything, just display all commands to be executed to the console
    --exists        skip any output or intermediate files that already exist
    --no-prompt     don't prompt the user to confirm the GOLD data version
    --no-submit     create all of the job files but don't submit them

    --bc1           configure the scripts to work with biocluster1 instead of biocluster 2
    --scheduler     specify the scheduler to use (defaults to slurm, can be torque)
    --queue         the cluster queue to use for computation

    --db-type       type of database to write SQL commands for (optional); mysql or sqlite

    --config        path to EFI database configuration file 
    --build-config  path to EFI build configuration file 

USAGE


if (not $WorkingDir) {
    print "Do you want to use the current dir $ENV{PWD} as the build directory? [y/n] ";
    my $resp = <STDIN>;
    if ($resp !~ m/^y/) {
        print "The -dir (build directory) parameter must be specified.\n$usage\n";
        exit(1);
    } else {
        $WorkingDir = $ENV{PWD};
    }
}


$configFile = "$FindBin::Bin/../../conf/build.conf" if not $configFile;
die "The --build-config file parameter must be specified" if not $configFile or not -f $configFile;

my $config = parseConfigFile($configFile);

$doPdbBlast = defined $doPdbBlast;
$dbType = "mysql" if not $dbType;
$queue = $config->{cluster}->{queue} if not $queue and $config->{cluster}->{queue};

die "The BLASTDB environment variable must be present. Did you forget to \"module load BLAST\" before running this program?" if not exists $ENV{BLASTDB} and $doPdbBlast;
die "The EFI database home variable must be present either through argument or present in config file." if not $config->{build}->{db_home};
die "The --db-name parameter is required." if not $dbName and not ($buildEna or $doDownload or $buildCountsOnly);
die "The --queue parameter is required." if not $queue and not ($sql or $doDownload or $buildCountsOnly);







# Various directories and files.
my $DbSupport = "$config->{build}->{db_home}/support";
$WorkingDir = abs_path($WorkingDir);
my $ScriptDir = $FindBin::Bin;
my $BuildDir = "$WorkingDir/build";
my $InputDir = "$WorkingDir/input";
my $OutputDir = "$WorkingDir/output";
my $CompletedFlagFile = "$BuildDir/progress/completed";
my $LocalSupportDir = "$BuildDir/support";
my $CombinedDir = "$BuildDir/combined";
my $PdbBuildDir = "$BuildDir/pdbblast";
my $RemoveFragsDir = "$BuildDir/remove_frags";
my $UniRefDir = "$BuildDir/uniref";


# Number of processors to use for the blast job.
my $np = 200;

mkdir $WorkingDir if not -d $WorkingDir;
mkdir $BuildDir if not -d $BuildDir;
mkdir $InputDir if not -d $InputDir;
mkdir $OutputDir if not -d $OutputDir;
mkdir "$BuildDir/progress" if not -d "$BuildDir/progress";
mkdir $LocalSupportDir if not -d $LocalSupportDir;
mkdir $CombinedDir if not -d $CombinedDir;
mkdir $UniRefDir if not -d $UniRefDir;
mkdir $PdbBuildDir if not -d $PdbBuildDir;
mkdir "$PdbBuildDir/output" if not -d "$PdbBuildDir/output";
mkdir $RemoveFragsDir if not -d $RemoveFragsDir;


# Setup logging. Also redirect stderr to console stdout.
$logFile = "$BuildDir/builddb.log" unless (defined $logFile and length $logFile);
open LOG, ">$logFile" or die "Unable to open log file $logFile";
open(STDERR, ">&STDOUT") or die "Unable to redirect STDERR: $!";
sub logprint { print join("", @_), "\n"; print LOG join("", @_), "\n"; }
#logprint "#OPTIONS: dir=$WorkingDir no-download=$doDownload step=$interactive log=$logFile dryrun=$dryRun exists=$skipIfExists queue=$queue scheduler=$scheduler\n";

logprint "#STARTED builddb.pl AT " . scalar localtime() . "\n";
logprint "# USING WORKING DIR OF $WorkingDir AND SCRIPTS IN $ScriptDir";
logprint "# USING CONFIG FILE $configFile";


my $buildOptions = 0;
$buildOptions = $buildOptions | BUILD_ENA if $buildEna;
$buildOptions = $buildOptions | BUILD_COUNTS if $buildCountsOnly;

my %dbArgs;
$dbArgs{config_file_path} = $configFile if (defined $configFile and -f $configFile);

# Get info from the configuration file.
my $UniprotLocation = $config->{build}->{uniprot_url};
my $InterproLocation = $config->{build}->{interpro_url};
my $TaxonomyLocation = $config->{build}->{taxonomy_url};

# Set up the scheduler API.
$scheduler = "" if not $scheduler;
my $S = new EFI::SchedulerApi('type' => $scheduler, 'queue' => $queue, 'resource' => [1, 1, '100gb'],
    'default_working_dir' => $BuildDir, 'dryrun' => $dryRun, 'abort_script_on_action_fail' => 0);


# Output the sql commands necessary for creating the database and importing the data, then exit.
if (defined $sql) {
    writeSqlCommands($dbName, $buildOptions, $dbType eq "sqlite" ? "sqlite" : "mysql", $S);
    exit(0);
}


`rm -f $CompletedFlagFile.*`;

my $DoSubmit = not defined $noSubmit;



my $FH = new EFI::Util::FileHandle('dryrun' => $dryRun);


# Remove the file that indicates the build process (outside of database import) has completed.
unlink $CompletedFlagFile if -f $CompletedFlagFile;


my $fileNum = 0;
    
if (defined $buildEna and $buildEna) {

    $fileNum = $dbType eq "sqlite" ? 37 : 17;

    $enaDir = "$InputDir/ena/release" if not defined $enaDir;
    if (not -d $enaDir or not -d "$enaDir/std") {
        die "Unable to create job for building ENA table: the ENA directory $enaDir is not valid.";
    }

    # Create ENA table
    logprint "#CREATING ENA TABLE";
    my $enaJobId = submitEnaJob($S->getBuilder(), $enaDir, $fileNum++);
    
} elsif ($doDownload) {
    
    #logprint "\n#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
    #logprint "# USING GOLD DATA THAT WAS LAST UPDATED LOCALLY ON ", scalar localtime((stat("$DbSupport/phylo.tab"))[9]), "\n";
    #logprint "# TO DOWNLOAD THE LATEST DATA, GO TO https://gold.jgi.doe.gov/ AND REMOVE ALL COLUMNS EXCEPT\n";
    #logprint "#    NCBI TAXON ID, DOMAIN, KINGDOM, PHYLUM, CLASS, ORDER, FAMILY, GENUS, SPECIES\n";
    #logprint "# AND COPY THE RESULTING TAB-SEPARATED FILE TO $DbSupport/phylo.tab\n";
    #logprint "#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n";
    #print "To continue using these GOLD data, press enter or press Ctrl+C to abort..." and scalar <STDIN> unless $batchMode;
    #logprint "\n";
   
    # Write out the download script, even though it can't be run on the cluster. This way we can execute it ourselves.
    logprint "#DOWNLOADING FILES\n";
    my $dlJobId;
    $dlJobId = submitDownloadJob($S->getBuilder(), $doDownload, $fileNum++);
    $dlJobId = undef if not $doDownload;

} elsif ($buildOptions & BUILD_COUNTS) { # Build the counts table only

    $fileNum = 27;

    submitBuildCountsJob($S->getBuilder(), undef, $fileNum++);

} else {

    $fileNum = 1; # reserve 0 for download
    
    logprint "#UNZIPPING FILES + COPYING TREMBL FILES + ADDING SPROT FILES\n";
    my $unzipJobId = submitUnzipJob($S->getBuilder(), undef, $fileNum++);
    
    logprint "#PARSING TAXONOMY FILE\n";
    my $taxJobId = submitTaxonomyJob($S->getBuilder(), $unzipJobId, $fileNum++);
    
    # Chop up xml files so we can parse them easily
    logprint "#CHOP MATCH_COMPLETE AND .TAB FILES\n";
    my $ffJobId = submitFinalFileJob($S->getBuilder(), $unzipJobId, $fileNum++);
    
    # Create idmapping table
    logprint "#CREATING IDMAPPING TABLE\n";
    my $idmappingJobId = submitIdMappingJob($S->getBuilder(), $unzipJobId, $fileNum++);
    
    logprint "#CREATE ANNOTATIONS (STRUCT) TAB FILES\n";
    my $structJobId = submitAnnotationsJob($S->getBuilder(), [$idmappingJobId, $ffJobId], $fileNum++);

    logprint "#CREATE NO-FRAGMENT FASTA FILES\n";
    my $noFragJobId = submitNoFragmentJob($S->getBuilder(), $structJobId, $fileNum++);
    
    # Create uniref table
    logprint "#CREATING UNIREF TABLE\n";
    my $unirefJobId = submitBuildUnirefJob($S->getBuilder(), $unzipJobId, $fileNum++);

    # Create family_counts table
    logprint "#CREATING FAMILY COUNTS TABLE\n";
    my $countJobId = submitBuildCountsJob($S->getBuilder(), [$ffJobId, $unirefJobId], $fileNum++);
    
    # We try to do this after everything else has completed so that we don't hog the queue.
    logprint "#FORMAT BLAST DATABASE\n";
    my $splitJobId = submitFormatDbAndSplitFastaJob($S->getBuilder(), $noFragJobId, $np, $PdbBuildDir, $doPdbBlast, $fileNum++);
    
    if ($doPdbBlast) {
       logprint "#DO PDB BLAST\n";
       my $blastJobId = submitBlastJob($S->getBuilder(), [$splitJobId, $unirefJobId, $countJobId], $np, $PdbBuildDir, $fileNum++);
       
       logprint "#CAT BLAST FILES\n";
       my $catJobId = submitCatBlastJob($S->getBuilder(), $blastJobId, $PdbBuildDir, $fileNum++);
   }
}   



if (not $doDownload) {
    # Create and import the data into the database
    logprint "#WRITING SQL SCRIPT FOR IMPORTING DATA INTO DATABASE\n";
    writeSqlCommands($dbName, $buildOptions | BUILD_COUNTS, $fileNum, $S); # Output the build counts job as well, by default
}


logprint "\n#FINISHED AT " . scalar localtime() . "\n";

close LOG;













sub submitIdMappingJob {
    my ($B, $depId, $fileNum) = @_;

    waitForInput();

    my $configParam = ($configFile and -f $configFile) ? "-config $configFile" : "";

    my $file = "$BuildDir/$fileNum-idmapping.sh";
    $B->dependency(0, $depId);
   
    $B->addAction("perl $ScriptDir/import_id_mapping.pl $configParam -input $InputDir/idmapping.dat -output $OutputDir/idmapping.tab");
    $B->addAction("date > $CompletedFlagFile.$fileNum-idmapping\n");
   
    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitEnaJob {
    my ($B, $enaInputDir, $fileNum) = @_;

    waitForInput();

    my $file = "$BuildDir/$fileNum-ena.sh";
    
    $B->resource(1, 1, "300gb");

    addStandardEnv($B);
   
    my $enaDir = "$BuildDir/ena"; 
    mkdir $enaDir unless(-d $enaDir);
    if (not $skipIfExists or not -f "$enaDir/pro.tab") {
        #my @emblDirs = sort map { $_ =~ s/^.*\/Release_(\d+).*?$/$1/; $_ } glob($ENV{EFIEMBL} . "/Release_*");
        #my $release = $emblDirs[-1];
        #my $enaInputDir = "$ENV{EFIEMBL}/Release_$release";
        
        $B->addAction("$ScriptDir/make_ena_table.pl -embl $enaInputDir -pro $enaDir/pro.tab -env $enaDir/env.tab -fun $enaDir/fun.tab -com $enaDir/com.tab -interpro $OutputDir/INTERPRO.tab -pfam $OutputDir/PFAM.tab -idmapping $OutputDir/idmapping.tab -log $BuildDir/make_ena_table.log");
        $B->addAction("date > $CompletedFlagFile.make_ena_table\n");
        $B->addAction("cat $enaDir/env.tab $enaDir/fun.tab $enaDir/pro.tab > $OutputDir/ena.tab");
        $B->addAction("date > $CompletedFlagFile.cat_ena\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-ena\n");
   
    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitFinalFileJob {
    my ($B, $depId, $fileNum) = @_;

    waitForInput();

    my $file = "$BuildDir/$fileNum-finalFiles.sh";
    $B->dependency(0, $depId);
    
    addStandardEnv($B);
    
    mkdir "$BuildDir/match_complete" unless(-d "$BuildDir/match_complete");
    
    if (not $skipIfExists or not -f "$BuildDir/match_complete/0.xml") {
        $B->addAction("$ScriptDir/chopxml.pl -in $InputDir/match_complete.xml -outdir $BuildDir/match_complete");
        $B->addAction("date > $CompletedFlagFile.chopxml\n");
    }
    # Build PFAM, SSF, INTERPRO, and GENE3D .tab files
    if (not $skipIfExists or not -f "$OutputDir/INTERPRO.tab") {
        $B->addAction("$ScriptDir/make_family_tables.pl -outdir $OutputDir -indir $BuildDir/match_complete -types $InputDir/interpro_entry.list -tree $InputDir/interpro_ParentChildTreeFile.txt");
        $B->addAction("date > $CompletedFlagFile.make_family_tables\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-finalFiles\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitBuildCountsJob {
    my ($B, $depId, $fileNum) = @_;

    waitForInput();

    my $file = "$BuildDir/$fileNum-buildCounts.sh";
    $B->dependency(0, $depId);
    $B->resource(1, 1, "200gb");
    
    addStandardEnv($B);
    
    if (not $skipIfExists or not -f "$OutputDir/family_counts.tab") {
        $B->addAction("$ScriptDir/count_families.pl -input $OutputDir/PFAM.tab -output $OutputDir/family_counts.tab -type PFAM -uniref $OutputDir/uniref.tab -merge-domain -clans $InputDir/Pfam-A.clans.tsv");
        $B->addAction("$ScriptDir/count_families.pl -input $OutputDir/INTERPRO.tab -output $OutputDir/family_counts.tab -type INTERPRO -uniref $OutputDir/uniref.tab -merge-domain -append");
        $B->addAction("$ScriptDir/count_families.pl -input $OutputDir/GENE3D.tab -output $OutputDir/family_counts.tab -type GENE3D -uniref $OutputDir/uniref.tab -merge-domain -append");
        $B->addAction("$ScriptDir/count_families.pl -input $OutputDir/SSF.tab -output $OutputDir/family_counts.tab -type SSF -uniref $OutputDir/uniref.tab -merge-domain -append");
        $B->addAction("date > $CompletedFlagFile.family_counts\n");
    }
    if (not $skipIfExists or not -f "$OutputDir/family_info.tab") {
        $B->addAction("$ScriptDir/create_family_info.pl -combined $InputDir/Pfam-A.clans.tsv -merge-counts $OutputDir/family_counts.tab -out $BuildDir/pfam_family_info.tab -use-clans");
        $B->addAction("$ScriptDir/create_family_info.pl -long $InputDir/interpro_names.dat -short $InputDir/interpro_short_names.dat -merge-counts $OutputDir/family_counts.tab -out $BuildDir/interpro_family_info.tab");
        $B->addAction("cp $BuildDir/pfam_family_info.tab $OutputDir/family_info.tab");
        $B->addAction("cat $BuildDir/interpro_family_info.tab >> $OutputDir/family_info.tab");
        # Add clans to the info table
        #$B->addAction("grep CLAN $OutputDir/family_counts.tab | awk '" . '{print $2, "\t", $3, $4, $5}' . "' >> $OutputDir/family_info.tab");
        $B->addAction("date > $CompletedFlagFile.create_family_info\n");
    }
    if (not $skipIfExists or not -f "$OutputDir/PFAM_clans.tab") {
        $B->addAction("cut -f1,2 $InputDir/Pfam-A.clans.tsv > $OutputDir/PFAM_clans.tab");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-buildCounts\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitBuildUnirefJob {
    my ($B, $depId, $fileNum) = @_;

    waitForInput();

    my $file = "$BuildDir/$fileNum-buildUniref.sh";
    $B->dependency(0, $depId);
    $B->resource(1, 1, "350gb");
    
    addStandardEnv($B);
    
    if (not $skipIfExists or not -f "$OutputDir/uniref.tab") {
        foreach my $ver ("50", "90") {
            my $outDir = "$UniRefDir/uniref$ver";
            mkdir $outDir if not -d $outDir;
            $B->addAction("rm -rf $outDir/*");
            $B->addAction("$ScriptDir/chop_uniref_xml.pl -in $InputDir/uniref$ver.xml -outdir $outDir");
            $B->addAction("$ScriptDir/make_uniref_table.pl -in-dir $outDir -out-list $UniRefDir/uniref$ver.list -out-map $UniRefDir/uniref$ver.tab -out-seq $UniRefDir/uniref$ver.fasta");
        }
        $B->addAction("$ScriptDir/merge_uniref_tables.pl $UniRefDir/uniref50.tab $UniRefDir/uniref90.tab $OutputDir/uniref.tab");
        $B->addAction("date > $CompletedFlagFile.make-merge_uniref\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-buildUniref\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitFormatDbAndSplitFastaJob {
    my ($B, $depId, $np, $pdbBuildDir, $doPdbBlast, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-processFasta.sh";
    $B->dependency(0, $depId);

    waitForInput();

    my $dbDir = "$WorkingDir/blastdb";
    mkdir $dbDir if not -d $dbDir;
    my $diamondDbDir = "$WorkingDir/diamonddb";
    mkdir $diamondDbDir if not -d $diamondDbDir;

    $B->workingDirectory($dbDir);
    
    addStandardEnv($B);
    
    #build fasta database
    if (not $skipIfExists or not -f "$dbDir/formatdb.log") {
        my @dbs = ("combined/combined.fasta", "uniref/uniref90.fasta", "uniref/uniref50.fasta");
        foreach my $db (@dbs) {
            (my $target = $db) =~ s%^.*?([^/]+)$%$1%;
            $B->addAction("cd $dbDir");
            $B->addAction("mv $BuildDir/$db $dbDir/$target");
            $B->addAction("formatdb -i $dbDir/$target -p T -o T");
            $B->addAction("mv $dbDir/$target $BuildDir/$db");
            $B->addAction("diamond makedb --in $BuildDir/$db -d $diamondDbDir/$target");
            $B->addAction("date > $CompletedFlagFile.formatdb.$target\n");
        }
    }
    
    my $fracDir = "$pdbBuildDir/fractions";
    mkdir $fracDir if not -d $fracDir;

    if ($doPdbBlast and not $skipIfExists or not -f "$fracDir/fracfile-1.fa") {
        $B->addAction("rm -rf $fracDir");
        $B->addAction("$ScriptDir/splitfasta.pl -parts $np -tmp $fracDir -source $CombinedDir/combined.fasta");
        $B->addAction("date > $CompletedFlagFile.splitfasta\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-processFasta\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitBlastJob {
    my ($B, $depId, $np, $pdbBuildDir, $fileNum) = @_;

    # Separate blast job since we are requesting a job array.

    my $file = "$BuildDir/$fileNum-blast-qsub.sh";
    $B->workingDirectory($pdbBuildDir);
    $B->dependency(0, $depId);
    $B->jobArray("1-$np");

    my @dirs = sort grep(m%^\d+$%, map { s%^.*\/(\d+)\/?%$1%; $_ } glob($ENV{BLASTDB} . "/../*"));
    my $version = $dirs[-1];
    my $dbPath = $ENV{BLASTDB} . "/../" . $version;

    addStandardEnv($B);
    if (not $skipIfExists or not -f "$pdbBuildDir/output/blastout-1.fa.tab") {
        $B->addAction("blastall -p blastp -i $pdbBuildDir/fractions/fracfile-\${JOB_ARRAYID}.fa -d $dbPath/pdbaa -m 8 -e 1e-20 -b 1 -o $pdbBuildDir/output/blastout-\${JOB_ARRAYID}.fa.tab");
        $B->addAction("date > $CompletedFlagFile.blastall\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-blast-qsub\n");
        
    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitCatBlastJob {
    my ($B, $depId, $pdbBuildDir, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-cat-blast.sh";
    $B->workingDirectory($pdbBuildDir);
    $B->dependency(0, $depId);

    addStandardEnv($B);

    if (not $skipIfExists or not -f "$pdbBuildDir/pdb.tab") {
        $B->addAction("cat $pdbBuildDir/output/*.tab > $pdbBuildDir/pdb.full.tab");
        $B->addAction("date > $CompletedFlagFile.blast_cat\n");
    }
    if (not $skipIfExists or not -f "$OutputDir/pdb.tab") {
        $B->addAction($ScriptDir . "/pdbblasttotab.pl -in $pdbBuildDir/pdb.full.tab -out $OutputDir/pdb.tab");
        $B->addAction("date > $CompletedFlagFile.pdbblasttotab\n");
    }
        
    $B->addAction("date > $CompletedFlagFile.$fileNum-cat-blast\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitTaxonomyJob {
    my ($B, $depId, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-taxonomy.sh";

    $B->dependency(0, $depId);

    addStandardEnv($B);
    $B->addAction("$ScriptDir/make_taxonomy_table.pl -input $InputDir/taxonomy.xml -output $OutputDir/taxonomy.tab -verbose");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitDownloadJob {
    my ($B, $doDownload, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-download.sh";

    waitForInput();

    if (not $skipIfExists or not -f "$InputDir/uniprot_sprot.dat.gz" and not -f "$InputDir/uniprot_sprot.dat") {
        logprint "#  Downloading $UniprotLocation/knowledgebase/complete/uniprot_sprot.dat.gz\n";
        $B->addAction("echo Downloading uniprot_sprot.dat.gz");
        $B->addAction("curl -sS $UniprotLocation/knowledgebase/complete/uniprot_sprot.dat.gz > $InputDir/uniprot_sprot.dat.gz");
        $B->addAction("date > $CompletedFlagFile.uniprot_sprot.dat\n");
    }
    if (not $skipIfExists or not -f "$InputDir/uniprot_trembl.dat.gz" and not -f "$InputDir/uniprot_trembl.dat") {
        logprint "#  Downloading $UniprotLocation/knowledgebase/complete/uniprot_trembl.dat.gz\n";
        $B->addAction("echo Downloading uniprot_trembl.dat.gz");
        $B->addAction("curl -sS $UniprotLocation/knowledgebase/complete/uniprot_trembl.dat.gz > $InputDir/uniprot_trembl.dat.gz");
        $B->addAction("date > $CompletedFlagFile.uniprot_trembl.dat\n");
    }
    if (not $skipIfExists or not -f "$InputDir/uniprot_sprot.fasta.gz" and not -f "$InputDir/uniprot_sprot.fasta") {
        logprint "#  Downloading $UniprotLocation/knowledgebase/complete/uniprot_sprot.fasta.gz\n";
        $B->addAction("echo Downloading uniprot_sprot.fasta.gz");
        $B->addAction("curl -sS $UniprotLocation/knowledgebase/complete/uniprot_sprot.fasta.gz > $InputDir/uniprot_sprot.fasta.gz");
        $B->addAction("date > $CompletedFlagFile.uniprot_sprot.fasta\n");
    }
    if (not $skipIfExists or not -f "$InputDir/uniprot_trembl.fasta.gz" and not -f "$InputDir/uniprot_trembl.fasta") {
        logprint "#  Downloading $UniprotLocation/knowledgebase/complete/uniprot_trembl.fasta.gz\n";
        $B->addAction("echo Downloading uniprot_trembl.fasta.gz");
        $B->addAction("curl -sS $UniprotLocation/knowledgebase/complete/uniprot_trembl.fasta.gz > $InputDir/uniprot_trembl.fasta.gz");
        $B->addAction("date > $CompletedFlagFile.uniprot_trembl.fasta\n");
    }
    if (not $skipIfExists or not -f "$InputDir/match_complete.xml.gz" and not -f "$InputDir/match_complete.xml") {
        logprint "#  Downloading $InterproLocation/match_complete.xml.gz\n";
        $B->addAction("echo Downloading match_complete.xml.gz");
        $B->addAction("curl -sS $InterproLocation/match_complete.xml.gz > $InputDir/match_complete.xml.gz");
        $B->addAction("date > $CompletedFlagFile.match_complete.xml\n");
    }
    if (not $skipIfExists or not -f "$InputDir/idmapping.dat.gz" and not -f "$InputDir/idmapping.dat") {
        logprint "#  Downloading $UniprotLocation/knowledgebase/idmapping/idpmapping.dat.gz\n";
        $B->addAction("echo Downloading idmapping.dat.gz");
        $B->addAction("curl -sS $UniprotLocation/knowledgebase/idmapping/idmapping.dat.gz > $InputDir/idmapping.dat.gz");
        $B->addAction("date > $CompletedFlagFile.idmapping.dat\n");
    }
    if (not $skipIfExists or not -f "$InputDir/taxonomy.xml.gz" and not -f "$InputDir/taxonomy.xml") {
        if (defined $TaxonomyLocation) {
            logprint "#  Downloading $TaxonomyLocation\n";
            $B->addAction("echo Downloading taxonomy.xml.gz");
            $B->addAction("curl -sS $TaxonomyLocation > $InputDir/taxonomy.xml.gz");
            $B->addAction("date > $CompletedFlagFile.taxonomy.xml\n");
        }
    }
    if (not $skipIfExists or not -f "$InputDir/uniref50.xml.gz" and not -f "$InputDir/uniref50.xml") {
        logprint "#  Downloading $UniprotLocation/uniref/uniref50/uniref50.xml.gz\n";
        $B->addAction("echo Downloading uniref50.xml.gz");
        $B->addAction("curl -sS $UniprotLocation/uniref/uniref50/uniref50.xml.gz > $InputDir/uniref50.xml.gz");
        $B->addAction("date > $CompletedFlagFile.uniref50.xml\n");
    }
    if (not $skipIfExists or not -f "$InputDir/uniref90.xml.gz" and not -f "$InputDir/uniref90.xml") {
        logprint "#  Downloading $UniprotLocation/uniref/uniref90/uniref90.xml.gz\n";
        $B->addAction("echo Downloading uniref90.xml.gz");
        $B->addAction("curl -sS $UniprotLocation/uniref/uniref90/uniref90.xml.gz > $InputDir/uniref90.xml.gz");
        $B->addAction("date > $CompletedFlagFile.uniref90.xml\n");
    }
    my $pfamInfoUrl = $config->{build}->{pfam_info_url};
    my $clanInfoUrl = exists $config->{build}->{clan_info_url} ? $config->{build}->{clan_info_url} : "";
    if (not $skipIfExists or not -f "$InputDir/Pfam-A.clans.tsv.gz" and not -f "$InputDir/Pfam-A.clans.tsv") {
        logprint "#  Downloading $pfamInfoUrl\n";
        $B->addAction("echo Downloading Pfam-A.clans.tsv.gz");
        $B->addAction("curl -sS $pfamInfoUrl > $InputDir/Pfam-A.clans.tsv.gz");
        if ($clanInfoUrl) {
            $B->addAction("curl -sS $clanInfoUrl > $InputDir/Pfam-C.gz");
        }
        $B->addAction("date > $CompletedFlagFile.Pfam-A.clans.tsv\n");
    }
    if (not $skipIfExists or not -f "$InputDir/interpro_short_names.dat") {
        logprint "#  Downloading $InterproLocation/short_names.dat\n";
        $B->addAction("echo Downloading short_names.dat");
        $B->addAction("curl -sS $InterproLocation/short_names.dat > $InputDir/interpro_short_names.dat");
        $B->addAction("curl -sS $InterproLocation/names.dat > $InputDir/interpro_names.dat");
        $B->addAction("curl -sS $InterproLocation/ParentChildTreeFile.txt > $InputDir/interpro_ParentChildTreeFile.txt");
        $B->addAction("curl -sS $InterproLocation/entry.list > $InputDir/interpro_entry.list");
        $B->addAction("date > $CompletedFlagFile.interpro_misc\n");
    }

    $B->addAction("echo To download the ENA files, run");
    $B->addAction("echo rsync -auv rsync://bio-mirror.net/biomirror/embl/release/ TARGET_ENA_DIR");
    $B->addAction("echo $ScriptDir/mirror/mirror.pl emblwgs_pub PATH_TO_MIRROR_PACKAGE_DIR/emblwgs");
    #rsync -auv rsync://bio-mirror.net/biomirror/embl/release/

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    logprint "#COMPLETED DOWNLOAD AT " . scalar localtime() . "\n"
        if $interactive;

    return ($doDownload and $DoSubmit) ? $S->submit($file) : undef;
}


sub submitUnzipJob {
    my ($B, $depId, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-process-downloads.sh";

    $B->dependency(0, $depId);
    $B->mailError();

    addStandardEnv($B);

    waitForInput();

    my @gzFiles = glob("$InputDir/*.gz");
    if (scalar @gzFiles) {
        $B->addAction("gunzip -f $InputDir/*.gz");
        $B->addAction("date > $CompletedFlagFile.gunzip\n");
        # If there was an error (e.g. bad gz) then there will be one or more .gz files in the dir.
        # If that is the case we exit with an error code of 1 which will cause all of the dependent
        # jobs to abort.
        $B->addAction("NUM_GZ=`ls -l $InputDir | grep '\.gz\\s*\$' | wc -l`");
        $B->addAction("if (( \$NUM_GZ > 0 ));");
        $B->addAction("then");
        $B->addAction("    exit 1");
        $B->addAction("fi");
    }

    #create new copies of trembl databases
    if (not $skipIfExists or not -f "$CombinedDir/combined.fasta") {
        $B->addAction("cp $InputDir/uniprot_trembl.fasta $CombinedDir/combined.fasta");
        $B->addAction("date > $CompletedFlagFile.combined.fasta_cp\n");
    }
    if (not $skipIfExists or not -f "$CombinedDir/combined.dat") {
        $B->addAction("cp $InputDir/uniprot_trembl.dat $CombinedDir/combined.dat");
        $B->addAction("date > $CompletedFlagFile.combined.dat_cp\n");
    }
    
    #add swissprot database to trembl copy
    if (not $skipIfExists or not -f "$CombinedDir/combined.fasta") {
        $B->addAction("cat $InputDir/uniprot_sprot.fasta >> $CombinedDir/combined.fasta");
        $B->addAction("date > $CompletedFlagFile.combined.fasta_cat\n");
    }
    if (not $skipIfExists or not -f "$CombinedDir/combined.dat") {
        $B->addAction("cat $InputDir/uniprot_sprot.dat >> $CombinedDir/combined.dat");
        $B->addAction("date > $CompletedFlagFile.combined.dat_cat\n");
    }

    # July 2017 - Don't include GI anymore
    #if (not $skipIfExists or not -f "$InputDir/gionly.dat") {
    #    $B->addAction("grep -P \"\tGI\t\" $InputDir/idmapping.dat > $LocalSupportDir/gionly.dat");
    #    $B->addAction("date > $CompletedFlagFile.gionly\n");
    #}

    waitForInput();

    if (not $skipIfExists or not -f "$LocalSupportDir/hmp.tab") {
        $B->addAction("cp $DbSupport/hmp.tab $LocalSupportDir/hmp.tab\n");
    }
    if (not $skipIfExists or not -f "$LocalSupportDir/gdna.tab") {
        $B->addAction("cp $DbSupport/gdna.tab $LocalSupportDir/gdna.tab"); 
        $B->addAction("tr -d ' \t' < $LocalSupportDir/gdna.tab > $LocalSupportDir/gdna.new.tab");
        $B->addAction("rm $LocalSupportDir/gdna.tab");
        $B->addAction("mv $LocalSupportDir/gdna.new.tab $LocalSupportDir/gdna.tab");
    }
    $B->addAction("date > $CompletedFlagFile.support_files\n");
    
    $B->addAction("date > $CompletedFlagFile.$fileNum-process-downloads\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitAnnotationsJob {
    my ($B, $depId, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-annotations.sh";

    $B->resource(1, 1, "150gb");
    $B->dependency(0, $depId);

    addStandardEnv($B);

    waitForInput();

    if (not $skipIfExists or not -f "$OutputDir/annotations.tab") {
        # Exclude GI
        #$B->addAction($ScriptDir . "/make_annotations_table.pl -dat $CombinedDir/combined.dat -annotations $OutputDir/annotations.tab -uniprotgi $LocalSupportDir/gionly.dat -efitid $LocalSupportDir/efi-accession.tab -gdna $LocalSupportDir/gdna.tab -hmp $LocalSupportDir/hmp.tab -phylo $LocalSupportDir/phylo.tab");
        $B->addAction($ScriptDir . "/make_annotations_table.pl -dat $CombinedDir/combined.dat -annotations $OutputDir/annotations.tab -gdna $LocalSupportDir/gdna.tab -hmp $LocalSupportDir/hmp.tab");
        $B->addAction("date > $CompletedFlagFile.make_annotations_table\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-annotations\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub submitNoFragmentJob {
    my ($B, $depId, $fileNum) = @_;

    my $file = "$BuildDir/$fileNum-remove-fragments.sh";

    $B->resource(1, 1, "15gb");
    $B->dependency(0, $depId);

    addStandardEnv($B);

    waitForInput();

    if (not $skipIfExists or not -f "$OutputDir/annotations.tab") {
        my $fragTab = "$RemoveFragsDir/anno_frag_col.tab";
        my $fragIds = "$RemoveFragsDir/fragment_ids.list";
        $B->addAction("cut -f1,22 $OutputDir/annotations.tab > $fragTab");
        $B->addAction("awk '{ if (\$2 == 1) { print \$1 } }' $fragTab > $fragIds");
        $B->addAction($ScriptDir . "/remove_ids_from_file.pl --id-list $fragIds --in $CombinedDir/combined.fasta --out $CombinedDir/combined_no_frags.fasta");
        $B->addAction($ScriptDir . "/remove_ids_from_file.pl --id-list $fragIds --in $UniRefDir/uniref90.fasta --out $UniRefDir/uniref90_no_frags.fasta");
        $B->addAction($ScriptDir . "/remove_ids_from_file.pl --id-list $fragIds --in $UniRefDir/uniref50.fasta --out $UniRefDir/uniref50_no_frags.fasta");
        $B->addAction("date > $CompletedFlagFile.remove_ids_from_file\n");
    }

    $B->addAction("date > $CompletedFlagFile.$fileNum-remove-fragments\n");

    $B->outputBaseFilepath($file);
    $B->renderToFile($file);

    return $DoSubmit ? $S->submit($file) : undef;
}


sub writeSqlCommands {
    my ($dbName, $buildOptions, $fileNum, $S) = @_;

    my $sql = "";
    my $countSql = "";
    my $enaSql = "";

    my $startTrans = $dbType eq "sqlite" ? "BEGIN TRANSACTION;" : "START TRANSACTION;";
    my $loadStart = $dbType eq "sqlite" ? ".import" : "LOAD DATA LOCAL INFILE";
    my $loadMid = $dbType eq "sqlite" ? "" : "INTO TABLE";
    my $loadEnd = $dbType eq "sqlite" ? "" : ";";
    my $endTrans = "COMMIT;";
    my $sqlSepStmt = $dbType eq "sqlite" ? ".separator \"\\t\"\n\n" : "";

    if ($buildOptions & BUILD_COUNTS) {
        $countSql = $sqlSepStmt . <<SQL;

$startTrans
SELECT 'CREATING family_info' AS '';
DROP TABLE IF EXISTS family_info;
CREATE TABLE family_info(family VARCHAR(10) PRIMARY KEY, short_name VARCHAR(50), long_name VARCHAR(255), num_members INTEGER, num_uniref50_members INTEGER, num_uniref90_members INTEGER);
/*CREATE TABLE family_info(family VARCHAR(10) PRIMARY KEY, short_name VARCHAR(50), long_name VARCHAR(255), num_members INTEGER, num_uniref50_members INTEGER, num_uniref90_members INTEGER, family_type VARCHAR(22), parent VARCHAR(10));*/
CREATE INDEX family_Index ON family_info (family);

SELECT 'LOADING family_info' AS '';
$loadStart '$OutputDir/family_info.tab' $loadMid family_info$loadEnd
$endTrans

$startTrans
SELECT 'CREATING PFAM_clans' AS '';
DROP TABLE IF EXISTS PFAM_clans;
CREATE TABLE PFAM_clans(pfam_id VARCHAR(24), clan_id VARCHAR(24));
CREATE INDEX clan_id_Index ON PFAM_clans (clan_id);

SELECT 'LOADING PFAM_clans' AS '';
$loadStart '$OutputDir/PFAM_clans.tab' $loadMid PFAM_clans$loadEnd
$endTrans

SQL
        ;
    }
    
    if ($buildOptions & BUILD_ENA) {
        $enaSql = $sqlSepStmt . <<SQL;

$startTrans
SELECT 'CREATING ena' AS '';
DROP TABLE IF EXISTS ena;
CREATE TABLE ena(ID VARCHAR(20),AC VARCHAR(10),NUM int,TYPE bool,DIRECTION bool,start int, stop int);
/*CREATE TABLE ena(ID VARCHAR(20),AC VARCHAR(10),NUM int,TYPE bool,DIRECTION bool,start int, stop int,strain VARCHAR(2000),pfam VARCHAR(1800));*/
CREATE INDEX ena_acnum_Index ON ena(AC, NUM);
CREATE INDEX ena_ID_Index ON ena(id);

SELECT 'LOADING ena' AS '';
$loadStart '$OutputDir/ena.tab' $loadMid ena$loadEnd
$endTrans

SQL
        ;
    }
    
    {
        $sql = $sqlSepStmt . <<SQL;

$startTrans
SELECT 'CREATING ANNOTATIONS' AS '';
DROP TABLE IF EXISTS annotations;
CREATE TABLE annotations(accession VARCHAR(10) PRIMARY KEY,
                         Uniprot_ID VARCHAR(15),
                         STATUS VARCHAR(10),
                         Sequence_Length INTEGER,
                         Taxonomy_ID INTEGER,
                         GDNA VARCHAR(5),
                         Description VARCHAR(255),
                         SwissProt_Description VARCHAR(255),
                         Organism VARCHAR(150),
                         GN VARCHAR(40),
                         pdb VARCHAR(3000),
                         GO VARCHAR(1300),
                         KEGG VARCHAR(100),
                         STRING VARCHAR(100),
                         BRENDA VARCHAR(100),
                         PATRIC VARCHAR(100),
                         HMP_Body_Site VARCHAR(75),
                         HMP_Oxygen VARCHAR(50),
                         EFI_ID VARCHAR(6),
                         EC VARCHAR(185),
                         Cazy VARCHAR(30),
                         Fragment TINYINT(1));
CREATE INDEX TaxID_Index ON annotations (Taxonomy_ID);
CREATE INDEX accession_Index ON annotations (accession);
CREATE INDEX STATUS_Index ON annotations (STATUS);
CREATE INDEX Fragment_Index ON annotations (Fragment);
SELECT 'LOADING annotations' AS '';
$loadStart '$OutputDir/annotations.tab' $loadMid annotations$loadEnd
$endTrans

$startTrans
SELECT 'CREATING TAXONOMY' AS '';
DROP TABLE IF EXISTS taxonomy;
CREATE TABLE taxonomy(Taxonomy_ID INTEGER, Domain VARCHAR(25), Kingdom VARCHAR(25), Phylum VARCHAR(30), Class VARCHAR(25), TaxOrder VARCHAR(30), Family VARCHAR(25), Genus VARCHAR(40), Species VARCHAR(50));
CREATE INDEX TaxID_Index ON taxonomy (Taxonomy_ID);
SELECT 'LOADING taxonomy' AS '';
$loadStart '$OutputDir/taxonomy.tab' $loadMid taxonomy$loadEnd
$endTrans

$startTrans
SELECT 'CREATING GENE3D' AS '';
DROP TABLE IF EXISTS GENE3D;
CREATE TABLE GENE3D(id VARCHAR(24), accession VARCHAR(10), start INTEGER, end INTEGER);
CREATE INDEX GENE3D_ID_Index ON GENE3D (id);
SELECT 'LOADING GENE3D' AS '';
$loadStart '$OutputDir/GENE3D.tab' $loadMid GENE3D$loadEnd
$endTrans

$startTrans
SELECT 'CREATING PFAM' AS '';
DROP TABLE IF EXISTS PFAM;
CREATE TABLE PFAM(id VARCHAR(24), accession VARCHAR(10), start INTEGER, end INTEGER);
CREATE INDEX PAM_ID_Index ON PFAM (id);
CREATE INDEX PAM_Accession_Index ON PFAM (accession);
SELECT 'LOADING PFAM' AS '';
$loadStart '$OutputDir/PFAM.tab' $loadMid PFAM$loadEnd
$endTrans

$startTrans
SELECT 'CREATING UNIREF' AS '';
DROP TABLE IF EXISTS uniref;
CREATE TABLE uniref(accession VARCHAR(10), uniref50_seed VARCHAR(10), uniref90_seed VARCHAR(10));
CREATE INDEX uniref_accession_Index ON uniref (accession);
CREATE INDEX uniref50_seed_Index ON uniref (uniref50_seed);
CREATE INDEX uniref90_seed_Index ON uniref (uniref90_seed);
SELECT 'LOADING UNIREF' AS '';
$loadStart '$OutputDir/uniref.tab' $loadMid uniref$loadEnd
$endTrans

$startTrans
SELECT 'CREATING SSF' AS '';
DROP TABLE IF EXISTS SSF;
CREATE TABLE SSF(id VARCHAR(24), accession VARCHAR(10), start INTEGER, end INTEGER);
CREATE INDEX SSF_ID_Index ON SSF (id);
SELECT 'LOADING SSF' AS '';
$loadStart '$OutputDir/SSF.tab' $loadMid SSF$loadEnd
$endTrans

$startTrans
SELECT 'CREATING INTERPRO' AS '';
DROP TABLE IF EXISTS INTERPRO;
CREATE TABLE INTERPRO(id VARCHAR(24), accession VARCHAR(10), start INTEGER, end INTEGER, family_type VARCHAR(22), parent VARCHAR(10), is_leaf BOOLEAN);
CREATE INDEX INTERPRO_ID_Index ON INTERPRO (id);
CREATE INDEX INTERPRO_Accession_Index ON INTERPRO (accession);
SELECT 'LOADING INTERPRO' AS '';
$loadStart '$OutputDir/INTERPRO.tab' $loadMid INTERPRO$loadEnd
$endTrans

$startTrans
SELECT 'CREATING colors' AS '';
DROP TABLE IF EXISTS colors;
CREATE TABLE colors(cluster INTEGER PRIMARY KEY,color VARCHAR(7));
SELECT 'LOADING colors' AS '';
$loadStart '$DbSupport/colors.tab' $loadMid colors$loadEnd
$endTrans

$startTrans
SELECT 'CREATING idmapping' AS '';
DROP TABLE IF EXISTS idmapping;
CREATE TABLE idmapping (uniprot_id VARCHAR(15), foreign_id_type VARCHAR(15), foreign_id VARCHAR(20));
CREATE INDEX uniprot_id_Index ON idmapping (uniprot_id);
CREATE INDEX foreign_id_Index ON idmapping (foreign_id);
SELECT 'LOADING idmapping' AS '';
$loadStart '$OutputDir/idmapping.tab' $loadMid idmapping$loadEnd
$endTrans

$startTrans
SELECT 'CREATING version' AS '';
DROP TABLE IF EXISTS version;
CREATE TABLE version (db_version INTEGER);
INSERT INTO version VALUES (2);
$endTrans

/*GRANT SELECT ON `$dbName`.* TO 'DB_USER'\@'IP_ADDRESS';*/

SQL
        ;
        
        if ($doPdbBlast) {
            $sql .= <<SQL;
$startTrans
SELECT 'CREATING pdbhits' AS '';
DROP TABLE IF EXISTS pdbhits;
CREATE TABLE pdbhits(ACC VARCHAR(10) PRIMARY KEY, PDB VARCHAR(4), e VARCHAR(20));
CREATE INDEX pdbhits_ACC_Index ON pdbhits (ACC);
SELECT 'LOADING pdbhits' AS '';
$loadStart '$OutputDir/pdb.tab' $loadMid pdbhits$loadEnd
$endTrans
SQL
        }
    }


    my $writeSqlSub = sub {
        my ($filePath, $sqlString) = @_;
        print "WRITING TO $filePath\n";
        open OUT, "> $filePath" or die "Unable to open '$filePath' to save SQL commands: $!";
        print OUT $sqlString;
        close OUT;
    };

    my $outFile = "$BuildDir/$fileNum-createDbAndImportData";
    my $countSqlFile = $outFile . "-counts.sql";
    my $enaSqlFile = $outFile . "-ena.sql";
    my $sqlFile = $outFile . ".sql";

    $writeSqlSub->($countSqlFile, $countSql) if $buildOptions & BUILD_COUNTS;
    $writeSqlSub->($enaSqlFile, $enaSql) if $buildOptions & BUILD_ENA;
    $writeSqlSub->($sqlFile, $sql);


    my $DB = new EFI::Database(%dbArgs);

    my $dbConnCmd = $dbType eq "sqlite" ? "sqlite3" : $DB->getCommandLineConnString();
    (my $mysqlCmdAdmin = $dbConnCmd) =~ s/mysql /mysqladmin /g;
    my $B = $S->getBuilder();
    $B->resource(1, 1, "10gb");
    my $batchFile = "$BuildDir/$fileNum-runDatabaseActions-all.sh";

    my $loadDbName = $dbName;

    if ($buildOptions & BUILD_ENA) {
        $B->addAction(<<CMDS);

if [ -f $CompletedFlagFile.mysql_import-ena ]; then
    echo "The ENA database has already been imported. You will need to manually import the data to"
    echo "override this check."
    exit
fi
CMDS
        $B->addAction("$dbConnCmd $loadDbName < $enaSqlFile");
        $B->addAction("date > $CompletedFlagFile.mysql_import-ena");
    }

    {
        $B->addAction(<<CMDS);

if [ -f $CompletedFlagFile.mysql_import-base ]; then
    echo "It looks like the data has already been imported. You'll have to manually import if you want"
    echo "to override this check.";
    exit
fi
CMDS
        if ($dbType eq "mysql") {
            $B->addAction("#mysql: GRANT SELECT ON `$loadDbName`.* TO 'DB_USER'\@'';*/");
            $B->addAction("#$mysqlCmdAdmin create $loadDbName");
        }
        $B->addAction("$dbConnCmd $loadDbName < $sqlFile");
        $B->addAction("date > $CompletedFlagFile.mysql_import-base");
    }
    
    if ($buildOptions & BUILD_COUNTS) {
        $B->addAction(<<CMDS);

if [ -f $CompletedFlagFile.mysql_import-counts ]; then
    echo "The family counts table has already been imported. You will need to manually import the data"
    echo "to override this check."
    exit
fi
CMDS
        $B->addAction("$dbConnCmd $loadDbName < $countSqlFile");
    }
        
    $B->outputBaseFilepath($batchFile);
    $B->renderToFile($batchFile);
}



# This function allows the user to step through the script.
sub waitForInput {
    $interactive and scalar <STDIN>;
}


sub addStandardEnv {
    my $B = shift;
    return if not $config->{"environment.build"}->{_raw};
    foreach my $module (@{$config->{"environment.build"}->{_raw}}) {
        $B->addAction($module);
    }
}


