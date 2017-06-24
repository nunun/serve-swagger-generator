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
export HTTPD_POLLEE_PORT="${HTTPD_POLLEE_PORT:-"80"}"
export CODEGEN_URL="${CODEGEN_URL:-""}"
export CODEGEN_LANG="${CODEGEN_LANG:-"php"}"
export CODEGEN_TEMPLATE="${CODEGEN_TEMPLATE:-""}"
export CODEGEN_CONFIG="${CODEGEN_CONFIG:-""}"
export CODEGEN_CHECK_INTERVAL="${CODEGEN_CHECK_INTERVAL:-"1"}"
export DAEMON_CHECK_INTERVAL="${DAEMON_CHECK_INTERVAL:-"10"}"
export TZ="${TZ:-"UTC"}"

# spec.yaml
SPEC_FILE="/spec.yaml"
if [ ! "${CODEGEN_URL}" = "" ]; then
        SPEC_FILE="/spec.download.yaml"
fi

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
        tail -n0 -f /var/log/rsync.log &
        rsync --daemon
        sleep 3
}
stop_rsyncd() {
        pkill -f 'rsync.log'
        pkill -f 'rsync --daemon'
        rm -rf /var/run/rsyncd.pid
        rm -rf /var/run/rsyncd.lock
        sleep 3
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

# httpd_pollee
httpd_pollee() {
        echo "(-> httpd_pollee)"
        echo "httpd pollee is listening on port ${HTTPD_POLLEE_PORT}."
        R="require 'webrick';s=WEBrick::HTTPServer.new({Port:${HTTPD_POLLEE_PORT}})"
        R="${R};s.mount_proc('/'){|q,r|r.body=File.mtime('${RSYNCD_MODULE_DIR}').to_s}"
        R="${R};s.start"
        ruby -e "${R}" > /dev/null 2>&1
        echo "(<- httpd_pollee)"
}
start_httpd_pollee() {
        stop_httpd_pollee
        httpd_pollee &
}
stop_httpd_pollee() {
        pkill -f 'ruby -e'
}
check_httpd_pollee() {
        if [ "`pgrep -f 'ruby -e'`" = "" ]; then
                start_httpd_pollee
        fi
}

# spec.yaml
check_spec() {
        FOUND="`find ${SPEC_FILE} -mmin -${CODEGEN_CHECK_INTERVAL}`"
        if [ "${FOUND}" = "" ]; then
                if [ ! "${CODEGEN_URL}" = "" ]; then
                        echo "downloading spec ... ${CODEGEN_URL}"
                        curl -o ${SPEC_FILE} "${CODEGEN_URL}"
                        touch /.modified
                fi
                if [ -f "/.modified" ]; then
                        echo "spec update detected."
                        echo "stopping rsyncd ..."
                        stop_rsyncd
                        rm -vrf /.modified
                        cp -v ${SPEC_FILE} /spec.gen.yaml
                        rm -vrf /data/*
                        echo "check config ..."
                        CODEGEN_OPTIONS=""
                        if [ ! "${CODEGEN_TEMPLATE}" = "" ]; then
                                CODEGEN_OPTIONS="${CODEGEN_OPTIONS} -t ${CODEGEN_TEMPLATE}"
                        fi
                        if [ ! "${CODEGEN_CONFIG}" = "" ]; then
                                echo "${CODEGEN_CONFIG}" > /.config
                                CODEGEN_OPTIONS="${CODEGEN_OPTIONS} -c /.config"
                        fi
                        echo "generate spec code ..."
                        groovy /SwaggerCodegenCli.groovy generate \
                                -i /spec.gen.yaml \
                                -l ${CODEGEN_LANG} \
                                -o /data \
                                ${CODEGEN_OPTIONS}
                        if [ -d "/bundles" ]; then
                                echo "add bundle files ..."
                                cp -rv /bundles/* /data/
                        fi
                        echo "generate done."
                        echo "restarting rsyncd ..."
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
        check_httpd_pollee
        check_spec
        sleep "${DAEMON_CHECK_INTERVAL}"
done
