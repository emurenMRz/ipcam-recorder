# ipcam-recorder

[防犯カメラ映像の配信・録画サーバーの構築](https://www.mrz-net.org/_tdiary/index.rb/article/20201029p1)で作成したコードの保守リポジトリです。

> ブログ記事の内容は開発当初のものです。現在のセットアップ手順と仕様は、このリポジトリの内容を参照してください。

## REQUIRED

```sh
$ lsb_release -a
No LSB modules are available.
Distributor ID: Debian
Description:    Debian GNU/Linux 12 (bookworm)
Release:        12
Codename:       bookworm
$ uname -a
Linux raspberrypi 6.12.109+rpt-rpi-v8 #1 SMP PREEMPT Debian 1:6.12.109-1+rpt1 (2026-09-11) aarch64 GNU/Linux
```

```sh
$ nginx -v
nginx version: nginx/1.22.1
```

```sh
$ ffmpeg -version
ffmpeg version 5.1.9-0+deb12u1+rpt1 Copyright (c) 2000-2026 the FFmpeg developers
built with gcc 12 (Debian 12.2.0-14+deb12u1)
configuration: --prefix=/usr --extra-version=0+deb12u1+rpt1 --toolchain=hardened --incdir=/usr/include/aarch64-linux-gnu --enable-gpl --disable-stripping --disable-mmal --enable-gnutls --enable-ladspa --enable-libaom --enable-libass --enable-libbluray --enable-libbs2b --enable-libcaca --enable-libcdio --enable-libcodec2 --enable-libdav1d --enable-libflite --enable-libfontconfig --enable-libfreetype --enable-libfribidi --enable-libglslang --enable-libgme --enable-libgsm --enable-libjack --enable-libmp3lame --enable-libmysofa --enable-libopenjpeg --enable-libopenmpt --enable-libopus --enable-libpulse --enable-librabbitmq --enable-librist --enable-librubberband --enable-libshine --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libsrt --enable-libssh --enable-libsvtav1 --enable-libtheora --enable-libtwolame --enable-libvidstab --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libx265 --enable-libxml2 --enable-libxvid --enable-libzimg --enable-libzmq --enable-libzvbi --enable-lv2 --enable-omx --enable-openal --enable-opencl --enable-opengl --enable-sand --enable-sdl2 --disable-sndio --enable-libjxl --enable-neon --enable-v4l2-request --enable-libudev --enable-epoxy --libdir=/usr/lib/aarch64-linux-gnu --arch=arm64 --enable-pocketsphinx --enable-librsvg --enable-libdc1394 --enable-libdrm --enable-vout-drm --enable-libiec61883 --enable-chromaprint --enable-frei0r --enable-libx264 --enable-libplacebo --enable-librav1e --enable-shared
libavutil      57. 28.100 / 57. 28.100
libavcodec     59. 37.100 / 59. 37.100
libavformat    59. 27.100 / 59. 27.100
libavdevice    59.  7.100 / 59.  7.100
libavfilter     8. 44.100 /  8. 44.100
libswscale      6.  7.100 /  6.  7.100
libswresample   4.  7.100 /  4.  7.100
libpostproc    56.  6.100 / 56.  6.100
```

```sh
 $ perl -v

This is perl 5, version 36, subversion 0 (v5.36.0) built for aarch64-linux-gnu-thread-multi
(with 60 registered patches, see perl -V for more detail)

Copyright 1987-2022, Larry Wall

Perl may be copied only under the terms of either the Artistic License or the
GNU General Public License, which may be found in the Perl 5 source kit.

Complete documentation for Perl, including FAQ lists, should be found on
this system using "man perl" or "perldoc perl".  If you have access to the
Internet, point your browser at https://www.perl.org/, the Perl Home Page.

```

## START IPCAM RECORDING

認証情報は環境変数として指定する。`TENVIS JPT3815W`のIPアドレスやアクセス用のユーザー名・パスワードを設定する。

- `IPCAM_HOST` — カメラのIPアドレス:port
- `IPCAM_USER` — カメラのユーザー名
- `IPCAM_PWD` — カメラのパスワード

スクリプトを実行するとffmpegがhls形式で動画を出力する。

```sh
$ export IPCAM_HOST=[your IPCamera ip address:port]
$ export IPCAM_USER=[your IPCamera user id]
$ export IPCAM_PWD=[your IPCamera user password]
$ sh ${REPOSITORY_ROOT}/core_service/stream.sh
```

ffmpegのPIDとログは `${IPCAM_STATE_DIR}`（既定: `~/.local/state/ipcam-recorder`、パーミッション700）の `ffmpeg.pid` / `ffmpeg.log` に保存される。
ログにはカメラの認証情報を含むURLが出力され得るため、Webから配信される `video/` 配下には置かない。
再起動時は、PIDファイルのプロセスが ffmpeg であることを確認した上で停止してから新規起動する。

## SETUP WEB UI

```sh
$ sudo apt install nginx
$ sudo mv ${REPOSITORY_ROOT}/nginx/stream.conf /etc/nginx/sites-available/stream.conf
$ sudo ln -s /etc/nginx/sites-available/stream.conf /etc/nginx/sites-enable/stream.conf
$ sudo /etc/init.d/nginx start
```

## RECORDING HISTORY

```sh
$ chmod 700 ${REPOSITORY_ROOT}/core_service/remove.pl
$ chmod 700 ${REPOSITORY_ROOT}/core_service/status.pl
$ chmod 700 ${REPOSITORY_ROOT}/core_service/stream.pl
```

```crontab
0 * * * * ${REPOSITORY_ROOT}/core_service/remove.pl
* * * * * ${REPOSITORY_ROOT}/core_service/status.pl
* * * * * ${REPOSITORY_ROOT}/core_service/stream.pl
```

## MOTION DETECTION CLEANUP

`remove.pl` は毎時実行され、24時間以上経過した1時間ディレクトリ（`YYYYMMDD/HH/`）について、ffmpeg のシーン検知で動体が検出されなければディレクトリごと削除する。

- 動体検知: ディレクトリ内のTSを15秒間隔でサンプリング（最大240本）し、シーン変更を検知
- 検知済みディレクトリは `.scdet_done` マーカーで管理され、再実行しない
- 削除ログは `/var/www/stream_root/video/.deleted.log` に記録
- 並行実行は `/var/www/stream_root/video/.remove.lock` の `flock` で防止

## STATUS MONITORING

ストレージの空き容量と ffmpeg の動作状況を画面に表示する。**容量不足でも、自動削除・ffmpeg の自動再起動は行わない**。気づけるようにするだけで、対処は人が行う。

- `status.pl` が毎分 `/var/www/stream_root/status.json` を書き出す（一時ファイルへ書いてから `rename`。ディスクが満杯で書けない場合は直前の内容が残る）。
- `status.json` は nginx から `/status.json` として配信される（キャッシュ無効）。
- `index.html`（`stream.js`）が1分間隔のポーリングで `status.json` を取得して表示する。判定の閾値は `stream.js` の先頭にある。

```json
{
  "version": 1,
  "generated_at": 1759550000,
  "disk": { "total_bytes": 0, "used_bytes": 0, "free_bytes": 0, "free_percent": 12.3 },
  "ffmpeg": { "process_alive": true, "playlist_updated_at": 1759549998 }
}
```

| 項目 | 意味 |
| --- | --- |
| `generated_at` | JSONの作成時刻（UNIX秒）。画面側でサーバのDateヘッダと比べ、古ければ「状態が更新されていない」と警告する |
| `disk` | 録画先（`video/`）があるファイルシステムの容量。`free_percent` は一般ユーザーが使える容量に対する空きの割合 |
| `ffmpeg.process_alive` | `${IPCAM_STATE_DIR}/ffmpeg.pid` のプロセスが ffmpeg か。PIDファイルが無ければ `null` |
| `ffmpeg.playlist_updated_at` | ライブ用 `video/playlist.m3u8` の更新時刻。ffmpeg が止まる、または映像が来なくなると更新が止まる。ファイルが無ければ `null` |

`status.pl` は `stream.sh` と同じ `IPCAM_STATE_DIR`（既定 `~/.local/state/ipcam-recorder`）を参照する。`stream.sh` を既定以外の `IPCAM_STATE_DIR` で起動している場合は、cron 側にも同じ環境変数を設定すること。
