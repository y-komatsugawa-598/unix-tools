#!/bin/sh

### このスクリプトについて
# 概要     : 帯域制限や圧縮、暗号化などをオプションで設定してリモートのtarアーカイブを取得するスクリプト
# 使用方法 : 必須の環境変数(無いとエラー扱いになるもの)を埋めて実行するとtarアーカイブを標準出力する。
#            オプションでのフィルターコマンド指定がない場合デフォルト値のコマンドで圧縮・帯域制限・暗号化を行う。
#            RES 文字列を第一引数に与えた場合はローカルでの暗号化・圧縮を解除したファイルを標準出力する
#            リストア時には環境変数はそのままに RES コマンドを与えればリモートで展開可能なファイルストリームを得られる
#
#            使用例としては、下記のようなシェルスクリプトで変数を設定して実行する。
#
#            #!/bin/sh
#
#            SUB_COMMAND=$1
#
#            export SSH_USER=store; export SSH_USER
#            export SSH_PORT=22; export SSH_PORT
#            export ARCHIVE_TARGETS=.; export ARCHIVE_TARGETS
#            export ARCHIVE_EXCLUDE_LIST='work_server.tar.gz'; export ARCHIVE_EXCLUDE_LIST
#            export DO_BW_LIMIT=yes; export DO_BW_LIMIT
#            export BW_LIMIT=$(echo '8 * 1024' | bc); export BW_LIMIT
#            export DO_COMPRESS=yes; export DO_COMPRESS
#            export DO_ENCRYPT=yes; export DO_ENCRYPT
#            export ENCRYPTION_KEY=$(cat $GRAVEYARD_ROOT/vault_secret); export ENCRYPTION_KEY
#            export REMOTE_HOST=graveyard-storage; export REMOTE_HOST
#            export REMOTE_BASE_DIR=/home/store/dist; export REMOTE_BASE_DIR
#            export DO_LOCAL_COMPRESS=''; export DO_LOCAL_COMPRESS
#
#            if [ -n "$SUB_COMMAND" -a "$SUB_COMMAND" = RES ]; then
#                sh /path/to/this/script.sh $SUB_COMMAND
#            else
#                sh /path/to/this/script.sh \
#                   > /some/backup/dir/test_archive.tar.gz
#            fi
#
# 適用条件 : * リモートへのSSH接続が可能なこと
#            * リモート・ローカルでオプション指定に応じた依存コマンドが使用可能なこと
#                * リモート: tar, gzip, pv がインストールされていること(tar以外はオプションによっては不要)
#                * ローカル: gpg, gzip がインストールされていること(それぞれオプションによっては不要)
# 備考     : RES コマンド付与時の標準出力はリモートでの加工分は復元しない、必要に応じて本スクリプト外で復元する
#            例(リストア先にgzipが期待できる)  : /path/to/this/script.sh RES < archive.tar.gz | ssh remote-host 'gunzip | tar xf -'
#            例(リストア先にgzipが期待できない): /path/to/this/script.sh RES < archive.tar.gz | gunzip | ssh remote-host 'tar xf -'

### 変数初期化(変数を一覧できるようにバリデーション済み変数の初期化や空文字列への初期化も記載する)
# 圧縮・帯域制限等の純粋なフィルターコマンドは交換可能なのでコマンド自体を変数で指定する方針とする

[ -z "$REMOTE_HOST" ] && REMOTE_HOST='' # 必須環境変数
[ -z "$REMOTE_BASE_DIR" ] && REMOTE_BASE_DIR='' # 必須環境変数
[ -z "$ARCHIVE_TARGETS" ] && ARCHIVE_TARGETS='' # 必須環境変数(複数の場合改行区切りを想定する)
[ -z "$DO_BW_LIMIT" ] && DO_BW_LIMIT=yes
[ -z "$BW_LIMIT" ] && BW_LIMIT=1024 # KiB指定
[ -z "$DO_COMPRESS" ] && DO_COMPRESS=yes
[ -z "$DO_ENCRYPT" ] && DO_ENCRYPT=yes
[ -z "$ENCRYPTION_KEY" ] && ENCRYPTION_KEY=''
[ -z "$ARCHIVE_EXCLUDE_LIST" ] && ARCHIVE_EXCLUDE_LIST='' # 改行区切りのみを想定する
[ -z "$DO_LOCAL_COMPRESS" ] && DO_LOCAL_COMPRESS=''

### 環境変数バリデーション

[ -z "$REMOTE_HOST" ] && { echo error: variable \$REMOTE_HOST is empty.; exit 1; }
[ -z "$REMOTE_BASE_DIR" ] && { echo error: variable \$REMOTE_BASE_DIR is empty.; exit 1; }
[ -z "$ARCHIVE_TARGETS" ] && { echo error: variable \$BACKUP_TARGETS is empty.; exit 1; }
[ -n "$DO_ENCRYPT" -a -z "$ENCRYPTION_KEY" ] && { echo error: variable \$ENCRYPTION_KEY is empty.; exit 1; }

### オプション構築

SSH_OPTIONS=''
[ -n "$SSH_USER" ] && SSH_OPTIONS="$SSH_OPTIONS -l $SSH_USER"
[ -n "$SSH_PORT" ] && SSH_OPTIONS="$SSH_OPTIONS -p $SSH_PORT"

TAR_OPTIONS="cf -"

if [ -n "$ARCHIVE_EXCLUDE_LIST" ]; then
    for ARCHIVE_EXCLUDE in $ARCHIVE_EXCLUDE_LIST; do
        TAR_OPTIONS="$TAR_OPTIONS --exclude=$ARCHIVE_EXCLUDE"
    done
fi

for ARCHIVE_TARGET in $ARCHIVE_TARGETS; do
    TAR_OPTIONS="$TAR_OPTIONS $ARCHIVE_TARGET"
done

### パイプライン構築

# 標準入力: なし
# 標準出力: 環境変数での指定ディレクトリをアーカイブしたファイル
# 備考    : 環境変数による指定ででgzipによる圧縮とpvによる帯域消費の制限が可能
REMOTE_PIPELINE="tar $TAR_OPTIONS"
[ "$DO_COMPRESS" = yes ] && REMOTE_PIPELINE="$REMOTE_PIPELINE | gzip"
[ "$DO_BW_LIMIT" = yes ] && REMOTE_PIPELINE="$REMOTE_PIPELINE | pv --rate-limit ${BW_LIMIT}K"

# 標準入力: ファイル(一般のデータ)
# 標準出力: 入力ファイルに対して環境変数指定のフィルター(暗号化, gzip圧縮)をかけたファイル
# 備考    : 環境変数による指定がなかった場合入力ファイルをそのまま出力する
LOCAL_PIPELINE=cat
[ "$DO_LOCAL_COMPRESS" = yes ] && LOCAL_PIPELINE="$LOCAL_PIPELINE | gzip"
[ "$DO_ENCRYPT" = yes ] && LOCAL_PIPELINE="$LOCAL_PIPELINE | gpg -c --batch --no-keyring --passphrase $ENCRYPTION_KEY"

# 標準入力: LOCAL_PIPELINE処理済みファイル
# 標準出力: LOCAL_PIPELINE処理前ファイル
# 備考    : LOCAL_PIPELINE処理の逆フィルターとして元のファイルストリームを再現したい場合に用いる
REVERSE_PIPELINE=cat
[ "$DO_ENCRYPT" = yes ] && REVERSE_PIPELINE="$REVERSE_PIPELINE | gpg -d --batch --no-keyring --passphrase $ENCRYPTION_KEY"
[ "$DO_LOCAL_COMPRESS" = yes ] && REVERSE_PIPELINE="$REVERSE_PIPELINE | gunzip"

### 処理実行部

if [ "$1" = RES ]; then
    # RES コマンドが与えられた場合作成済みアーカイブを標準入力としてLOCAL_PIPELINE処理前のストリームを復元する
    eval $REVERSE_PIPELINE
else
    # デフォルトの挙動としてリモートの指定ディレクトリをアーカイブし暗号化・圧縮の上で標準出力する
    ssh $SSH_OPTIONS $REMOTE_HOST "cd $REMOTE_BASE_DIR && $REMOTE_PIPELINE" | eval $LOCAL_PIPELINE
fi
