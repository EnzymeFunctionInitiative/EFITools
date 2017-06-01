#!/usr/bin/env perl

use Getopt::Long;

$result=GetOptions ("ssnin=s"		=> \$ssnin,
		    "n=s"		=> \$n,
		    "nomatch=s"		=> \$nomatch,
		    "noneigh=s"		=> \$noneigh,
		    "ssnout=s"		=> \$ssnout,
		    "incfrac=i"		=> \$incfrac,
		    "stats=s"		=> \$stats,
		    "queue=s"		=> \$queue,
		    "cluster=s"		=> \$cluster,
		    "pfam=s"		=> \$pfam
);

$toolpath=$ENV{'EFIGNN'};
$efignnmod=$ENV{'EFIGNNMOD'};
$efidbmod=$ENV{'EFIDBMOD'};

print "gnn mod is:$efignnmod\n";
print "efidb mod is:$efidbmod\n";
print "distance is $n\n";
print "nomatch is $nomatch\n";
print "noneigh is $noneigh\n";

unless($n>0){
  die "-n $n must be an integer greater than zero\n$usage";
}

unless($ssnin=~/^\//){
  print "ssnin $ssnin\n";
  $ssnin="$ENV{PWD}/$ssnin";
  print "ssnin $ssnin\n";
}

unless($nomatch=~/^\//){
  print "nomatch $nomatch\n";
  $nomatch="$ENV{PWD}/$nomatch";
  print "nomatch $nomatch\n";
}

unless($noneigh=~/^\//){
  print "noneigh $noneigh\n";
  $noneigh="$ENV{PWD}/$noneigh";
  print "nomatch $noneigh\n";
}

unless($cluster=~/^\//){
  $cluster="$ENV{PWD}/$cluster";
}
unless($pfam=~/^\//){
  $pfam="$ENV{PWD}/$pfam";
}
unless($ssnout=~/^\//){
  $ssnout="$ENV{PWD}/$ssnout";
}

unless($stats=~/^\//){
  $stats="$ENV{PWD}/$stats";
}

unless($queue=~/\w/){
  $queue="efi";
}

if($incfrac=~/^\d+$/){

}else{
  if(defined $incfrac){
    die "incfrac must be an integer\n";
  }
  $incfrac=20;  
}


unless(-s $ssnin){
  die "cannot open ssnin file $ssnin\n";
}

if(-s "gnnqsub.sh"){
  die "qsub submission file already exists at this location\n";
}

open(QSUB,">gnnqsub.sh") or die "could not create blast submission script gnnqsub.sh\n";
print QSUB "#!/bin/bash\n";
print QSUB "#PBS -j oe\n";
print QSUB "#PBS -S /bin/bash\n";
print QSUB "#PBS -q $queue\n";
print QSUB "#PBS -l nodes=1:ppn=1\n";
print QSUB "module load $efignnmod\n";
print QSUB "module load $efidbmod\n";
print QSUB "$toolpath/clustergnn.pl -ssnin \"$ssnin\" -ssnout \"$ssnout\" -gnn \"$cluster\" -pfam \"$pfam\" -n $n -nomatch \"$nomatch\" -stats \"$stats\" -noneigh \"$noneigh\" -incfrac \"$incfrac\"\n";
close QSUB;

#submit generate the full xgmml script, job dependences should keep it from running till blast results have been created all blast out files are combined

$gnnjob=`qsub gnnqsub.sh`;
print "Job to make gnn network is :\n $gnnjob";
