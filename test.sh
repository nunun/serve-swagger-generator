docker-compose down
case "${1}" in
down) exit;;
pull) docker-compose pull; exit;;
esac
docker-compose up --build

