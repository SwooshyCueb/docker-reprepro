#!/bin/bash

set -m

export GNUPGHOME="/data/.gnupg"
REPREPRO_BASE_DIR="/data/${REPREPRO_BASE_DIR_NAME}"


if [ -f "/config/reprepro_sec.gpg" ]
then
    perms=$(stat -c %a /config/reprepro_sec.gpg)
    if [ "${perms: -1}" != "0" ]
    then
        echo "/config/reprepro_sec.gpg gnupg private key should not be readable by others..."
        echo "=> Aborting!"
        exit 1
    fi
fi
if [ -d "${GNUPGHOME}" ]
then
    echo "=> ${GNUPGHOME} directory already exists:"
    echo "   So gnupg seems to be already configured, nothing to do..."
else
    echo "=> ${GNUPGHOME} directory does not exist:"
    echo "   Configuring gnupg for reprepro user..."
    gpg --import /config/reprepro_pub.gpg
    if [ $? -ne 0 ]; then
        echo "=> Failed to import gnupg public key for reprepro..."
        echo "=> Aborting!"
        exit 1
    fi
    gpg --allow-secret-key-import --import /config/reprepro_sec.gpg
    if [ $? -ne 0 ]; then
        echo "=> Failed to import gnupg private key for reprepro..."
        echo "=> Aborting!"
        exit 1
    fi
    chown -R reprepro:reprepro ${GNUPGHOME}
fi

if [ -d "${REPREPRO_BASE_DIR}" ]
then
    echo "=> ${REPREPRO_BASE_DIR} directory already exists:"
    echo "   So reprepro seems to be already configured, nothing to do..."
else
    echo "=> ${REPREPRO_BASE_DIR} directory does not exist:"
    echo "   Configuring a default ubuntu repository with reprepro..."

    keyid=$(gpg --dry-run /config/reprepro_pub.gpg | grep "^pub " | sed "s/.*\/\([^ ]*\).*/\1/")
    if [ -z "$keyid" ]
    then
        echo "=> Please provide /config/reprepro_pub.gpg file to guess the key id to use for reprepro to sign pakages..."
        echo "=> Aborting!"
        exit 1
    fi

    mkdir -p "${REPREPRO_BASE_DIR}"/{tmp,incoming,conf}

    cat << EOF > "${REPREPRO_BASE_DIR}/conf/options"
verbose
basedir ${REPREPRO_BASE_DIR}
gnupghome ${GNUPGHOME}
ask-passphrase
EOF

    for dist in $(echo ${RPP_DISTRIBUTIONS} | tr ";" "\n"); do
        dcodename_var="RPP_CODENAME_${dist}"
        darchs_var="RPP_ARCHITECTURES_${dist}"
        dcomps_var="RPP_COMPONENTS_${dist}"
        dcodename="${!dcodename_var}"
        if [ -z "${dcodename}" ]; then
            echo "=> No codename supplied for distribution ${dist}: falling back to ${dist} codename"
            dcodename=${dist}
        fi
        cat << EOF >> "${REPREPRO_BASE_DIR}/conf/distributions"
Origin: ${REPREPRO_DEFAULT_NAME}
Label: ${REPREPRO_DEFAULT_NAME}
Codename: ${dcodename}
Architectures: ${!darchs_var:-"i386 amd64 armhf source"}
Components: ${!dcomps_var:-"main"}
Description: ${REPREPRO_DEFAULT_NAME} apt repository
DebOverride: override.${dist}
DscOverride: override.${dist}
SignWith: ${keyid}

EOF
        touch "${REPREPRO_BASE_DIR}"/conf/override.${dist}
    done

    for incoming in $(echo ${RPP_INCOMINGS} | tr ";" "\n"); do
        iallow_var="RPP_ALLOW_${incoming}"
        mkdir -p "${REPREPRO_BASE_DIR}/incoming/${incoming}" "${REPREPRO_BASE_DIR}/tmp/${incoming}"
        cat << EOF >> "${REPREPRO_BASE_DIR}/conf/incoming"
Name: ${incoming}
IncomingDir: ${REPREPRO_BASE_DIR}/incoming/${incoming}
TempDir: ${REPREPRO_BASE_DIR}/tmp/${incoming}
Allow: ${!iallow_var}
Cleanup: on_deny on_error

EOF
    done
    chown -R reprepro:reprepro "${REPREPRO_BASE_DIR}"
fi

declare -A sigvals=( ["SIGHUP"]=1
                     ["SIGINT"]=2
                     ["SIGQUIT"]=3
                     ["SIGILL"]=4
                     ["SIGTRAP"]=5
                     ["SIGABRT"]=6
                     ["SIGIOT"]=6
                     ["SIGBUS"]=7
                     ["SIGFPE"]=8
                     ["SIGKILL"]=9
                     ["SIGUSR1"]=10
                     ["SIGSEGV"]=11
                     ["SIGUSR2"]=12
                     ["SIGPIPE"]=13
                     ["SIGALRM"]=14
                     ["SIGTERM"]=15
                     ["SIGSTKFLT"]=16
                     ["SIGCHLD"]=17
                     ["SIGCONT"]=18
                     ["SIGSTOP"]=19
                     ["SIGTSTP"]=20
                     ["SIGTTIN"]=21
                     ["SIGTTOU"]=22
                     ["SIGURG"]=23
                     ["SIGXCPU"]=24
                     ["SIGXFSZ"]=25
                     ["SIGVTALRM"]=26
                     ["SIGPROF"]=27
                     ["SIGWINCH"]=28
                     ["SIGIO"]=29
                     ["SIGPWR"]=30
                     ["SIGSYS"]=31
                     ["SIGUNUSED"]=31
                     ["SIGRT"]=32 )

function start_daemons {
    echo "=> Starting SSH server..."
    sed 's|@REPREPRO_BASE_DIR@|'"$REPREPRO_BASE_DIR"'|g' /sshd_config.in > /sshd_config
    start-stop-daemon \
        --start \
        --quiet \
        --oknodo \
        --pidfile /var/run/sshd.pid \
        --exec /usr/sbin/sshd \
        -- \
            -f /sshd_config \
            -E /var/log/sshd.log

    echo "=> Starting Nginx..."
    start-stop-daemon \
        --start \
        --quiet \
        --oknodo \
        --pidfile /var/run/nginx.pid \
        --exec /usr/sbin/nginx \
        -- \
            -c /etc/nginx/nginx.conf
}

function stop_daemons {
    echo "=> Stopping Nginx..."
    start-stop-daemon \
        --stop \
        --quiet \
        --oknodo \
        --retry=TERM/30/KILL/5 \
        --pidfile /var/run/nginx.pid
    rm -f /var/run/nginx.pid

    echo "=> Stopping SSH server..."
    start-stop-daemon \
        --stop \
        --quiet \
        --oknodo \
        --retry=TERM/30/KILL/5 \
        --pidfile /var/run/sshd.pid
    rm -f /var/run/sshd.pid
}

function reload_daemons {
    echo "=> Reloading Nginx configuration..."
    start-stop-daemon \
        --stop \
        --quiet \
        --oknodo \
        --signal HUP \
        --pidfile /var/run/nginx.pid

    echo "=> Reloading SSH server configuration..."
    start-stop-daemon \
        --stop \
        --quiet \
        --oknodo \
        --signal HUP \
        --pidfile /var/run/sshd.pid
}

function restart_daemons {
    stop_daemons
    start_daemons
}

function signal_stop {
    echo "=> Received $1"
    stop_daemons
    echo "=> Quitting"
    kill ${!}
    ev=${sigvals["$1"]}
    exit $(( ev + 128 ))
}

function signal_reload {
    echo "=> Received $1"
    reload_daemons
}

function signal_nye {
    echo "=> Received $1"
    echo "   Behavior for this signal not yet defined."
}

function setup_signals {
    handler="$1"; shift
    for sig; do
        trap "$handler '$sig'" "$sig"
    done
}

mkdir -p /var/log/

setup_signals "signal_stop" SIGINT SIGTERM SIGQUIT SIGABRT
setup_signals "signal_reload" SIGHUP
setup_signals "signal_nye" SIGUSR1 SIGUSR2

start_daemons

while true; do
    tail -f /dev/null & wait ${!}
done
