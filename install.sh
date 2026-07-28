#!/bin/bash
# bedolaga-installer.sh
# Поддержка: amd64, arm64 (ARMv8), armv7l (ARMv7)
# Автоматическая установка Bedolaga Bot + Cabinet
# с интеграцией в существующий Nginx и SSL (Certbot)

set -e
set -o pipefail

# ---------------------- Цвета ----------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------- Проверка root ----------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Запускайте с sudo.${NC}"
   exit 1
fi

# ---------- Определение ОС и архитектуры ----------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Не удалось определить ОС.${NC}"
    exit 1
fi
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo -e "${RED}Поддерживаются только Ubuntu/Debian.${NC}"
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH_NAME="amd64"
        ;;
    aarch64|arm64)
        ARCH_NAME="arm64"
        ;;
    armv7l)
        ARCH_NAME="armv7l"
        ;;
    *)
        echo -e "${YELLOW}⚠️ Неизвестная архитектура: $ARCH. Попробуем продолжить, но могут быть проблемы.${NC}"
        ARCH_NAME="$ARCH"
        ;;
esac
echo -e "${GREEN}✅ ОС: $OS, Архитектура: $ARCH_NAME${NC}"

# ---------- Функции ----------
is_port_in_use() {
    ss -tulpn | grep -q ":$1 "
}

find_telegram_port() {
    local allowed_ports=(88 8443 443)
    for port in "${allowed_ports[@]}"; do
        if ! is_port_in_use $port; then
            echo "$port"
            return 0
        else
            >&2 echo -e "${YELLOW}⚠️ Порт $port занят, пробуем следующий...${NC}"
        fi
    done
    >&2 echo -e "${RED}❌ Все разрешённые порты (88, 8443, 443) заняты.${NC}"
    exit 1
}

# ---------- Запрос данных ----------
echo -e "${YELLOW}Введите основной домен (например, example.com), уже используемый для вашей ноды:${NC}"
read -p "Основной домен: " MAIN_DOMAIN
echo -e "${YELLOW}Введите поддомен для вебхука бота (например, hooks.$MAIN_DOMAIN):${NC}"
read -p "Поддомен вебхука: " WEBHOOK_DOMAIN
echo -e "${YELLOW}Введите поддомен для веб-кабинета (например, cabinet.$MAIN_DOMAIN):${NC}"
read -p "Поддомен кабинета: " CABINET_DOMAIN
echo -e "${YELLOW}Введите токен бота от @BotFather:${NC}"
read -sp "BOT_TOKEN: " BOT_TOKEN; echo
echo -e "${YELLOW}Введите ваш Telegram ID (администратора):${NC}"
read -p "ADMIN_IDS: " ADMIN_IDS
echo -e "${YELLOW}Введите API URL панели Remnawave (например, https://panel.$MAIN_DOMAIN):${NC}"
read -p "REMNAWAVE_API_URL: " REMNAWAVE_API_URL
echo -e "${YELLOW}Введите API KEY от панели Remnawave:${NC}"
read -sp "REMNAWAVE_API_KEY: " REMNAWAVE_API_KEY; echo

WEBHOOK_SECRET=$(openssl rand -hex 32)
CABINET_JWT_SECRET=$(openssl rand -hex 32)

# ---------- Установка Docker (для ARM тоже работает) ----------
echo -e "${YELLOW}➜ Проверка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Устанавливаем Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER
fi
if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Устанавливаем Docker Compose plugin...${NC}"
    apt-get update && apt-get install -y docker-compose-plugin
fi
echo -e "${GREEN}✅ Docker готов.${NC}"

# ---------- Установка Nginx ----------
echo -e "${YELLOW}➜ Проверка Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    apt-get update && apt-get install -y nginx
    systemctl enable nginx && systemctl start nginx
fi
echo -e "${GREEN}✅ Nginx установлен.${NC}"

# ---------- Установка Certbot + плагин Nginx ----------
echo -e "${YELLOW}➜ Проверка Certbot и плагина Nginx...${NC}"
if ! command -v certbot &> /dev/null; then
    apt-get update && apt-get install -y certbot python3-certbot-nginx
else
    if ! certbot plugins | grep -q "nginx"; then
        apt-get update && apt-get install -y python3-certbot-nginx
    fi
fi
echo -e "${GREEN}✅ Certbot и плагин готовы.${NC}"

# ---------- Поиск свободного внешнего порта HTTPS ----------
echo -e "${YELLOW}➜ Поиск свободного HTTPS-порта (разрешённого Telegram)...${NC}"
HTTPS_PORT=$(find_telegram_port)
echo -e "${GREEN}✅ Выбран внешний HTTPS-порт: $HTTPS_PORT${NC}"

# ---------- Внутренний порт бота ----------
BOT_INTERNAL_PORT=8080
HOST_BOT_PORT=8081
while is_port_in_use $HOST_BOT_PORT; do
    HOST_BOT_PORT=$((HOST_BOT_PORT + 1))
done
echo -e "${GREEN}✅ Внешний порт для бота (для Nginx): $HOST_BOT_PORT (внутри: $BOT_INTERNAL_PORT)${NC}"

# ---------- Проверка DNS ----------
echo -e "${YELLOW}➜ Проверка DNS для поддоменов...${NC}"
if ! command -v dig &> /dev/null; then
    apt-get update && apt-get install -y dnsutils
fi
SERVER_IP=$(curl -s ifconfig.me)
for domain in "$WEBHOOK_DOMAIN" "$CABINET_DOMAIN"; do
    if ! dig +short "$domain" | grep -q "$SERVER_IP"; then
        echo -e "${RED}⚠️ DNS-запись $domain не указывает на этот сервер.${NC}"
        read -p "Продолжить? (y/N) " ans
        [[ ! "$ans" =~ ^[Yy]$ ]] && exit 1
    else
        echo -e "${GREEN}✅ $domain -> OK${NC}"
    fi
done

# ---------- Открытие портов в фаерволе ----------
echo -e "${YELLOW}➜ Открываем порты в фаерволе...${NC}"
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp || true
    ufw allow $HTTPS_PORT/tcp || true
    ufw allow $HOST_BOT_PORT/tcp || true
    ufw reload
    echo -e "${GREEN}✅ Порты 80, $HTTPS_PORT и $HOST_BOT_PORT открыты через UFW.${NC}"
elif command -v iptables &> /dev/null; then
    for port in 80 $HTTPS_PORT $HOST_BOT_PORT; do
        if ! iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p tcp --dport $port -j ACCEPT
        fi
    done
    command -v netfilter-persistent &> /dev/null && netfilter-persistent save
    echo -e "${GREEN}✅ Порты открыты через iptables.${NC}"
else
    echo -e "${YELLOW}⚠️ Не найден фаервол, откройте порты 80, $HTTPS_PORT и $HOST_BOT_PORT вручную.${NC}"
fi
sleep 2

# ---------- Клонирование бота ----------
echo -e "${YELLOW}➜ Установка Bedolaga Bot...${NC}"
cd /opt
if [[ -d "remnawave-bedolaga-telegram-bot" ]]; then
    cd remnawave-bedolaga-telegram-bot && git pull
else
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git
    cd remnawave-bedolaga-telegram-bot
fi

# ---------- Создание папок с правами ----------
echo -e "${YELLOW}➜ Создание папок для бэкапов, логов и локалей...${NC}"
mkdir -p data/backups logs locales
chmod -R 777 data logs locales

# ---------- Создание .env ----------
cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
REMNAWAVE_API_URL=$REMNAWAVE_API_URL
REMNAWAVE_API_KEY=$REMNAWAVE_API_KEY
BOT_RUN_MODE=webhook
WEBHOOK_URL=https://$WEBHOOK_DOMAIN:$HTTPS_PORT
WEBHOOK_PATH=/webhook
WEBHOOK_SECRET_TOKEN=$WEBHOOK_SECRET
WEB_API_ENABLED=true
WEB_API_HOST=0.0.0.0
WEB_API_PORT=$BOT_INTERNAL_PORT
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN:$HTTPS_PORT
WEB_API_ALLOWED_ORIGINS=https://$CABINET_DOMAIN:$HTTPS_PORT
EOF

# ---------- Настройка docker-compose.yml ----------
# Проверяем, есть ли уже порты, если нет — добавляем (упрощённо)
if ! grep -q "$HOST_BOT_PORT:$BOT_INTERNAL_PORT" docker-compose.yml; then
    # Если есть секция ports, заменяем первую строку, иначе добавляем после image
    if grep -q "ports:" docker-compose.yml; then
        sed -i "/ports:/,/^[^ ]/ s/- .*:.*/- \"$HOST_BOT_PORT:$BOT_INTERNAL_PORT\"/" docker-compose.yml
    else
        # Вставляем секцию ports после строки с image (упрощённо)
        sed -i "/image:/a \    ports:\n      - \"$HOST_BOT_PORT:$BOT_INTERNAL_PORT\"" docker-compose.yml
    fi
fi

# ---------- Запуск бота ----------
docker compose up -d
echo -e "${GREEN}✅ Bedolaga Bot запущен.${NC}"

# ---------- Установка Cabinet ----------
echo -e "${YELLOW}➜ Установка Cabinet...${NC}"
mkdir -p /srv/cabinet
docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
docker cp tmp_cabinet:/usr/share/nginx/html/. /srv/cabinet/
docker rm tmp_cabinet
chown -R www-data:www-data /srv/cabinet
echo -e "${GREEN}✅ Cabinet файлы размещены.${NC}"

# ---------- Настройка Nginx ----------
echo -e "${YELLOW}➜ Создание конфигураций Nginx (порт $HTTPS_PORT)...${NC}"
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/bedolaga-webhook <<EOF
server {
    listen 80;
    server_name $WEBHOOK_DOMAIN;
    return 301 https://\$server_name:$HTTPS_PORT\$request_uri;
}

server {
    listen $HTTPS_PORT ssl http2;
    server_name $WEBHOOK_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$HOST_BOT_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

cat > /etc/nginx/sites-available/bedolaga-cabinet <<EOF
server {
    listen 80;
    server_name $CABINET_DOMAIN;
    return 301 https://\$server_name:$HTTPS_PORT\$request_uri;
}

server {
    listen $HTTPS_PORT ssl http2;
    server_name $CABINET_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem;

    root /srv/cabinet;
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    location /api {
        proxy_pass http://127.0.0.1:$HOST_BOT_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/bedolaga-webhook /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/bedolaga-cabinet /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
echo -e "${GREEN}✅ Nginx перезагружен.${NC}"

# ---------- SSL-сертификаты ----------
echo -e "${YELLOW}➜ Получение SSL-сертификатов...${NC}"
if certbot certificates 2>/dev/null | grep -q "Domains:.*$MAIN_DOMAIN"; then
    certbot --nginx -d "$MAIN_DOMAIN" -d "$WEBHOOK_DOMAIN" -d "$CABINET_DOMAIN" \
            --expand --non-interactive --agree-tos --email "admin@$MAIN_DOMAIN"
else
    certbot --nginx -d "$MAIN_DOMAIN" -d "$WEBHOOK_DOMAIN" -d "$CABINET_DOMAIN" \
            --non-interactive --agree-tos --email "admin@$MAIN_DOMAIN"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SSL-сертификаты успешно установлены.${NC}"
    systemctl reload nginx
else
    echo -e "${RED}❌ Ошибка при получении сертификатов. Проверьте порт 80 и DNS.${NC}"
    exit 1
fi

# ---------- Перезапуск бота ----------
docker compose restart bot
sleep 5

# ---------- Установка вебхука ----------
echo -e "${YELLOW}➜ Установка вебхука в Telegram...${NC}"
WEBHOOK_URL="https://$WEBHOOK_DOMAIN:$HTTPS_PORT/webhook"
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" \
    -d "url=$WEBHOOK_URL&secret_token=$WEBHOOK_SECRET_TOKEN")
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo -e "${GREEN}✅ Вебхук успешно установлен на $WEBHOOK_URL${NC}"
else
    echo -e "${RED}❌ Не удалось установить вебхук. Ответ: $RESPONSE${NC}"
    echo -e "${YELLOW}Попробуйте установить вручную:${NC}"
    echo "curl -X POST 'https://api.telegram.org/bot$BOT_TOKEN/setWebhook' -d 'url=$WEBHOOK_URL&secret_token=$WEBHOOK_SECRET_TOKEN'"
fi

# ---------- Финальное сообщение ----------
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}✅ Установка завершена!${NC}"
echo -e "🔹 Вебхук бота: https://$WEBHOOK_DOMAIN:$HTTPS_PORT"
echo -e "🔹 Веб-кабинет: https://$CABINET_DOMAIN:$HTTPS_PORT"
echo -e "🔹 Порт для доступа Nginx к боту: $HOST_BOT_PORT"
echo -e "🔹 Архитектура: $ARCH_NAME"
echo -e ""
echo -e "${YELLOW}⚠️  Важно:${NC}"
echo -e "   - Проверьте доступность кабинета в браузере."
echo -e "   - Отправьте боту команду /start."
echo -e "   - При необходимости проверьте логи: docker compose logs bot"
echo -e "${GREEN}===============================================${NC}"
