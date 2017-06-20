export RSYNCD_UID="${RSYNCD_UID:-"root"}"
export RSYNCD_GID="${RSYNCD_GID:-"root"}"
export RSYNCD_PORT="${RSYNCD_PORT:-"873"}"
export RSYNCD_MODULE_NAME="${RSYNCD_MODULE_NAME:-"data"}"
export RSYNCD_MODULE_DIR="${RSYNCD_MODULE_DIR:-"/data"}"
export RSYNCD_MODULE_COMMENT="${RSYNCD_MODULE_COMMENT:-"DATA"}"
export RSYNCD_TIMEOUT="${RSYNCD_TIMEOUT:-"1800"}"
export RSYNCD_MAX_CONNECTIONS="${RSYNCD_MAX_CONNECTIONS:-"1"}"
export RSYNCD_USERNAME="${RSYNCD_USERNAME:-"username"}"
export RSYNCD_PASSWORD="${RSYNCD_PASSWORD:-"password"}"
export CODEGEN_LANG="php"
export CODEGEN_OPTIONS=""
export DAEMON_CHECK_INTERVAL="${DAEMON_CHECK_INTERVAL:-"20"}"
export TZ="${TZ:-"UTC"}"

# timezone
cp /usr/share/zoneinfo/$TZ /etc/localtime
echo $TZ > /etc/timezone

# /etc/rsyncd.conf
RSYNCD_CONF_FILE="/etc/rsyncd.conf"
echo "pid file  = /var/run/rsyncd.pid"              > "${RSYNCD_CONF_FILE}"
echo "lock file = /var/run/rsync.lock"             >> "${RSYNCD_CONF_FILE}"
echo "log file  = /var/log/rsync.log"              >> "${RSYNCD_CONF_FILE}"
echo "port      = ${RSYNCD_PORT}"                  >> "${RSYNCD_CONF_FILE}"
echo ""                                            >> "${RSYNCD_CONF_FILE}"
echo "[${RSYNCD_MODULE_NAME}]"                     >> "${RSYNCD_CONF_FILE}"
echo "uid             = ${RSYNCD_UID}"             >> "${RSYNCD_CONF_FILE}"
echo "gid             = ${RSYNCD_GID}"             >> "${RSYNCD_CONF_FILE}"
echo "path            = ${RSYNCD_MODULE_DIR}"      >> "${RSYNCD_CONF_FILE}"
echo "comment         = ${RSYNCD_MODULE_COMMENT}"  >> "${RSYNCD_CONF_FILE}"
echo "read only       = false"                     >> "${RSYNCD_CONF_FILE}"
echo "timeout         = ${RSYNCD_TIMEOUT}"         >> "${RSYNCD_CONF_FILE}"
echo "max connections = ${RSYNCD_MAX_CONNECTIONS}" >> "${RSYNCD_CONF_FILE}"
echo "auth users      = ${RSYNCD_USERNAME}"        >> "${RSYNCD_CONF_FILE}"
echo "secrets file    = /etc/rsyncd.secrets"       >> "${RSYNCD_CONF_FILE}"

# /etc/rsyncd.secrets
RSYNCD_SECRETS_FILE="/etc/rsyncd.secrets"
echo "${RSYNCD_USERNAME}:${RSYNCD_PASSWORD}" > "${RSYNCD_SECRETS_FILE}"
chmod 600 "${RSYNCD_SECRETS_FILE}"

# rsyncd
mkdir -p "${RSYNCD_MODULE_DIR}"
mkdir -p /var/log/
touch /var/log/rsync.log
start_rsyncd() {
        stop_rsyncd
        tail -f /var/log/rsync.log &
        rsync --daemon
        sleep 5
}
stop_rsyncd() {
        pkill -f 'rsync.log'
        pkill -f 'rsync --daemon'
        rm -rf /var/run/rsyncd.pid
        rm -rf /var/run/rsyncd.lock
        sleep 5
}
check_rsyncd() {
        if [ -f "/.rsyncd_lock" ]; then
                return
        fi
        if [    "`pgrep -f 'rsync.log'`"      = "" \
             -o "`pgrep -f 'rsync --daemon'`" = "" ]; then
                start_rsyncd
        fi
}

# spec.yaml
check_spec() {
        FOUND="`find /spec.yaml -mmin -1`"
        if [ "${FOUND}" = "" ]; then
                if [ -f "/.modified" ]; then
                        echo "spec update detected."
                        stop_rsyncd
                        rm -vrf /.modified
                        cp -v /spec.yaml /gen.yaml
                        rm -vrf /data/*
                        echo "generate spec code ..."
                        groovy /SwaggerCodegenCli.groovy generate \
                                -i /gen.yaml \
                                -l ${CODEGEN_LANG} \
                                -o /data \
                                ${CODEGEN_OPTIONS}
                        echo "generate done."
                        start_rsyncd
                fi
        else
                if [ ! -f "/.modified" ]; then
                        touch /.modified
                fi
        fi
}
touch /.modified

# daemon loop
while : ; do
        check_rsyncd
        check_spec
        sleep "${DAEMON_CHECK_INTERVAL}"
done
