# pymongo-api (реализация шардирования + репликация + redis cache)

## Как запустить

Запускаем mongodb и приложение, а так же инициализируем кластер

```shell
./scripts/mongo-init.sh
```

В последующие разы достаточно выполнить 

```shell
docker compose up -d
```

Остановить кластер и удалить все данные

```shell
docker compose down -v
```

## Как проверить

### Если вы запускаете проект на локальной машине

```shell
curl -X 'GET' 'http://localhost:8080/helloDoc/count' -H 'accept: application/json' && echo
```

#### Для проверки работоспособности кеширования

```shell
curl -X 'GET' 'http://localhost:8080/helloDoc/users' -H 'accept: application/json' | jq . 
```