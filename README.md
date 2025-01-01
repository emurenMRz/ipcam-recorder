# ipcam-recorder

[防犯カメラ映像の配信・録画サーバーの構築](https://www.mrz-net.org/_tdiary/index.rb/article/20201029p1)で作成したコードの保守リポジトリです。

## REQUIRED

```sh
$ lsb_release -a
No LSB modules are available.
Distributor ID: Raspbian
Description:    Raspbian GNU/Linux 10 (buster)
Release:        10
Codename:       buster
pi@raspberrypi:~ $ uname -a
Linux raspberrypi 5.4.51-v7l+ #1333 SMP Mon Aug 10 16:51:40 BST 2020 armv7l GNU/Linux
```

```sh
$ nginx -v
nginx version: nginx/1.14.2
```

```sh
$ ffmpeg -version
ffmpeg version 4.1.6-1~deb10u1+rpt1 Copyright (c) 2000-2020 the FFmpeg developers
built with gcc 8 (Raspbian 8.3.0-6+rpi1)
configuration: --prefix=/usr --extra-version='1~deb10u1+rpt1' --toolchain=hardened --incdir=/usr/include/arm-linux-gnueabihf --enable-gpl --disable-stripping --enable-avresample --disable-filter=resample --enable-avisynth --enable-gnutls --enable-ladspa --enable-libaom --enable-libass --enable-libbluray --enable-libbs2b --enable-libcaca --enable-libcdio --enable-libcodec2 --enable-libflite --enable-libfontconfig --enable-libfreetype --enable-libfribidi --enable-libgme --enable-libgsm --enable-libjack --enable-libmp3lame --enable-libmysofa --enable-libopenjpeg --enable-libopenmpt --enable-libopus --enable-libpulse --enable-librsvg --enable-librubberband --enable-libshine --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libssh --enable-libtheora --enable-libtwolame --enable-libvidstab --enable-libvorbis --enable-libvpx --enable-libwavpack --enable-libwebp --enable-libx265 --enable-libxml2 --enable-libxvid --enable-libzmq --enable-libzvbi --enable-lv2 --enable-omx --enable-openal --enable-opengl --enable-sdl2 --enable-omx-rpi --enable-mmal --enable-neon --enable-rpi --enable-libdc1394 --enable-libdrm --enable-libiec61883 --enable-chromaprint --enable-frei0r --enable-libx264 --enable-shared --libdir=/usr/lib/arm-linux-gnueabihf --cpu=arm1176jzf-s --arch=arm
libavutil      56. 22.100 / 56. 22.100
libavcodec     58. 35.100 / 58. 35.100
libavformat    58. 20.100 / 58. 20.100
libavdevice    58.  5.100 / 58.  5.100
libavfilter     7. 40.101 /  7. 40.101
libavresample   4.  0.  0 /  4.  0.  0
libswscale      5.  3.100 /  5.  3.100
libswresample   3.  3.100 /  3.  3.100
libpostproc    55.  3.100 / 55.  3.100
```

```sh
 $ perl -v

This is perl 5, version 28, subversion 1 (v5.28.1) built for arm-linux-gnueabihf-thread-multi-64int
(with 61 registered patches, see perl -V for more detail)

Copyright 1987-2018, Larry Wall

Perl may be copied only under the terms of either the Artistic License or the
GNU General Public License, which may be found in the Perl 5 source kit.

Complete documentation for Perl, including FAQ lists, should be found on
this system using "man perl" or "perldoc perl".  If you have access to the
Internet, point your browser at http://www.perl.org/, the Perl Home Page.
```

## START IPCAM RECORDING

`${REPOSITORY_ROOT}/core_service/stream.sh`を開いて、以下の変数に`TENVIS JPT3815W`のIPアドレスやアクセス用のユーザー名・パスワードを設定する。

```sh
HOST=[your IPCamera ip address:port]
USER_ID=[your IPCamera user id]
USER_PWD=[your IPCamera user password]
```

スクリプトを実行するとffmpegがhls形式で動画を出力する。

```sh
$ sh ${REPOSITORY_ROOT}/core_service/stream.sh
```

## SETUP WEB UI

```sh
$ sudo apt install nginx
$ sudo mv ${REPOSITORY_ROOT}/nginx/stream.conf /etc/nginx/sites-available/stream.conf
$ sudo ln -s /etc/nginx/sites-available/stream.conf /etc/nginx/sites-enable/stream.conf
$ sudo /etc/init.d/nginx start
```

## RECORDING HISTORY

```sh
$ chmod 700 ${REPOSITORY_ROOT}/core_service/stream.pl
```

```crontab
1 * * * * ${REPOSITORY_ROOT}/core_service/stream.pl
```
