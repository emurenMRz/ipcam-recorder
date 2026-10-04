#!/usr/bin/perl
#
# ストレージの空き容量と ffmpeg の動作状況を status.json に書き出す。
# 毎分 crontab で実行する。画面(index.html / stream.js)が1分間隔でポーリングして表示する。
#
#   * * * * * /path/to/core_service/status.pl
#
# このスクリプトは「事実」を記録するだけで、削除も再起動も行わない。
# 警告の判定(閾値)はフロントエンド側で行う。
#
# 出力先: ${web_root}/status.json  (nginx からは /status.json として配信される)
#
# {
#   "version": 1,
#   "generated_at": 1759550000,            # このJSONを作成した時刻(UNIX秒, サーバ時計)
#   "disk": {                              # 録画先(video/)があるファイルシステム
#     "total_bytes": ..., "used_bytes": ..., "free_bytes": ..., "free_percent": 12.3
#   },
#   "ffmpeg": {
#     "process_alive": true,               # PIDファイルのプロセスがffmpegか。PIDファイルが無ければ null
#     "playlist_updated_at": 1759549998    # ライブ用 playlist.m3u8 の更新時刻。無ければ null
#   }
# }

use strict;
use warnings;
use JSON::PP;

my $web_root   = "/var/www/stream_root";
my $video_root = "${web_root}/video";

# stream.sh と同じ既定の状態ディレクトリ(PIDファイルの場所)
my $home      = $ENV{HOME} // "";
my $state_dir = $ENV{IPCAM_STATE_DIR} || "${home}/.local/state/ipcam-recorder";
my $pid_file  = "${state_dir}/ffmpeg.pid";

# --- ストレージ: df -Pk の2行目を読む(一般ユーザーが実際に使える容量で計算する) ---
sub get_disk {
    open(my $df, '-|', 'df', '-Pk', $video_root) or return undef;
    my @lines = <$df>;
    close($df);
    return undef unless @lines >= 2;
    # Filesystem 1024-blocks Used Available Capacity Mounted-on
    my @f = split ' ', $lines[1];
    return undef unless @f >= 4 && $f[1] =~ /^\d+$/ && $f[2] =~ /^\d+$/ && $f[3] =~ /^\d+$/;
    my ($total, $used, $free) = map { $_ * 1024 } @f[1, 2, 3];
    my $usable = $used + $free;
    my $percent = $usable > 0 ? sprintf("%.1f", $free * 100 / $usable) + 0 : 0;
    return {
        total_bytes  => $total + 0,
        used_bytes   => $used + 0,
        free_bytes   => $free + 0,
        free_percent => $percent,
    };
}

# --- ffmpeg: PIDファイルのプロセスが本当に ffmpeg か(PID使い回し対策で cmdline を確認) ---
sub is_process_alive {
    open(my $fh, '<', $pid_file) or return undef;     # PIDファイル無し = 判定不能
    my $pid = <$fh>;
    close($fh);
    return JSON::PP::false unless defined $pid && $pid =~ /^\s*(\d+)\s*$/;
    $pid = $1;
    open(my $cmd, '<', "/proc/${pid}/cmdline") or return JSON::PP::false;
    my $cmdline = do { local $/; <$cmd> };
    close($cmd);
    return (defined $cmdline && $cmdline =~ /ffmpeg/) ? JSON::PP::true : JSON::PP::false;
}

# --- ライブ用プレイリストの更新時刻(ffmpegが数秒ごとに更新する。止まれば更新も止まる) ---
sub get_playlist_mtime {
    my @st = stat("${video_root}/playlist.m3u8");
    return @st ? $st[9] + 0 : undef;
}

my $status = {
    version      => 1,
    generated_at => time() + 0,
    disk         => get_disk(),
    ffmpeg       => {
        process_alive       => is_process_alive(),
        playlist_updated_at => get_playlist_mtime(),
    },
};
my $out = JSON::PP->new->canonical->encode($status);

# 一時ファイルに書いてから rename する。
# ディスクが満杯で書き込みに失敗しても、直前の status.json はそのまま残る
# (その場合 generated_at が更新されないので、画面側で「状態が古い」と判定できる)。
my $json_file = "${web_root}/status.json";
my $json_tmp  = "${json_file}.tmp";
open(my $out_fh, '>', $json_tmp) or die "Can't open file \"${json_tmp}\": $!\n";
print $out_fh $out or do { unlink $json_tmp; die "Can't write file \"${json_tmp}\": $!\n" };
close($out_fh) or do { unlink $json_tmp; die "Can't write file \"${json_tmp}\": $!\n" };
rename($json_tmp, $json_file) or do { unlink $json_tmp; die "Can't rename \"${json_tmp}\" to \"${json_file}\": $!\n" };
