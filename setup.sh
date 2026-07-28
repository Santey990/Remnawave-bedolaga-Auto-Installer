#!/bin/bash
# bedolaga-installer.sh
# Полная автоматическая установка Bedolaga Bot и Cabinet на сервер с уже работающей нодой (Nginx + SSL)

set -e  # остановка при ошибке
set -o pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------
# 1. Проверка прав root
# ------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Этот скрипт должен запускаться с правами root (sudo).${NC}"
   exit 1
fi

# ------------------------------------------------------------
# 2. Определение ОС
# ------------------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}Не удалось определить ОС. Поддерживаются только Ubuntu/Debian.${NC}"
    exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo -e "${RED}Скрипт поддерживает только Ubuntu и Debian.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ОС определена: $OS $VER${NC}"

# ------------------------------------------------------------
# 3. Запрос необходимых данных у пользователя
# ------------------------------------------------------------
echo -e "${YELLOW}Введите основной домен (например, example.com), который уже используется для вашей ноды:${NC}"
read -p "Основной домен: " MAIN_DOMAIN

echo -e "${YELLOW}Введите поддомен для вебхука бота (например, hooks.$MAIN_DOMAIN):${NC}"
read -p "Поддомен вебхука: " WEBHOOK_DOMAIN

echo -e "${YELLOW}Введите поддомен для веб-кабинета (например, cabinet.$MAIN_DOMAIN):${NC}"
read -p "Поддомен кабинета: " CABINET_DOMAIN

echo -e "${YELLOW}Введите токен бота от @BotFather:${NC}"
read -sp "BOT_TOKEN: " BOT_TOKEN
echo

echo -e "${YELLOW}Введите ваш Telegram ID (для администратора):${NC}"
read -p "ADMIN_IDS: " ADMIN_IDS

echo -e "${YELLOW}Введите API URL вашей панели Remnawave (например, https://panel.$MAIN_DOMAIN):${NC}"
read -p "REMNAWAVE_API_URL: " REMNAWAVE_API_URL

echo -e "${YELLOW}Введите API KEY от панели Remnawave:${NC}"
read -sp "REMNAWAVE_API_KEY: " REMNAWAVE_API_KEY
echo

# Генерация секретов
WEBHOOK_SECRET=$(openssl rand -hex 32)
CABINET_JWT_SECRET=$(openssl rand -hex 32)

# ------------------------------------------------------------
# 4. Проверка и установка Docker
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Проверка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker не найден. Установка...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER
    echo -e "${GREEN}✅ Docker установлен.${NC}"
else
    echo -e "${GREEN}✅ Docker уже установлен.${NC}"
fi

# Проверка Docker Compose (plugin или standalone)
if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Docker Compose plugin не найден. Установка...${NC}"
    apt-get update && apt-get install -y docker-compose-plugin
fi
echo -e "${GREEN}✅ Docker Compose готов.${NC}"

# ------------------------------------------------------------
# 5. Проверка и установка Nginx
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Проверка Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    echo -e "${YELLOW}Nginx не найден. Установка...${NC}"
    apt-get update && apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo -e "${GREEN}✅ Nginx установлен и запущен.${NC}"
else
    echo -e "${GREEN}✅ Nginx уже установлен.${NC}"
fi

# ------------------------------------------------------------
# 6. Проверка и установка Certbot (для ACME HTTP-01)
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Проверка Certbot...${NC}"
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Certbot не найден. Установка...${NC}"
    apt-get update && apt-get install -y certbot python3-certbot-nginx
    echo -e "${GREEN}✅ Certbot установлен.${NC}"
else
    echo -e "${GREEN}✅ Certbot уже установлен.${NC}"
fi

# ------------------------------------------------------------
# 7. Проверка доступности портов
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Проверка занятости портов...${NC}"
# Проверяем, что порт 8080 свободен (для бота)
if ss -tulpn | grep -q ":8080 "; then
    echo -e "${RED}⚠️ Порт 8080 уже занят. Скрипт попытается использовать 8081.${NC}"
    WEB_API_PORT=8081
else
    WEB_API_PORT=8080
fi
echo -e "${GREEN}✅ Порт для бота: $WEB_API_PORT${NC}"

# ------------------------------------------------------------
# 8. Проверка DNS (опционально)
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Проверка DNS для поддоменов...${NC}"
for domain in "$WEBHOOK_DOMAIN" "$CABINET_DOMAIN"; do
    if ! dig +short "$domain" | grep -q "$(curl -s ifconfig.me)"; then
        echo -e "${RED}⚠️ Внимание: DNS-запись для $domain не указывает на этот сервер.${NC}"
        echo -e "${YELLOW}Продолжить? (y/N)${NC}"
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✅ $domain -> OK${NC}"
    fi
done

# ------------------------------------------------------------
# 9. Установка Bedolaga Bot
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Установка Bedolaga Bot...${NC}"
cd /opt
if [[ -d "remnawave-bedolaga-telegram-bot" ]]; then
    echo -e "${YELLOW}Директория бота уже существует. Обновление...${NC}"
    cd remnawave-bedolaga-telegram-bot
    git pull
else
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git
    cd remnawave-bedolaga-telegram-bot
fi

# Создание .env
cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
REMNAWAVE_API_URL=$REMNAWAVE_API_URL
REMNAWAVE_API_KEY=$REMNAWAVE_API_KEY
BOT_RUN_MODE=webhook
WEBHOOK_URL=https://$WEBHOOK_DOMAIN
WEBHOOK_PATH=/webhook
WEBHOOK_SECRET_TOKEN=$WEBHOOK_SECRET
WEB_API_ENABLED=true
WEB_API_PORT=$WEB_API_PORT
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
WEB_API_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
EOF

# Запуск бота
docker compose up -d
echo -e "${GREEN}✅ Bedolaga Bot запущен.${NC}"

# ------------------------------------------------------------
# 10. Установка Cabinet (веб-кабинет)
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Установка Cabinet...${NC}"
mkdir -p /srv/cabinet
docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
docker cp tmp_cabinet:/usr/share/nginx/html/. /srv/cabinet/
docker rm tmp_cabinet
chown -R www-data:www-data /srv/cabinet
echo -e "${GREEN}✅ Cabinet файлы размещены.${NC}"

# ------------------------------------------------------------
# 11. Создание конфигураций Nginx
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Настройка Nginx...${NC}"

# Блок для вебхука
cat > /etc/nginx/sites-available/bedolaga-webhook <<EOF
server {
    listen 80;
    server_name $WEBHOOK_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $WEBHOOK_DOMAIN;

    # SSL будет добавлен позже через Certbot
    # Пока используем временный самоподписанный или просто без SSL
    # Но Certbot добавит свою конфигурацию

    location / {
        proxy_pass http://127.0.0.1:$WEB_API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Блок для кабинета
cat > /etc/nginx/sites-available/bedolaga-cabinet <<EOF
server {
    listen 80;
    server_name $CABINET_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $CABINET_DOMAIN;

    root /srv/cabinet;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:$WEB_API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Включаем сайты
ln -sf /etc/nginx/sites-available/bedolaga-webhook /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/bedolaga-cabinet /etc/nginx/sites-enabled/

# Проверка конфигурации
nginx -t
systemctl reload nginx
echo -e "${GREEN}✅ Nginx перезагружен с новыми конфигурациями.${NC}"

# ------------------------------------------------------------
# 12. Получение SSL-сертификатов через Certbot (расширение существующего)
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Получение SSL-сертификатов для новых поддоменов...${NC}"
# Пробуем расширить существующий сертификат (если он есть для основного домена)
# Или запрашиваем новый с указанием всех доменов
if certbot certificates | grep -q "$MAIN_DOMAIN"; then
    echo -e "${YELLOW}Обнаружен существующий сертификат для $MAIN_DOMAIN. Расширяем...${NC}"
    certbot --nginx -d "$MAIN_DOMAIN" -d "$WEBHOOK_DOMAIN" -d "$CABINET_DOMAIN" --expand --non-interactive --agree-tos --email admin@$MAIN_DOMAIN
else
    echo -e "${YELLOW}Нет существующего сертификата. Запрашиваем новый...${NC}"
    certbot --nginx -d "$MAIN_DOMAIN" -d "$WEBHOOK_DOMAIN" -d "$CABINET_DOMAIN" --non-interactive --agree-tos --email admin@$MAIN_DOMAIN
fi

systemctl reload nginx
echo -e "${GREEN}✅ SSL сертификаты установлены.${NC}"

# ------------------------------------------------------------
# 13. Перезапуск бота для применения webhook
# ------------------------------------------------------------
echo -e "${YELLOW}➜ Перезапуск бота для установки webhook...${NC}"
cd /opt/remnawave-bedolaga-telegram-bot
docker compose restart remnawave_bot
sleep 5
docker compose logs --tail=20 remnawave_bot

# ------------------------------------------------------------
# 14. Финальные инструкции
# ------------------------------------------------------------
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}✅ Установка завершена!${NC}"
echo -e "🔹 Вебхук бота: https://$WEBHOOK_DOMAIN"
echo -e "🔹 Кабинет: https://$CABINET_DOMAIN"
echo -e "🔹 Админ-панель бота (если включена): http://localhost:$WEB_API_PORT (только локально)"
echo -e "${YELLOW}ВАЖНО: Проверьте логи бота на наличие ошибок.${NC}"
echo -e "${YELLOW}Рекомендуется настроить бэкапы согласно документации.${NC}"
echo -e "${GREEN}===============================================${NC}"
