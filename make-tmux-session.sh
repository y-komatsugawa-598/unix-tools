#!/bin/sh

### このスクリプトについて
# 概要     : tmuxで決まったウィンドウ構成を再現するためのシェルスクリプトを出力する
# 使用方法 : 下記のような形式でウィンドウ構成を記載したファイルを作成し、このスクリプトに標準入力で与える。
#
#                {セッション名}:{番号}:{ウィンドウでの実行コマンド}
#
#            例えば下記のようなファイルとなる。
#
#                main:1:'sleep 3 && emacsclient -nw'
#                main:2:
#                admin-shell:1:~/work/dev-admin/get-shell
#                service:1:~/scripts/kick-ssh-agent
#                service:2:~/scripts/kick-emacs-daemon
#
#            実行結果として出力される tmux コマンドを sh で実行するとウィンドウ構成を再現したtmuxセッションが立ち上がる。
# 備考     : エラーハンドル等はしていないので、入力が正しいファイルフォーマットであることを確認してから利用する。

CONF="$(cat)"

SESSIONS=$(echo "$CONF" | cut -d: -f1 | sort | uniq)
for SESSION in $SESSIONS; do
    FIRST_WINDOW_COMMAND="$(echo "$CONF" | grep $SESSION:1 | cut -d: -f3)"
    echo tmux new-session -d -s $SESSION $FIRST_WINDOW_COMMAND

    for CURRENT_LINE in $(echo "$CONF" | grep $SESSION: | grep -v $SESSION:1); do
        WINDOW_NUM=$(echo $CURRENT_LINE | cut -d: -f2)
        CURRENT_WINDOW_COMMAND=$(echo $CURRENT_LINE | cut -d: -f3)
        echo tmux new-window -t $SESSION:$WINDOW_NUM $CURRENT_WINDOW_COMMAND
    done

done
