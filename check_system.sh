cat > /root/check_system.sh << 'EOF'
#!/bin/bash

echo "═══════════════════════════════════════════════════════════════════════════"
echo "       🔍  КОМПЛЕКСНАЯ ПРОВЕРКА СИСТЕМЫ (Remnawave + Bedolaga)           "
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

# 1. Информация о системе
echo "📌 1. ИНФОРМАЦИЯ О СИСТЕМЕ"
echo "───────────────────────────────────────────────────────────────────────────"
echo "  Дата и время: $(date)"
echo "  Hostname: $(hostname)"
echo "  ОС: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "  Ядро: $(uname -r)"
echo "  Архитектура: $(uname -m)"
echo ""

# 2. Docker-контейнеры
echo "📌 2. ЗАПУЩЕННЫЕ DOCKER-КОНТЕЙНЕРЫ"
echo "───────────────────────────────────────────────────────────────────────────"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "📌 3. ВСЕ КОНТЕЙНЕРЫ (включая остановленные)"
echo "───────────────────────────────────────────────────────────────────────────"
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
echo ""

# 4. Занятые ключевые порты
echo "📌 4. КЛЮЧЕВЫЕ ПОРТЫ (прослушивание)"
echo "───────────────────────────────────────────────────────────────────────────"
for port in 443 8443 4443 9443 3020 8080 5432 6379 80; do
    echo -n "  Порт $port: "
    sudo ss -tulpn | grep ":$port " | head -n 1 || echo "свободен"
done
echo ""

# 5. Проверка Caddy
echo "📌 5. ПРОВЕРКА CADDY"
echo "───────────────────────────────────────────────────────────────────────────"
if docker ps | grep -q caddy; then
    echo "  ✅ Caddy запущен"
    echo "  Порты: $(docker port caddy 2>/dev/null | head -3)"
    echo "  Caddyfile (первые 20 строк):"
    docker exec caddy cat /etc/caddy/Caddyfile 2>/dev/null | head -20 | sed 's/^/    /'
    echo "  Логи Caddy (последние 10 строк):"
    docker logs --tail 10 caddy 2>&1 | sed 's/^/    /'
else
    echo "  ❌ Caddy не запущен"
fi
echo ""

# 6. Проверка бота Bedolaga
echo "📌 6. ПРОВЕРКА БОТА (remnawave_bot или bedolaga-bot)"
echo "───────────────────────────────────────────────────────────────────────────"
BOT_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'remnawave_bot|bedolaga-bot' | head -1)
if [ -n "$BOT_CONTAINER" ]; then
    echo "  ✅ Бот найден: $BOT_CONTAINER"
    echo "  Переменные окружения (без паролей):"
    docker exec "$BOT_CONTAINER" env 2>/dev/null | grep -E "BOT_TOKEN|ADMIN_IDS|REMNAWAVE_API_URL|CABINET_ENABLED|POSTGRES_HOST|DB_TYPE" | sed 's/=.*/=***/' | sed 's/^/    /'
    echo "  Логи бота (последние 15 строк):"
    docker logs --tail 15 "$BOT_CONTAINER" 2>&1 | sed 's/^/    /'
else
    echo "  ❌ Бот не найден"
fi
echo ""

# 7. Проверка Cabinet (frontend)
echo "📌 7. ПРОВЕРКА CABINET (frontend)"
echo "───────────────────────────────────────────────────────────────────────────"
if docker ps | grep -q cabinet_frontend; then
    echo "  ✅ Cabinet запущен на порту $(docker port cabinet_frontend | grep 80/tcp | head -1 | cut -d: -f2)"
    echo "  Здоровье: $(docker inspect --format='{{.State.Health.Status}}' cabinet_frontend 2>/dev/null || echo 'неизвестно')"
else
    echo "  ❌ Cabinet не запущен"
fi
echo ""

# 8. Доступность панели Remnawave
echo "📌 8. ДОСТУП К REMNAWAVE API"
echo "───────────────────────────────────────────────────────────────────────────"
if [ -n "$BOT_CONTAINER" ]; then
    API_URL=$(docker exec "$BOT_CONTAINER" env 2>/dev/null | grep REMNAWAVE_API_URL | cut -d= -f2-)
    if [ -n "$API_URL" ]; then
        echo "  API URL: $API_URL"
        # Проверка через wget (если есть) или curl
        if docker exec "$BOT_CONTAINER" command -v curl &>/dev/null; then
            HTTP_CODE=$(docker exec "$BOT_CONTAINER" curl -s -o /dev/null -w "%{http_code}" "$API_URL" 2>/dev/null)
            if [ "$HTTP_CODE" = "000" ]; then
                echo "  ❌ API недоступен (соединение не установлено)"
            else
                echo "  ✅ API доступен (код: $HTTP_CODE)"
            fi
        else
            echo "  ⚠️  curl не установлен в контейнере, пропускаем проверку"
        fi
    else
        echo "  ⚠️  Переменная REMNAWAVE_API_URL не найдена"
    fi
else
    echo "  ❌ Бот не найден, проверка API невозможна"
fi
echo ""

# 9. Проверка ядра Remnawave (remnanode)
echo "📌 9. ПРОВЕРКА ЯДРА REMNAWAVE (remnanode)"
echo "───────────────────────────────────────────────────────────────────────────"
if docker ps | grep -q remnanode; then
    echo "  ✅ remnanode запущен"
    if sudo ss -tulpn | grep -q ":443.*rw-core"; then
        echo "  ✅ rw-core слушает на порту 443 (как и ожидалось)"
    elif sudo ss -tulpn | grep -q ":443.*caddy"; then
        echo "  ⚠️  Порт 443 занят Caddy, а не ядром (потенциальный конфликт)"
    else
        echo "  ⚠️  Порт 443 не прослушивается ни ядром, ни Caddy"
    fi
else
    echo "  ❌ remnanode не запущен"
fi
echo ""

# 10. Проверка конфигурационных файлов
echo "📌 10. КОНФИГУРАЦИОННЫЕ ФАЙЛЫ"
echo "───────────────────────────────────────────────────────────────────────────"
if [ -d "/opt/bedolaga" ]; then
    echo "  /opt/bedolaga – существует"
    if [ -f "/opt/bedolaga/docker-compose.yml" ]; then
        echo "  docker-compose.yml найден, первые 20 строк:"
        head -20 /opt/bedolaga/docker-compose.yml | sed 's/^/    /'
    fi
else
    echo "  /opt/bedolaga – не найден"
fi
if [ -d "/opt/remnawave" ]; then
    echo "  /opt/remnawave – существует"
    if [ -f "/opt/remnawave/caddy/Caddyfile" ]; then
        echo "  Caddyfile найден, первые 20 строк:"
        head -20 /opt/remnawave/caddy/Caddyfile | sed 's/^/    /'
    fi
else
    echo "  /opt/remnawave – не найден"
fi
echo ""

# 11. Сетевое взаимодействие между контейнерами
echo "📌 11. СЕТЕВЫЕ СВЯЗИ (контейнеры в одной сети)"
echo "───────────────────────────────────────────────────────────────────────────"
docker network ls --format '{{.Name}}' | while read net; do
    count=$(docker network inspect "$net" --format '{{range .Containers}}{{.Name}} {{end}}' | wc -w)
    if [ "$count" -gt 1 ]; then
        echo "  Сеть $net: $(docker network inspect "$net" --format '{{range .Containers}}{{.Name}} {{end}}')"
    fi
done
echo ""

# 12. Проверка DNS
echo "📌 12. ПРОВЕРКА DNS"
echo "───────────────────────────────────────────────────────────────────────────"
for domain in cabinet.dark-team.ru.net localhost host.docker.internal; do
    echo -n "  $domain -> "
    if ping -c 1 -W 1 "$domain" >/dev/null 2>&1; then
        echo "доступен"
    else
        echo "недоступен"
    fi
done
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo "✅  Проверка завершена. Обратите внимание на предупреждения и ошибки."
echo "═══════════════════════════════════════════════════════════════════════════"
EOF

chmod +x /root/check_system.sh
