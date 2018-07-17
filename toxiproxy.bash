#!/usr/bin/env bash

set -o errexit
set -o nounset

readonly debug='false'
readonly curdir="$(realpath "$PWD")"

declare -i toxiproxy_server_pid=0
declare -i perftest_pid=0

function command_exists
{
    command -v "$1" > /dev/null 2>&1
}

function make_temp_dir
{
    local template="${1:-tmp-$$}"
    if [[ $template != *XXXXXX ]]
    then
        template="$template.XXXXXX"
    fi
    mktemp -d -t "$template"
}

function make_temp_file
{
    local template="${1:-tmp-$$}"
    if [[ $template != *XXXXXX ]]
    then
        template="$template.XXXXXX"
    fi
    mktemp -t "$template"
}

function now
{
    date '+%Y-%m-%d %H:%M:%S'
}

function pwarn
{
    echo "$(now) [warning]: $*" 1>&2
}

function perr
{
    echo "$(now) [error]: $*" 1>&2
}

function pinfo
{
    echo "$(now) [info]: $*"
}

function pinfo_n
{
    echo -n "$(now) [info]: $*"
}

function pdebug
{
    if [[ $debug == 'true' ]]
    then
        echo "$(now) [debug]: $*"
    fi
}

function errexit
{
    perr "$@"
    exit 1
}

function onexit
{
    set +o errexit
    if (( toxiproxy_server_pid > 0 ))
    then
        kill "$toxiproxy_server_pid"
    fi
    if (( perftest_pid > 0 ))
    then
        kill "$perftest_pid"
    fi
    set -o errexit
    return 0
}

trap onexit EXIT

if ! command_exists curl
then
    errexit "please ensure curl is in PATH"
fi
if ! command_exists jq
then
    errexit "please ensure jq is in PATH"
fi

readonly perftest="$curdir/rabbitmq-perf-test-2.2.0.M1/bin/runjava com.rabbitmq.perf.PerfTest"
readonly toxiproxy_cli="$curdir/toxiproxy-cli-linux-amd64"
readonly toxiproxy_server="$curdir/toxiproxy-server-linux-amd64"

if [[ -x $toxiproxy_cli && -x $toxiproxy_server ]]
then
    pinfo "toxiproxy cli and server exist in $curdir"
else
    for toxibin in toxiproxy-cli-linux-amd64 toxiproxy-server-linux-amd64
    do
        pinfo_n "downloading $toxibin..."
        browser_download_url="$(curl -s https://api.github.com/repos/Shopify/toxiproxy/releases/latest | jq -r ".assets[] | select(.name == \"toxiproxy-cli-linux-amd64\") | .browser_download_url")"
        curl -sLO "$browser_download_url"
        chmod 755 "$toxibin"
        echo 'DONE'
    done
fi

"$toxiproxy_server" --config "$curdir/toxiproxy.json" &
toxiproxy_server_pid="$!"
sleep 5

# URI='amqp://guest:guest@localhost:55672' AUTO_DELETE='true' CONSUMER_LATENCY='600' CONSUMERS='500' EXCLUSIVE='true' HEARTBEAT_SENDER_THREADS='10' INTERVAL='30' MSG_SIZE='1000' NIO_THREAD_POOL='20' NIO_THREADS='10' PRODUCER_RANDOM_START_DELAY='60' PRODUCER_SCHEDULER_THREADS='50' PRODUCERS='500' PUBLISHING_INTERVAL='60' QUEUE_PATTERN='exclusive%d' QUEUE_PATTERN_FROM='1' QUEUE_PATTERN_TO='500' $perftest &
URI='amqp://guest:guest@localhost:55672' CONSUMERS='1' EXCLUSIVE='true' INTERVAL='10' MSG_SIZE='1024' PRODUCERS='1' PUBLISHING_INTERVAL='10' QUEUE_PATTERN='exclusive%d' QUEUE_PATTERN_FROM='1' QUEUE_PATTERN_TO='1' $perftest &
perftest_pid="$!"

# Wait for PerfTest to get going
sleep 10

# Introduce a rule to timeout connections
# "$toxiproxy_cli" toxic add --toxicName amqp_5672_0_timeout --type timeout --attribute timeout=5000 --downstream amqp_5672_0

# Toggle status of proxy
"$toxiproxy_cli" toggle amqp_5672_0

# Wait a while for mayhem to ensue
sleep 10

# Remove rule to timeout connections, PerfTest should recover
# "$toxiproxy_cli" toxic remove --toxicName amqp_5672_0_timeout amqp_5672_0

# Toggle status of proxy
"$toxiproxy_cli" toggle amqp_5672_0

wait
