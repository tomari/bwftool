#!/usr/bin/perl
# bwftool - BWF (Broadcast Wave Format) header tool
# 2014 H.Tomari. Public Domain.
use strict;
use warnings;
use Fcntl;
use JSON::PP;
use File::Temp qw/ tempfile /;
use File::Copy;
my $usage=<<'EOL';
 bwftool - BWF (Broadcast Wave Format) header tool

 usage:

  % bwftool.pl dump <input.wav>
    Dump BWF information in JSON format

  % bwftool.pl extract <input.wav> <output>
    Extract BWF metadata to a file

  % bwftool.pl copy <bwfinput> <output.wav>
    Copy BWF header on <bwfinput> to <output.wav>
    <bwfinput> can be either extracted BWF info or another WAV file
    WARNING: <output.wav> is modified

  % bwftool.pl vorbis <input.wav>
    Export some of BWF metadata to Vorbis comment field.
    This format is suitable for use with metaflac for FLAC.

EOL

my $quiet=1;

sub find_chunk {
  my ($fh, $label)=@_;
  my $buf;
  my $chunk_label;
  my $chunk_size=0;
  do {
    seek($fh,$chunk_size,Fcntl::SEEK_CUR);
    my $bytes_read=read($fh,$buf,8);
    die "$!" if($bytes_read<0);
    return 0 if($bytes_read==0);
    ($chunk_label, $chunk_size)=unpack("a4V",$buf);
    $quiet or print STDERR "Found chunk: \"".$chunk_label."\" of ".$chunk_size." bytes\n";
  } while($chunk_label ne $label);
  return $chunk_size;
}
sub detect_wave {
  my $fh=shift;
  read($fh, my $buf, 4) or die "$!";
  my $identifier=unpack("a4",$buf);
  return ($identifier eq "WAVE");
}

sub unpack_and_hash {
  my ($unpack_ctrl, $unpack_src, $hashref, @fields) = @_;
  my $stmt='my (';
  my $stmt2;
  foreach (@fields) {
    $stmt.='$'.$_.',';
    $stmt2.='$hashref->{\''.$_.'\'}=$'.$_.';';
  }
  $stmt.=') = unpack(\''.$unpack_ctrl.'\',$unpack_src);';
  eval($stmt.$stmt2);
}

sub decode_bwfbody {
  my $ckData=shift;
  my %decoded;
  unpack_and_hash("Z256Z32Z32a10a8VVv",$ckData,\%decoded,
     'Description',		# ASCII: Description of the sound sequence
     'Originator',		# ASCII: Name of the originator
     'OriginatorReference',	# ASCII: Reference of the originator
     'OriginationDate',		# ASCII: yyyy:mm:dd
     'OriginationTime',		# ASCII: hh:mm:ss
     'TimeReferenceLow',	# First sample count since midnight, low word
     'TimeReferenceHigh',	# First sample count since midnight, high word
     'Version');		# Version of the BWF; unsigned binary number
  my @umid=unpack("x348C64",$ckData);
  $decoded{'UMID'}=\@umid;
  unpack_and_hash("x412vvvvvx180Z*",$ckData,\%decoded,
     'LoudnessValue',		# Integrated Loudness Value of the file in LUFS
     'LoudnessRange',		# Loudness Range of the file in LU
     'MaxTruePeakLevel',	# Maximum True Peak Level of the file in dBTP
     'MaxMomentaryLoudness',	# Highest value of the Momentary Loudness Lv
     'MaxShortTermLoudness',	# Highest value of the Short-Term Loudness Lv
     'CodingHistory');		# History coding

  return \%decoded;
}

sub handlebwf {
  my $path=shift;
  my $funp=shift;
  open(my $fh,'<', $path) or die "$!";
  binmode($fh);
  my $riff_len=find_chunk($fh,"RIFF");
  if($riff_len==0 || !detect_wave($fh)) {
    print STDERR "Not a wave file.\n";
    close($fh);
    return -1;
  }
  my $bext_bytes=find_chunk($fh,"bext");
  if($bext_bytes>0) {
    my $bytes_read=read($fh, my $bext_body, $bext_bytes);
    if($bytes_read<0) {
      print STDERR "$!";
      close($fh);
      return -2;
    } elsif($bytes_read<$bext_bytes) {
      print STDERR "WARNING: bext chunk short\n";
    }
    close($fh);
    $funp->($bext_body, @_);
  } else {
    close($fh);
    print STDERR "WARNING: bext not found\n";
  }
  return 0;
}

sub dumpbwf {
  my $bext_body=shift;
  my $decoded=decode_bwfbody($bext_body);
  print JSON::PP->new->ascii->pretty->encode($decoded);
}

sub extractbwf {
  my $bext_body=shift;
  my $path=shift;
  open(my $fh, '>', $path) or die("cannot open destination: $!");
  binmode($fh);
  extractbwf_with_fh($bext_body, $fh);
  close($fh);
}

sub extractbwf_with_fh {
  my ($bext_body, $fh)=@_;
  # RIFF length= "WAVEbext...." + body length
  my $rifflen=12+length($bext_body);
  my $buf=pack("a4Va8V","RIFF",$rifflen,"WAVEbext",length($bext_body));
  print $fh $buf or die "cannot write: $!";
  print $fh $bext_body or die "cannot write: $!";
  return;
}

sub pip_fh_to_fh {
  my $dstfh=shift;
  my $srcfh=shift;
  my $len=shift;
  my $blksz=32768;
  while($len>0) {
    my $bytes_to_read=($len,$blksz)[$len>$blksz];
    my $bytes_read=read($srcfh, my $buf, $bytes_to_read);
    if($bytes_read<=0) { die "#!";}
    print $dstfh $buf;
    $len-=$bytes_read;
  }
}

sub copybwf {
  my $bwfsrc=shift;
  my $datasrc=shift;
  my ($tmp, $tmppath) = tempfile();
  binmode($tmp);
  # First copy bext from src to tmp
  $quiet or print STDERR "Tmp file= ".$tmppath."\n";
  handlebwf($bwfsrc,\&extractbwf_with_fh,$tmp);
  # Second copy non-bext chunks from dest to tmp
  open(my $dest, '<', $datasrc) or die "cannot read destination file: $!";
  binmode($dest);
  my $dest_rifflen=find_chunk($dest,'RIFF');
  if($dest_rifflen<=0 || !detect_wave($dest)) { die("Destination is not a WAV file."); }
  my $buf;
  while(0<read($dest,$buf,8)) {
    my ($ident, $len)=unpack("a4V",$buf);
    if($ident eq "bext") {
      seek($dest,$len,Fcntl::SEEK_CUR);
      $quiet or print STDERR "Skipping bext on destination file\n";
    } else {
      $quiet or print STDERR "Copying ".$ident."\n";
      print $tmp $buf;
      pip_fh_to_fh($tmp,$dest,$len);
    }
  }
  close($dest);
  my $riff_size=tell($tmp)-8;
  seek($tmp,4,Fcntl::SEEK_SET);
  print $tmp pack("V",$riff_size);
  close($tmp);
  move($tmppath,$datasrc);
}

sub escape_crlf {
  my $x=shift;
  $x =~ s/\r//g;
  $x =~ s/\n/\\n/g;
  return $x;
}

sub bwfDateTime_to_ISO8601 {
  my ($D, $T)=@_;
  my $res="";
  if(length($D)>0) {
    $res.=substr($D,0,4).'-'.substr($D,5,2).'-'.substr($D,8,2);
  }
  if(length($T)>0) {
    $res.='T' if(length($res)>0);
    $res.=substr($T,0,2).':'.substr($T,3,2).':'.substr($T,6,2);
  }
  return $res;
}

sub bwf2vorbis {
  my $bext_body=shift;
  my $d=decode_bwfbody($bext_body);
  print 'SOURCEMEDIA='.escape_crlf($d->{'Originator'})."\n" if(length($d->{'Originator'})>0);
  print 'ENCODING='.escape_crlf($d->{'CodingHistory'})."\n" if(length($d->{'CodingHistory'})>0);
  print 'COMMENT='.escape_crlf($d->{'Description'})."\n" if(length($d->{'Description'})>0);
  if(length($d->{'OriginationDate'})>0 || length($d->{'OriginationTime'})>0) {
    print 'DATE='.bwfDateTime_to_ISO8601($d->{'OriginationDate'},$d->{'OriginationTime'})."\n";
  }
}

sub run {
  if(@ARGV>0 && $ARGV[0] eq "-v") { $quiet=0; shift @ARGV; }
  if(@ARGV<1) {
    return -1;
  } elsif($ARGV[0] eq "dump" && 2==@ARGV) {
    return handlebwf($ARGV[1],\&dumpbwf);
  } elsif($ARGV[0] eq "extract" && 3==@ARGV) {
    return handlebwf($ARGV[1],\&extractbwf,$ARGV[2]);
  } elsif($ARGV[0] eq "copy" && 3==@ARGV) {
    return copybwf($ARGV[1],$ARGV[2]);
  } elsif($ARGV[0] eq "vorbis" && 2==@ARGV) {
    return handlebwf($ARGV[1],\&bwf2vorbis);
  } else {
    return -1;
  }
}

my $res=run();
if($res==-1) {
  print $usage;
}
exit($res);

