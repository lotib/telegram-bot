#!/bin/bash
TOKEN=${TOKEN:-}
CHAT_ID=${CHAT_ID:-}
POLLING_TIMEOUT=5
declare -A COMMANDS

# Register your commands here
COMMANDS["uptime"]="uptime"
COMMANDS["disk"]="df -h"
COMMANDS["who"]="who -a"

function usage()
{
    echo "$0 permits to send message and notifications.
    In order to use this script, you should provide this variables :
     - TOKEN        (mandatory)
     - CHAT_ID      (optionnal, can be dynamically retrieved from last update)

    TOKEN=\"XXX:YYY\" [CHAT_ID="ZZZ"] $0 send \"Hi from bot !\"

    $0 update offset
    $0 update -1
        - retrieves the last update

    $0 loop
        - infinite loop waiting for commands from telegram

    $0 send message_text

    $0 delete message_id

    $0 photo photo_path

    https://core.telegram.org/bots/api
"
    exit
}

# retrieves all updates from server
# $1: offset can be specified to limit results
function get_update()
{
    offset=${1:-}

    curl -s -X POST "https://api.telegram.org/bot$TOKEN/getUpdates" ${offset:+-d offset=${offset}}
}

# retrieve the latest chat id from update, if it exists
function get_latest_chat_id()
{
    local latest_chat_id=$(get_update -1 | jq ".result[-1].message.chat.id")
    if [ $? -eq 0 ] ; then
        echo ${latest_chat_id}
    fi
}

# send text from bot to user
# $1 : text (max 4096)
# TODO split message > 4096 characters
function send_message()
{
    local text="${1}"

    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d text="${text}"
}

# Sends a photo
# $1 local photo path
function send_photo()
{
    local photo_path="${2}"

    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendPhoto" -F chat_id="$CHAT_ID" -F photo="@${photo_path}"
}

# deletes a message from history
# $1 message id of the message to delete
function delete_message()
{
    local message_id=${1}

    curl -s -X POST "https://api.telegram.org/bot$TOKEN/deleteMessage" \
        -d chat_id="${CHAT_ID}" \
        -d message_id="${message_id}"
}

# infinite loop waiting commands to execute
# commands are registered in COMMANDS variable
function loop()
{
  local last_message_id=0
  local started=0

  while true
  do
    local message=$(get_update -1)
    if [ $? -eq 0 ] ; then
        local message_id=$(echo $message | jq ".result[-1].message.message_id")
        # get message text removing double quote
        local message_text=$(echo $message | jq ".result[-1].message.text" | awk -F',' '{gsub(/"/, "", $1); print $1}')
        if [ ${last_message_id} -lt ${message_id} ] ; then
            last_message_id=${message_id}

            # Started is used to not execute last command when script is started
            if [ ${started} -eq 0 ] ; then
                started=1
            else
                # looks for registered commands
                for cmd in ${!COMMANDS[@]}
                do
                    echo $cmd
                    if [ "${cmd}" == "${message_text}" ] ; then
                        # echo "executing ${COMMANDS["${message_text}"]}"
                        send_message "$(${COMMANDS["${message_text}"]})" &
                    fi
                done
            fi
        fi
    fi
    sleep ${POLLING_TIMEOUT}
  done

}

# main

if [ "${TOKEN}" == "" ] ; then
    echo "you must provide a TOKEN"
    exit 1
fi

if [ "$CHAT_ID" == "" ] ; then
    # echo "No chat id provided, trying to get one ..."
    CHAT_ID=$(get_latest_chat_id)
    if [ "$CHAT_ID" == "" ] ; then
        echo "you must provide a CHAT_ID, or you should talk to your bot"
        exit 1
    fi
fi

if [ $# == 0 ] ; then
    usage
fi

for i in $@ ; do
    case "${1}" in
    "delete")
        delete_message $2
        shift
        shift
     ;;
     "send")
        send_message $2
        shift
        shift
    ;;
    "photo")
        send_photo $2
        shift
        shift
    ;;
    "update")
        get_update $2
        exit $?
    ;;
    "loop")
        loop
        exit $?
    ;;
    *)
        send_$1
        if [ $? -ne 0 ] ; then
            usage
        fi
     ;;
     esac
done

