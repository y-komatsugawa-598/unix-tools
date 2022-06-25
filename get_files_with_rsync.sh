#!/bin/sh

### このスクリプトについて
# 概要     : 本番サーバ等からファイル取得を行う際に、リモート側への誤変更が発生しないように rsync を実行する。
#            コピーの挙動については環境変数で制御する。
# 使用方法 : 必須の環境変数(無いとエラー扱いになるもの)を埋めるとリモートホストとその同期元のパス指定による単純な実行となる。
#            同期されるファイルを指定したい場合は、 --files-from, --include, --exclude のオプションで調整する。
#            --files-from による指定を行った場合は --include, --exclude 関連の環境変数指定は無視される。
#            その他、転送前圧縮の有無・転送時帯域消費の上限指定を環境変数で設定できるので適宜利用する。
#
#            使用例としては、下記のようなシェルスクリプトで変数を設定して実行する。
#
#            #!/bin/sh
#
#             env REMOTE_HOST=dev.example.com \
#             REMOTE_BASE_DIR=/home/username \
#             BW_LIMIT=$(echo '1024 * 10' | bc) \
#             DO_COMPRESS=yes \
#             FILES_FROM_PATH='' \
#             INCLUDE_PATTERN='*/' \
#             EXCLUDE_PATTERN='*' \
#             sh /path/to/this/script
#
# 備考     : 本番サーバ等での事故的な変更を発生させないようにスクリプト化しているので、コピー先はハードコートしている。
#            不都合がある場合はスクリプトの定数設定部を書き換える。

### 定数設定
readonly LOCAL_DEST=~/rsync

### 環境変数バリデーション
[ -z "$REMOTE_HOST" ] && { echo error: variable \$REMOTE_HOST is empty.; exit 1; }
[ -z "$REMOTE_BASE_DIR" ] && { echo error: variable \$REMOTE_BASE_DIR is empty.; exit 1; }
[ -n "$FILES_FROM_PATH" -a ! -e $FILES_FROM_PATH ] && { echo error: the file $FILES_FROM_PATH not exists.; exit 1; }

### 変数初期化(環境変数バリデーションと合わせて変数を一覧できるように空文字列への初期化も記載する)
[ -z "$BW_LIMIT" ] && BW_LIMIT=1024 # KiB指定
[ -z "$DO_COMPRESS" ] && DO_COMPRESS=yes
[ -z "$FILES_FROM_PATH" ] && FILES_FROM_PATH=''
[ -z "$INCLUDE_PATTERN" ] && INCLUDE_PATTERN=''
[ -z "$EXCLUDE_PATTERN" ] && EXCLUDE_PATTERN=''

### オプション構築
OPTIONS="-av --delete --itemize-changes --bwlimit=${BW_LIMIT}KiB"

[ "$DO_COMPRESS" = 'yes' ] && OPTIONS="$OPTIONS --compress"

if [ -n "$FILES_FROM_PATH" ]; then
    OPTIONS=" $OPTIONS --files-from=$FILES_FROM_PATH"
else
    [ -n "$INCLUDE_PATTERN" ] && OPTIONS=" $OPTIONS --include=$INCLUDE_PATTERN"
    [ -n "$EXCLUDE_PATTERN" ] && OPTIONS=" $OPTIONS --exclude=$EXCLUDE_PATTERN"
fi

OPTIONS=" $OPTIONS $REMOTE_HOST:$REMOTE_BASE_DIR $LOCAL_DEST"

### 処理実行部
rsync --dry-run $OPTIONS

echo '==========================Start Confirmation================================'
echo The Above result of dry run will be comitted if you type '"yes"'.
echo Really execute rsync with bellow options ? '(yes/no)'
echo rsync $OPTIONS
echo -n 'Answer: '
read ANSWER
echo '===========================End Confirmation================================='

if [ "$ANSWER" = yes ]; then
    rsync $OPTIONS
else
    echo execution is canceled.
fi
