#!/usr/bin/env perl      

#version 0.9.3	Script Created
#version 0.9.3	Script to write out tables for R, replacement for doing with perl (this is over 25X more effecient)
#version 0.9.5	Fixed a problem where non text characters in SDF name would cause program to crash

use GD::Graph::boxplot;
use GD;
use Getopt::Long;
use Statistics::R;
use Data::Dumper;

$result=GetOptions ("blastout=s"=>	\$blastfile,
		    "edges=s"	=>	\$edges,
		    "length=s"	=>	\$lenhist,
		    "rdata=s"	=>	\$rdata,
		    "fasta=s"	=>	\$fasta,
		    "incfrac=f"=>	\$incfrac);

$edgelimit=10;
@evalues=();
%alignhandles=();
%peridhandles=();
%maxalign=();
$lastmax=0;

open(LENHIST, ">$lenhist") or die "could not write to $lenhist\n";
open(EDGES, ">$edges") or die "could not wirte to $edges\n";
open(BLAST, $blastfile) or die "cannot open blast output file $blastfile\n";
open(MAXALIGN, ">$rdata/maxyal") or die "cannot write out maximium alignment length to $rdata/maxyal\n";
while (<BLAST>){
  $line=$_;
  my @line=split /\t/, $line;
  #my $evalue=int(-(log(@line[3])/log(10))+@line[2]*log(2)/log(10));
  my $evalue=int(-(log(@line[5]*@line[6])/log(10))+@line[4]*log(2)/log(10));
  #my $pid=@line[5]*100;
  my $pid=@line[2];
  #my $align=@line[4];
  my $align=@line[3];
  if($align>$lastmax){
    $lastmax=$align;
    $maxalign{$evalue}=$align;
    print "newmax $evalue, $align\n";
  }
  if(defined @edges[$evalue]){
    @edges[$evalue]++;
    print {$alignhandles{$evalue}} "$align\n";
    print {$peridhandles{$evalue}} "$pid\n";
  }else{
    @edges[$evalue]=1;
    $lzeroevalue=sprintf("%5d",$evalue);
    $lzeroevalue=~tr/ /0/;
    open($alignhandles{$evalue}, ">$rdata/align$lzeroevalue") or die "cannot open alignment file for $evalue\n";
    open($peridhandles{$evalue}, ">$rdata/perid$lzeroevalue") or die "cannot open perid file for $evalue\n";
    print {$alignhandles{$evalue}} "$evalue\n$align\n";
    print {$peridhandles{$evalue}} "$evalue\n$pid\n";
  }
}

#get list of alignment files
@align=`wc -l $rdata/align*`;
#last line is a summary, we dont need that so pop it off
pop @align;



#remove files that represent e-values that are cut off (keeps x axis from being crazy long)
#also populates .tab file for edges histogram at the same time
$removefile=0;
$filekept=0;
foreach $file (@align){
  chomp $file;
  unless($file=~/align/){
    die "something is wrong, file does not have align in name\n";
  }
  unless($file=~/home/){
    die "something is wrong, file does not have home in name\n";
  }
  if($removefile==0){
    $file=~/\s*(\d+)\s+([\w-\/.]+)/;
    $file=$2;
    $edgecount=$1;
    if($1>$edgelimit){
      $filekept++;
      $file=~/(\d+)$/;
      $thisedge=int $1;
      #prints out number of edges at this e-value (retrieved from number of lines in file), for edge histogram
      print EDGES "$thisedge\t$edgecount\n";
      #print "keep $file\n";
    }else{
      #print "unlink $file\n";
      unlink $file or die "could not remove $file\n";
      #although we are only looking at align files, the perid ones have to go as well
      $file=~s/align(\d+)$/perid$1/;
      #print "unlink $file\n";
      unlink $file or die "could not remove $file\n";
      #if we have already saved some data, do not save any more (sets right side of graph)
      if($filekept>0){
        $removefile=1;
      }
    }
  }else{
    $file=~/\s*(\d+)\s+([\w-\/.]+)/; 
    $file=$2;
    #print "unlink $file\n";
    #once we find one value at the end of the graph to remove, we remove the rest
    unlink $file or die "could not remove $file\n";
    #although we are only looking at align files, the perid ones have to go as well
    $file=~s/align(\d+)$/perid$1/;
    #print "unlink $file\n";
    unlink $file or die "could not remove $file\n";
  }
}
print "$filekept results\n";

print "1.out procession complete, now processing fasta\n";


#processing data for the lentgh histogram
#if this script takes too long, we can make this run at same time as above commands.
@evalues=@edges=();
open FASTA, $fasta or die "could not open fastafile $fasta\n";

$largelen=$sequences=$length=0;
$smalllen=50000;
@data=();
$length=0;
$sequences=1;
foreach $line (<FASTA>){
  chomp $line;
  if($line=~/^>/ and $length>0){
    #unless first time, add to count of @data for the sequence length
    $sequences++;
    if(defined @data[$length]){
      @data[$length]++;
    }else{
      @data[$length]=1;
    }
    $length=0;
  }else{
    $length+=length $line;
  }

}

#save the last one in the file
if(defined @data[$length]){
  @data[$length]++;
}else{
  @data[$length]=1;
}


#figure number of sequences to cut off each end
$endtrim=$sequences*(1-$incfrac)/2;
$endtrim=int $endtrim;

$sequencesum=0;
foreach $piece (@data){
  if($sequencesum<=($sequences-$endtrim)){
    $count++;
    $sequencesum+=$piece;
    if($sequencesum<$endtrim){
      $mincount++;
    }
  }
}

#print out the area of the array that we want to keep
for($i=$mincount;$i<=$count;$i++){
  if(defined @data[$i]){
    print LENHIST "$i\t@data[$i]\n";
  }else{
    print LENHIST "$i\t0\n";
  }
}

$lastmax=0;
opendir(DIR, $rdata) or die "cannot open directory $rdata\n";
foreach my $file (grep {$_=~/^align/}readdir DIR){
  open(FILE, "$rdata/$file") or die "cannot open file $rdata/$file\n";
  $linenumber=0;
  while(<FILE>){
    my $line=$_;
    chomp $line;
    if(int($line)>$lastmax and $linenumber>0){
      $lastmax=int($line);
    }
    $linenumber++;
  }
  close FILE;
}

#$lastmax=0;
#foreach $key (keys %maxalign){
#  print "$key\t$lastmax\t$thisedge\t$maxalign{$key}\n";
##  if(int($key)<=int($thisedge) and int($maxalign{$key})>=int($lastmax)){
#  if(int($maxalign{$key})>=int($lastmax)){
#    $lastmax=$maxalign{$key};
#    print "$key,$lastmax\n";
#  }
#}
print "Maxalign $lastmax\n";
print MAXALIGN "$lastmax\n";
close MAXALIGN;