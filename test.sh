docker-compose down
if [ "${1}" = "stop" ]; then
        exit
fi
docker-compose up --build
