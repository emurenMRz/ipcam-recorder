#!/usr/bin/perl
#
# 24時間以上経過した1時間ディレクトリ（YYYYMMDD/HH/）について、
# ffmpeg のシーン検知で動体が検出されなければディレクトリごと削除する。
# 毎時 crontab で実行する。
#
#   0 * * * * /path/to/core_service/remove.pl

use strict;
use warnings;
use File::Find;
use File::Basename;
use Fcntl qw(:flock);
use POSIX qw(strftime);

my $video_root = "/var/www/stream_root/video";
my $FFMPEG_VER;
my $DELETED_LOG = "${video_root}/.deleted.log";

# --- ffmpeg バージョン取得（初回のみ実行、以降はキャッシュ） ---
sub get_ffmpeg_version {
    return $FFMPEG_VER if defined $FFMPEG_VER;
    my $ver = `ffmpeg -version 2>&1`;
    if($ver =~ /ffmpeg version (\d+\.\d+\.\d+)/) {
        $FFMPEG_VER = $1;
    } else {
        $FFMPEG_VER = "0.0.0";
    }
    return $FFMPEG_VER;
}

# --- 24時間以上経過したか判定 ---
sub is_old_enough {
    my ($dir) = @_;
    my @st = stat($dir);
    return 0 unless @st;
    return ($st[9] <= time() - 24 * 3600) ? 1 : 0;
}

# --- 最大スコアの取得 ---
sub get_max_score {
    my ($file, $filter, $label) = @_;
    my $output = `ffmpeg -hide_banner -loglevel info -i "$file" -vf "$filter" -f null - 2>&1`;
    my $status = $?;
    return undef if $status == -1 || ($status & 127) || ($status >> 8) != 0;

    my $max = 0;

    # stderr 出力から指定ラベルを全件抽出
    while ($output =~ /\Q$label\E=([0-9]+(?:\.[0-9]+)?)/g) {
        my $score = $1 + 0;
        $max = $score if $score > $max;
    }

    return $max;
}

# --- 動体検知: ディレクトリ内のTSを15秒間隔でサンプリング（240本）してシーン検知 ---
# 戻り値: 0=動体なし / 1=動体あり / undef=エラー
sub detect_motion {
    my ($dir) = @_;

    my @files = sort glob "${dir}/*.ts";
    return 0 unless @files;

    my $ver = get_ffmpeg_version();
    my $use_scdet = 0;
    if($ver ne "0.0.0") {
        my @v = split /\./, $ver;
        $use_scdet = 1 if ($v[0] > 4 || ($v[0] == 4 && $v[1] >= 3));
    }

    # 240本を等間隔サンプリング
    my $n = scalar @files;
    my $sample_count = ($n < 240) ? $n : 240;
    my @samples;
    for(my $i = 0; $i < $sample_count; $i++) {
        my $idx = int($i * $n / $sample_count);
        $idx = $n - 1 if $idx >= $n;
        push @samples, $files[$idx];
    }

    my ($filter, $label, $threshold) = $use_scdet
        ? (
            'scdet=threshold=1.0,metadata=mode=print',
            'lavfi.scd.score',
            1.0
          )
        : (
            "select='gt(scene,0.03)',metadata=mode=print",
            'lavfi.scene_score',
            0.03
          );

    for my $file (@samples) {
        my $score = get_max_score($file, $filter, $label);
        return undef unless defined $score;

        # 早期終了: 動体検出があれば即 1
        return 1 if $score > $threshold;
    }

    return 0;
}

# --- File::Find 用処理関数 ---
sub process {
    return unless $File::Find::name =~ /^.+\/(\d{8})\/(\d{2})$/;
    my $date = $1;
    my $hour = $2;
    my $dir  = $File::Find::name;

    # 24時間以上経過していない場合はスキップ
    return unless is_old_enough($dir);

    # 既に検知済みの場合はスキップ
    my $marker = "${dir}/.scdet_done";
    return if -f $marker;

    # 動体検知実行
    my $motion = detect_motion($dir);
    if(!defined $motion) {
        print "WARN: detect_motion error for ${dir}\n";
        return;
    }

    my $now_iso = strftime("%Y-%m-%dT%H:%M:%S", localtime);

    if($motion) {
        # 動体あり: マーカーを書き込み、ディレクトリを保持
        open(MARKER, "> ${marker}") or do {
            print "WARN: can't open ${marker}: $!\n";
            return;
        };
        print MARKER "MOTION time=${now_iso}\n";
        close(MARKER);
        print "INFO: motion detected, kept ${dir}\n";
    } else {
        # 動体なし: ディレクトリごと削除
        print "INFO: no motion, removing ${dir}\n";

        # マーカーも削除対象だが、ディレクトリごと消えるので不要
        my @to_remove = glob "${dir}/*";
        for my $f (@to_remove) {
            if(-d $f) {
                # 再帰的に削除（通常は無いが安全対策）
                my @subfiles = glob "${f}/*";
                unlink @subfiles;
                rmdir $f;
            } else {
                unlink $f;
            }
        }
        # 隠しファイル（.scdet_done 等）も削除
        my @hidden = glob "${dir}/.*";
        for my $f (@hidden) {
            my $base = basename($f);
            next if $base eq "." || $base eq "..";
            unlink $f;
        }
        rmdir $dir;

        # 削除ログに追記
        open(DEL_LOG, ">> ${DELETED_LOG}") or do {
            print "WARN: can't open ${DELETED_LOG}: $!\n";
            return;
        };
        print DEL_LOG "deleted ${dir} time=${now_iso}\n";
        close(DEL_LOG);
    }
}

# --- メイン: flock で排他ロック取得 ---
my $lock_file = "${video_root}/.remove.lock";
open(LOCK, "+< ${lock_file}") or do {
    print "WARN: can't open lock file ${lock_file}: $!\n";
    exit 1;
};
if(!flock(LOCK, LOCK_EX | LOCK_NB)) {
    print "INFO: previous remove.pl is still running, skipping.\n";
    close(LOCK);
    exit 0;
}

eval {
    find(\&process, $video_root);
};
if($@) {
    print "ERROR: $@\n";
}

close(LOCK);
exit 0;
