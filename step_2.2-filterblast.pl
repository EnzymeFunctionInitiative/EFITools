#!/usr/bin/env perl

#version 0.1, the make it work version
#eventually will be merged into step_s.1-chopblast
#version 0.8.5 Changed the blastfile loop from foreach to while to reduce memory
#version 0.9.1 After much thought, this step of the program will remain seperate
#version 0.9.1 Renamed blastreduce.pl from step_2.2-filterblast.pl


$filename=@ARGV[0];
$blastfile=@ARGV[1];

%seqlengths=();

open FASTA, $blastfile or die "Could not open $blastfile\n";

$sequence="";
while (<FASTA>){
  $line=$_;
  chomp $line;
  if($line=~/^>(\w{6})/){
    $seqlengths{$key}=length $sequence;
    $sequence="";
    $key=$1;
  }else{
    $sequence.=$line;
  }
}
$seqlengths{$key}=length $sequence;
close FASTA;

open(BLASTFILE,$filename) or die "Could not open $filename\n";

%searches=();

while (<BLASTFILE>){
  $line=$_;
  unless($line=~/^\#/){
    chomp $line;
    my @lineary=split /\t/,$line;
    my $sequencea=@lineary[0];
    my $sequenceb=@lineary[1];
    unless($sequencea eq $sequenceb or defined $searches{"$sequencea$sequenceb"}or defined $searches{"$sequenceb$sequencea"} ){
      $searches{"$sequencea$sequenceb"}=1;
      #$id=@lineary[11]/100;
      $id=@lineary[2]/100;
      #print "@lineary[0]\t@lineary[1]\t@lineary[2]\t".@lineary[4]*@lineary[5]."\t@lineary[6]\t$id\t@lineary[3]\t@lineary[8]\t@lineary[9]\t@lineary[10]\t@lineary[4]\t@lineary[5]\n";
      print "@lineary[0]\t@lineary[1]\t@lineary[11]\t".$seqlengths{@lineary[0]}*$seqlengths{@lineary[1]}."\t@lineary[3]\t$id\t@lineary[6]\t@lineary[7]\t@lineary[8]\t@lineary[9]\t$seqlengths{@lineary[0]}\t$seqlengths{@lineary[1]}\n";

    }
  }
}

close BLASTFILE;


