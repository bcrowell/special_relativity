#!/usr/bin/perl

use strict;

use FindBin;
use File::Glob;
use File::Copy;

# usage:
#   render_one_figure.pl foo.svg
# Renders it unless rendering already exists and is newer than svg. Attempts to render it to pdf first. If that
# fails preflight, redoes it as a bitmap.

my $not_for_real = 0;

my $svg = $ARGV[0];

my @temp_files = ();

my $exists = 0;
foreach my $e('pdf','jpg','png') {
  my $rendered = $svg;
  $rendered =~ s/\.svg$/.$e/;
  $exists = $exists || -e $rendered;
  if (-e $rendered && -M $svg > -M $rendered) {exit(0)} # -M finds age in days
}

if ($exists) {
  print "rendering figure $svg , which has a rendering older than the svg\n";
}
else {
  print "rendering figure $svg\n";
}

my $pdf=$svg;
$pdf=~s/\.svg$/.pdf/;
unless (-e $pdf && -M $svg > -M $pdf) { # 
  my $c="inkscape --export-text-to-path --export-pdf=$pdf $svg  --export-area-drawing 1>/dev/null"; 
  print "  $c\n"; 
  unless ($not_for_real) {
    my $good_prefs = "$FindBin::RealBin/inkscape_rendering_preferences.xml";
    unless (-r $good_prefs) {die "file $good_prefs not found or not readable"}
    # test that user_prefs exists, that I can write into it, and that if there's a prefs file there, I can overwrite it
    my $user_prefs_dir = "~/.config/inkscape";
    my $user_prefs     = "~/.config/inkscape/preferences.xml";
    my $flags =   File::Glob::GLOB_TILDE;       # allow stuff like ~ and ~jones
    my @r = File::Glob::bsd_glob($user_prefs_dir,$flags);
    if (@r<1 || File::Glob::GLOB_ERROR) {die "error finding directory $user_prefs_dir, $!, maybe this is windows, or inkscape isn't installed?"}
    $user_prefs_dir = $r[0];
    my @r = File::Glob::bsd_glob($user_prefs,$flags);
    my $had_prefs = (@r>0);
    my $save_user_prefs = '';
    if ($had_prefs) {
      $user_prefs = $r[0];
      unless (-w $user_prefs) {die "error, $user_prefs not writeable"}
      $save_user_prefs = "$user_prefs_dir/save_preferences.xml";
      # bug: if two instances of this script are running simultaneously, then the following could cause
      #      us to obliterate the user's real preferences file
      move($user_prefs,$save_user_prefs) || die "error moving $user_prefs to $save_user_prefs, $!";
    }
    copy($good_prefs,$user_prefs) || die "error copying $good_prefs to $user_prefs, $!";
    system($c)==0 or die "error in render_one_figure.pl, rendering figure using command $c";
    if ($had_prefs) {
      move($save_user_prefs,$user_prefs) || die "error moving $save_user_prefs to $user_prefs, $!";
    }
  }
  # Check that inkscape output pdf 1.4, since pdftk has buggy support for 1.5.
  # See https://bugs.launchpad.net/inkscape/+bug/1110549
  # Don't just depend on preflight_one_fig.pl to do this, because that would result in it being rendered to bitmap.
  # The following should actually never fail, because code above temporarily overwrites users prefs.
  my $pdf_version = detect_pdf_version($pdf);
  $pdf_version eq '1.4' or die "error in render_one_figure.pl, inkscape output pdf version='$pdf_version'; see https://bugs.launchpad.net/inkscape/+bug/1110549";
}

-x "scripts/preflight_one_fig.pl" or die "couldn't find scripts/preflight_one_fig.pl -- are you running me from home dir?";

if (system("scripts/preflight_one_fig.pl $svg")==0) {finit('')}

print "  preflight failed on pdf rendering of $svg , probably due to transparency; rendering to bitmap instead\n";
push @temp_files,$pdf;
my $png = $svg;
$png=~s/\.svg$/.png/;

# Don't use inkscape --export-png, because as of april 2013, it messes up on transparency.
# Can convert pdf directly to bitmap of the desired resolution using imagemagick, but it messes up on some files (e.g., huygens-1.pdf), so
# go through pdftoppm first.
my $ppm = 'z-1.ppm'; # only 1 page in pdf
push @temp_files,$ppm;
if (system("pdftoppm -r 300 $pdf z")!=0) {finit("Error in render_one_figure.pl, pdftoppm")}
if (system("convert $ppm $png")!=0) {finit("Error in render_one_figure.pl, ImageMagick's convert")}

print "\n";
finit();

# code duplicated in preflight_one_fig.pl
sub detect_pdf_version {
  my $pdf = shift;
  open (my $F,"<$pdf") or return undef;
  my $version_line = <$F>; # should be %PDF-1.4
  close $F;
  $version_line =~ /^\%PDF\-(\d+\.\d+)/i or return undef;
  my $version = $1;
  return $version;
}

sub finit {
  my $message = shift;
  tidy();
  if ($message eq '') {
    exit(0);
  }
  else {
    die $message;
  }
}

sub tidy {
  foreach my $f(@temp_files) {
    unlink($f) or die "error deleting $f, $!";
  }
}
