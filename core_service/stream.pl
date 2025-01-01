#!/usr/bin/perl

use strict;
use File::Find;
use FindBin;

my $video_root = "/var/www/stream_root/video";
our @lists = ();

find(\&process, "${video_root}");

sub get_playlist {
    my %data = ();
    if(open(PLAYLIST, "< ${_[0]}")) {
        my @existing_playlist = <PLAYLIST>;
        my $length = @existing_playlist;
        for(my $i = 3; $i < $length; $i += 2) {
            my $duration = $1 if $existing_playlist[$i] =~ /#EXTINF:([\d\.]+)/;
            my $path = $existing_playlist[$i + 1];
            $duration += 0;
            next unless $path;
            chomp($path);
            next unless $path =~ /^\d{2}_\d+\.ts$/;
            $data{$path} = $duration;
        }
        close(PLAYLIST);
    }
    return %data;
}

sub process {
    if($File::Find::name =~ /^.+\/(\d{8})\/(\d{2})$/) {
        my $date = $1;
        my $hour = $2;

        my %data = &get_playlist("${hour}/playlist.m3u8");
        print $date . '/' . $hour . ": " . %data . ' add ';

        my $add_item = 0;
        my @files = glob "${hour}/*.ts";
        for (@files) {
            my $target_file = $_;
            my $tsfile = substr($target_file, 3);
            next if exists($data{$tsfile});
            my $duration = `ffprobe -hide_banner -loglevel quiet -show_entries format=duration ${target_file}`;
            if($duration =~ /duration=(\d+\.\d+)/) {
                $data{$tsfile} = $1;
                ++$add_item;
            }
        }
        if($add_item) {
            my $max_duration = 0;
            for my $dur(values %data) {
                next if $dur < $max_duration;
                $max_duration = $dur;
            }
            $max_duration = int($max_duration);
            my $playlist = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:${max_duration}\n";
            for my $key(sort keys %data) {
                $playlist .= "#EXTINF:${data{$key}},\n${key}\n";
            }
            $playlist .= "#EXT-X-ENDLIST\n";
            open(DATAFILE, "> ${hour}/playlist.m3u8") or die qw/Can't open file "playlist.m3u8": $!/;
            print DATAFILE $playlist;
            close(DATAFILE);
        }
        print $add_item . "\n";

        unless(-f "${hour}/thumb.jpg") {
            system "ffmpeg -hide_banner -loglevel quiet -i ${files[0]} -ss 0 -vframes 1 -f image2 -s 160x120 ${hour}/thumb.jpg";
        }

        my %item = (path => "${date}/${hour}/playlist.m3u8", thumb => "${date}/${hour}/thumb.jpg");
        push(@lists, \%item);
    }
}

# build JSON
my $out = "[";
my $now_date = -1;
my $now_hour = -1;
for my $item (@lists) {
    my $path = @{$item}{"path"};
    my $thumb = @{$item}{"thumb"};
    my $date = substr($path, 0, 8) + 0;
    my $hour = substr($path, 9, 2) + 0;
    if($date != $now_date) {
        if($now_date >= 0) {$out .= "]},";}
        $out .= "{\"date\":${date},\"hours\":[";
        $now_date = $date;
        $now_hour = -1;
    }
    if($now_hour >= 0) {$out .= ",";}
    $out .= "{\"hour\":${hour},\"path\":\"${path}\",\"thumb\":\"${thumb}\"}";
    $now_hour = $hour;
}
$out .= "]}]";

# output
open(JSONFILE, "> ${video_root}/record.json") or die qw/Can't open file "record.json": $!/;
print JSONFILE $out;
close(JSONFILE);
