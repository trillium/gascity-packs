#!/bin/sh
# Stateful stand-in for `gc bd`, used by the merge-gate and resolve tests.
# It is not a model of real bd: it implements only the calls the pack scripts
# make, with the argument shapes the scripts use. State lives in $FAKE_DIR.
#   beads.json - array of beads {id,title,status,labels,metadata,comments}
set -eu
[ "$1" = bd ]
shift
sub=$1
shift
DB="$FAKE_DIR/beads.json"
[ -f "$DB" ] || echo '[]' >"$DB"

save() { jq "$@" "$DB" >"$DB.new" && mv "$DB.new" "$DB"; }

# The scripts put the rig flag right after the subcommand; drop it.
case "${1:-}" in --rig=*) shift ;; esac

case "$sub" in
    list)
        all=0; labels='[]'
        while [ $# -gt 0 ]; do
            case "$1" in
                --label) labels=$(printf '%s' "$labels" | jq -c --arg l "$2" '. + [$l]'); shift 2 ;;
                --all) all=1; shift ;;
                --json) shift ;;
                --limit) shift 2 ;;
                *) exit 64 ;;
            esac
        done
        jq -c --argjson labels "$labels" --argjson all "$all" '
            map(select(($all == 1 or .status != "closed")
                and (. as $b | $labels | all(. as $l | ($b.labels | index($l)) != null))))' "$DB"
        ;;
    show)
        id=$1
        jq -ce --arg id "$id" 'map(select(.id == $id))' "$DB" | jq -e 'length == 1' >/dev/null || exit 1
        jq -c --arg id "$id" 'map(select(.id == $id))' "$DB"
        ;;
    create)
        title=$1; shift
        labels=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --labels) labels=$2; shift 2 ;;
                --description|--deps) shift 2 ;;
                --silent) shift ;;
                *) exit 64 ;;
            esac
        done
        n=$(jq 'length + 1' "$DB")
        id="fake-$n"
        save --arg id "$id" --arg t "$title" --arg l "$labels" \
            '. + [{id: $id, title: $t, status: "open", labels: ($l | split(",")), metadata: {}, comments: []}]'
        echo "$id"
        ;;
    update)
        id=$1; shift
        while [ $# -gt 0 ]; do
            case "$1" in
                --set-metadata)
                    k=${2%%=*}; v=${2#*=}
                    save --arg id "$id" --arg k "$k" --arg v "$v" \
                        'map(if .id == $id then .metadata[$k] = $v else . end)'
                    shift 2 ;;
                *) exit 64 ;;
            esac
        done
        ;;
    comment)
        id=$1
        save --arg id "$id" --arg t "$2" 'map(if .id == $id then .comments += [{text: $t}] else . end)'
        ;;
    comments)
        jq -c --arg id "$1" 'map(select(.id == $id)) | .[0].comments // []' "$DB"
        ;;
    close)
        id=$1
        save --arg id "$id" 'map(if .id == $id then .status = "closed" else . end)'
        ;;
    *) exit 64 ;;
esac
