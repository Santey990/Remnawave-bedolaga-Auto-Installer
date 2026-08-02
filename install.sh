#!/bin/bash
# Установщик Bedolaga Bot + Cabinet
# Версия: 4.0.0 (с диагностикой и рекомендациями)
# Поддерживаемые архитектуры: amd64, arm64, armv7l
# Репозиторий: https://github.com/Santey990/Remnawave-bedolaga-Auto-Installer
# Лицензия: MIT

set -e
set -o pipefail

# ---------------------- Цвета ----------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------- Проверка root ----------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Скрипт должен запускаться с правами root (sudo).${NC}"
   exit 1
fi

# ---------------------- Определение ОС и архитектуры ----------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}❌ Не удалось определить ОС. Поддерживаются только Ubuntu/Debian.${NC}"
    exit 1
fi
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo -e "${RED}❌ Поддерживаются только Ubuntu и Debian.${NC}"
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)   ARCH_NAME="amd64" ;;
    aarch64|arm64)  ARCH_NAME="arm64" ;;
    armv7l)         ARCH_NAME="armv7l" ;;
    *)              ARCH_NAME="$ARCH" ;;
esac

# ---------------------- Глобальные переменные состояния ----------------------
STATE_DOCKER_INSTALLED=false
STATE_COMPOSE_INSTALLED=false
STATE_NGINX_INSTALLED=false
STATE_CERTBOT_INSTALLED=false
STATE_BOT_INSTALLED=false
STATE_BOT_RUNNING=false
STATE_CABINET_INSTALLED=false
STATE_WEBHOOK_NGINX=false
STATE_CABINET_NGINX=false
STATE_SSL_EXISTS=false
STATE_MAIN_DOMAIN=""
STATE_WEBHOOK_DOMAIN=""
STATE_CABINET_DOMAIN=""
STATE_HTTPS_PORT=""
STATE_BOT_PORT=""
STATE_BOT_ENV_FILE=""

# ---------------------- Функция диагностики ----------------------
diagnose() {
    echo -e "${CYAN}${BOLD}🔍 Диагностика системы...${NC}"

    # Docker
    if command -v docker &> /dev/null; then
        STATE_DOCKER_INSTALLED=true
        if docker compose version &> /dev/null; then
            STATE_COMPOSE_INSTALLED=true
        fi
    fi

    # Nginx
    if command -v nginx &> /dev/null; then
        STATE_NGINX_INSTALLED=true
    fi

    # Certbot
    if command -v certbot &> /dev/null; then
        STATE_CERTBOT_INSTALLED=true
    fi

    # Bot: проверяем папку и контейнер
    if [[ -d "/opt/remnawave-bedolaga-telegram-bot" ]]; then
        STATE_BOT_INSTALLED=true
        STATE_BOT_ENV_FILE="/opt/remnawave-bedolaga-telegram-bot/.env"
        # Проверяем, запущен ли контейнер
        if docker ps --filter "name=bot" --format '{{.Names}}' | grep -q "bot"; then
            STATE_BOT_RUNNING=true
        fi
        # Пытаемся извлечь домены из .env
        if [[ -f "$STATE_BOT_ENV_FILE" ]]; then
            STATE_WEBHOOK_DOMAIN=$(grep -E "^WEBHOOK_URL=" "$STATE_BOT_ENV_FILE" | sed -E 's|^WEBHOOK_URL=https?://([^:/]+).*$|\1|')
            STATE_CABINET_DOMAIN=$(grep -E "^CABINET_ALLOWED_ORIGINS=" "$STATE_BOT_ENV_FILE" | sed -E 's|^.*https?://([^:/]+).*$|\1|')
            STATE_MAIN_DOMAIN=$(echo "$STATE_WEBHOOK_DOMAIN" | sed -E 's/^[^.]+\.//')
            # Порты
            STATE_HTTPS_PORT=$(grep -E "^WEBHOOK_URL=" "$STATE_BOT_ENV_FILE" | sed -E 's|^.*:([0-9]+).*$|\1|')
            STATE_BOT_PORT=$(grep -E "^WEB_API_PORT=" "$STATE_BOT_ENV_FILE" | sed -E 's|^WEB_API_PORT=(.*)$|\1|')
        fi
    fi

    # Cabinet: проверяем папку со статикой
    if [[ -d "/srv/cabinet" ]]; then
        STATE_CABINET_INSTALLED=true
    fi

    # Nginx конфигурации
    if [[ -f "/etc/nginx/sites-available/bedolaga-webhook" ]]; then
        STATE_WEBHOOK_NGINX=true
    fi
    if [[ -f "/etc/nginx/sites-available/bedolaga-cabinet" ]]; then
        STATE_CABINET_NGINX=true
    fi

    # SSL (ищем сертификат для основного домена)
    if [[ -n "$STATE_MAIN_DOMAIN" ]] && [[ -f "/etc/letsencrypt/live/$STATE_MAIN_DOMAIN/fullchain.pem" ]]; then
        STATE_SSL_EXISTS=true
    fi

    # Если не удалось определить домен из .env, попробуем из конфигов Nginx
    if [[ -z "$STATE_MAIN_DOMAIN" ]] && [[ -f "/etc/nginx/sites-available/bedolaga-webhook" ]]; then
        STATE_MAIN_DOMAIN=$(grep -E "server_name" /etc/nginx/sites-available/bedolaga-webhook | head -1 | awk '{print $2}' | sed -E 's/^[^.]+\.//' | sed 's/;$//')
    fi

    # Если не удалось определить HTTPS-порт из .env, попробуем из конфигов
    if [[ -z "$STATE_HTTPS_PORT" ]] && [[ -f "/etc/nginx/sites-available/bedolaga-webhook" ]]; then
        STATE_HTTPS_PORT=$(grep -E "listen" /etc/nginx/sites-available/bedolaga-webhook | grep -oE '[0-9]+' | head -1)
    fi

    echo -e "${GREEN}✅ Диагностика завершена.${NC}"
}

# ---------------------- Вывод состояния ----------------------
print_state() {
    echo -e "\n${CYAN}${BOLD}📊 Текущее состояние:${NC}"
    echo -e "  Docker:           $([ "$STATE_DOCKER_INSTALLED" == true ] && echo -e "${GREEN}✅ установлен${NC}" || echo -e "${RED}❌ не установлен${NC}")"
    echo -e "  Docker Compose:   $([ "$STATE_COMPOSE_INSTALLED" == true ] && echo -e "${GREEN}✅ установлен${NC}" || echo -e "${RED}❌ не установлен${NC}")"
    echo -e "  Nginx:            $([ "$STATE_NGINX_INSTALLED" == true ] && echo -e "${GREEN}✅ установлен${NC}" || echo -e "${RED}❌ не установлен${NC}")"
    echo -e "  Certbot:          $([ "$STATE_CERTBOT_INSTALLED" == true ] && echo -e "${GREEN}✅ установлен${NC}" || echo -e "${RED}❌ не установлен${NC}")"
    echo -e "  Bot:              $([ "$STATE_BOT_INSTALLED" == true ] && echo -e "${GREEN}✅ установлен${NC} $([ "$STATE_BOT_RUNNING" == true ] && echo -e "${GREEN}(запущен)${NC}" || echo -e "${YELLOW}(остановлен)${NC}")" || echo -e "${RED}❌ не установлен${NC}")"
    echo -e "  Cabinet:          $([ "$STATE_CABINET_INSTALLED" == true ] && echo -e "${GREEN}✅ установлен${NC}" || echo -e "${RED}❌ не установлен${NC}")"
    echo -e "  Nginx config bot: $([ "$STATE_WEBHOOK_NGINX" == true ] && echo -e "${GREEN}✅ есть${NC}" || echo -e "${RED}❌ нет${NC}")"
    echo -e "  Nginx config cab: $([ "$STATE_CABINET_NGINX" == true ] && echo -e "${GREEN}✅ есть${NC}" || echo -e "${RED}❌ нет${NC}")"
    echo -e "  SSL сертификат:   $([ "$STATE_SSL_EXISTS" == true ] && echo -e "${GREEN}✅ есть${NC}" || echo -e "${RED}❌ нет${NC}")"
    if [[ -n "$STATE_MAIN_DOMAIN" ]]; then
        echo -e "  Основной домен:   ${CYAN}$STATE_MAIN_DOMAIN${NC}"
    fi
    if [[ -n "$STATE_WEBHOOK_DOMAIN" ]]; then
        echo -e "  Домен вебхука:    ${CYAN}$STATE_WEBHOOK_DOMAIN${NC}"
    fi
    if [[ -n "$STATE_CABINET_DOMAIN" ]]; then
        echo -e "  Домен кабинета:   ${CYAN}$STATE_CABINET_DOMAIN${NC}"
    fi
    if [[ -n "$STATE_HTTPS_PORT" ]]; then
        echo -e "  HTTPS порт:       ${CYAN}$STATE_HTTPS_PORT${NC}"
    fi
}

# ---------------------- Вспомогательные функции (без изменений) ----------------------
is_port_in_use() {
    ss -tulpn | grep -q ":$1 "
}

find_telegram_port() {
    local allowed_ports=(88 8443 443)
    for port in "${allowed_ports[@]}"; do
        if is_port_in_use $port; then
            local process=$(ss -tulpn | grep ":$port " | awk '{print $7}' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
            if [[ -n $process ]]; then
                local proc_name=$(ps -p $process -o comm= 2>/dev/null)
                if [[ "$proc_name" == "nginx" ]]; then
                    >&2 echo -e "${YELLOW}⚠️ Порт $port занят Nginx (используем его).${NC}"
                    echo "$port"
                    return 0
                fi
            fi
            >&2 echo -e "${YELLOW}⚠️ Порт $port занят другим процессом, пробуем следующий...${NC}"
        else
            echo "$port"
            return 0
        fi
    done
    >&2 echo -e "${RED}❌ Все разрешённые порты (88, 8443, 443) заняты другими процессами.${NC}"
    exit 1
}

collect_common_data() {
    echo -e "${YELLOW}Введите основной домен (например, example.com), который уже используется для вашей ноды:${NC}"
    read -p "Основной домен: " MAIN_DOMAIN

    echo -e "${YELLOW}Введите поддомен для вебхука бота (например, hooks.$MAIN_DOMAIN):${NC}"
    read -p "Поддомен вебхука: " WEBHOOK_DOMAIN

    echo -e "${YELLOW}Введите поддомен для веб-кабинета (например, cabinet.$MAIN_DOMAIN):${NC}"
    read -p "Поддомен кабинета: " CABINET_DOMAIN

    echo -e "${YELLOW}Введите токен бота от @BotFather:${NC}"
    read -sp "Токен бота: " BOT_TOKEN; echo

    echo -e "${YELLOW}Введите ваш Telegram ID (администратора):${NC}"
    read -p "Telegram ID: " ADMIN_IDS

    echo -e "${YELLOW}Введите API URL панели Remnawave (например, https://panel.$MAIN_DOMAIN):${NC}"
    read -p "API URL панели: " REMNAWAVE_API_URL

    echo -e "${YELLOW}Введите API KEY от панели Remnawave:${NC}"
    read -sp "API KEY: " REMNAWAVE_API_KEY; echo

    WEBHOOK_SECRET=$(openssl rand -hex 32)
    CABINET_JWT_SECRET=$(openssl rand -hex 32)
}

check_dns() {
    local domain=$1
    if ! command -v dig &> /dev/null; then
        apt-get update && apt-get install -y dnsutils
    fi
    local SERVER_IP=$(curl -s ifconfig.me)
    if [[ -z "$SERVER_IP" ]]; then
        echo -e "${RED}❌ Не удалось получить внешний IP сервера.${NC}"
        return 1
    fi
    if ! dig +short "$domain" | grep -q "$SERVER_IP"; then
        echo -e "${RED}⚠️ DNS-запись для $domain не указывает на этот сервер.${NC}"
        read -p "Продолжить? (y/N) " ans
        [[ ! "$ans" =~ ^[Yy]$ ]] && return 1
    else
        echo -e "${GREEN}✅ $domain -> OK${NC}"
    fi
    return 0
}

install_docker() {
    echo -e "${YELLOW}➜ Проверка Docker...${NC}"
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Установка Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        if [[ -n "$SUDO_USER" ]]; then
            usermod -aG docker "$SUDO_USER"
        else
            usermod -aG docker "$USER"
        fi
    fi
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Установка Docker Compose plugin...${NC}"
        apt-get update && apt-get install -y docker-compose-plugin
    fi
    echo -e "${GREEN}✅ Docker готов.${NC}"
}

install_nginx() {
    echo -e "${YELLOW}➜ Проверка Nginx...${NC}"
    if ! command -v nginx &> /dev/null; then
        apt-get update && apt-get install -y nginx
        systemctl enable nginx && systemctl start nginx
    fi
    echo -e "${GREEN}✅ Nginx установлен.${NC}"
}

install_certbot() {
    echo -e "${YELLOW}➜ Проверка Certbot и плагина Nginx...${NC}"
    if ! command -v certbot &> /dev/null; then
        apt-get update && apt-get install -y certbot python3-certbot-nginx
    else
        if ! certbot plugins | grep -q "nginx"; then
            apt-get update && apt-get install -y python3-certbot-nginx
        fi
    fi
    echo -e "${GREEN}✅ Certbot и плагин готовы.${NC}"
}

open_firewall_ports() {
    local ports=("$@")
    echo -e "${YELLOW}➜ Открываем порты в фаерволе...${NC}"
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        for port in "${ports[@]}"; do
            ufw allow "$port"/tcp || true
        done
        ufw reload
        echo -e "${GREEN}✅ Порты ${ports[*]} открыты через UFW.${NC}"
    elif command -v iptables &> /dev/null; then
        for port in "${ports[@]}"; do
            if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
                iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
            fi
        done
        if command -v netfilter-persistent &> /dev/null; then
            netfilter-persistent save
        elif command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        echo -e "${GREEN}✅ Порты ${ports[*]} открыты через iptables.${NC}"
    else
        echo -e "${YELLOW}⚠️ Не найден фаервол, откройте порты ${ports[*]} вручную.${NC}"
    fi
}

# ---------------------- Установка компонентов ----------------------

install_nginx_ssl() {
    echo -e "${BLUE}${BOLD}➜ Установка Nginx и SSL-сертификатов${NC}"
    if [[ -z "$MAIN_DOMAIN" || -z "$WEBHOOK_DOMAIN" || -z "$CABINET_DOMAIN" ]]; then
        echo -e "${YELLOW}Не все домены заданы. Введите данные.${NC}"
        collect_common_data
    fi
    install_nginx
    install_certbot
    check_dns "$WEBHOOK_DOMAIN" || exit 1
    check_dns "$CABINET_DOMAIN" || exit 1

    HTTPS_PORT=$(find_telegram_port)
    echo -e "${GREEN}✅ Выбран внешний HTTPS-порт: $HTTPS_PORT${NC}"

    open_firewall_ports 80 "$HTTPS_PORT"

    # Временные конфиги (HTTP)
    echo -e "${YELLOW}➜ Создание временных конфигураций Nginx (только HTTP)...${NC}"
    rm -f /etc/nginx/sites-enabled/default

    cat > /etc/nginx/sites-available/bedolaga-webhook <<EOF
server {
    listen 80;
    server_name $WEBHOOK_DOMAIN;
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
    echo -e "${GREEN}✅ Nginx перезагружен (только HTTP).${NC}"

    # SSL
    echo -e "${YELLOW}➜ Получение SSL-сертификатов...${NC}"
    if certbot certificates 2>/dev/null | grep -q "Domains:.*$MAIN_DOMAIN"; then
        echo -e "${YELLOW}Обнаружен существующий сертификат для $MAIN_DOMAIN. Расширяем...${NC}"
        certbot --nginx -d "$MAIN_DOMAIN" -d "$WEBHOOK_DOMAIN" -d "$CABINET_DOMAIN" \
                --expand --non-interactive --agree-tos --email "admin@$MAIN_DOMAIN" || true
    else
        certbot --nginx -d "$MAIN_DOMAIN" -d "$WEBHOOK_DOMAIN" -d "$CABINET_DOMAIN" \
                --non-interactive --agree-tos --email "admin@$MAIN_DOMAIN" || true
    fi

    if [ -f "/etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem" ]; then
        echo -e "${GREEN}✅ SSL-сертификаты успешно получены.${NC}"
    else
        echo -e "${RED}❌ Не удалось получить сертификаты. Проверьте порт 80 и DNS.${NC}"
        exit 1
    fi

    # SSL + редирект
    echo -e "${YELLOW}➜ Добавляем SSL и редирект...${NC}"
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

    nginx -t && systemctl reload nginx
    echo -e "${GREEN}✅ Nginx перезагружен с SSL.${NC}"
}

install_bot() {
    echo -e "${BLUE}${BOLD}➜ Установка Bedolaga Bot${NC}"
    if [[ -z "$MAIN_DOMAIN" || -z "$WEBHOOK_DOMAIN" || -z "$CABINET_DOMAIN" || -z "$BOT_TOKEN" || -z "$ADMIN_IDS" || -z "$REMNAWAVE_API_URL" || -z "$REMNAWAVE_API_KEY" ]]; then
        echo -e "${YELLOW}Необходимо ввести данные для бота.${NC}"
        collect_common_data
    fi
    if [[ -z "$HTTPS_PORT" ]]; then
        HTTPS_PORT=$(find_telegram_port)
    fi
    if [[ -z "$HOST_BOT_PORT" ]]; then
        HOST_BOT_PORT=8081
        while is_port_in_use $HOST_BOT_PORT; do
            HOST_BOT_PORT=$((HOST_BOT_PORT + 1))
        done
    fi

    install_docker
    open_firewall_ports "$HOST_BOT_PORT"

    echo -e "${YELLOW}➜ Клонирование бота...${NC}"
    cd /opt
    if [[ -d "remnawave-bedolaga-telegram-bot" ]]; then
        cd remnawave-bedolaga-telegram-bot && git pull
    else
        git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git
        cd remnawave-bedolaga-telegram-bot
    fi

    mkdir -p data/backups logs locales
    chmod -R 775 data logs locales

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
WEB_API_PORT=8080
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN:$HTTPS_PORT
WEB_API_ALLOWED_ORIGINS=https://$CABINET_DOMAIN:$HTTPS_PORT
EOF

    if ! grep -q "$HOST_BOT_PORT:8080" docker-compose.yml; then
        if grep -q "ports:" docker-compose.yml; then
            sed -i "/ports:/a \      - \"$HOST_BOT_PORT:8080\"" docker-compose.yml
        else
            sed -i "/image:/a \    ports:\n      - \"$HOST_BOT_PORT:8080\"" docker-compose.yml
        fi
    fi

    docker compose up -d
    echo -e "${GREEN}✅ Bedolaga Bot запущен.${NC}"
    sleep 10

    echo -e "${YELLOW}➜ Установка вебхука в Telegram...${NC}"
    WEBHOOK_URL="https://$WEBHOOK_DOMAIN:$HTTPS_PORT/webhook"
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" \
        -d "url=$WEBHOOK_URL&secret_token=$WEBHOOK_SECRET")
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "${GREEN}✅ Вебхук успешно установлен на $WEBHOOK_URL${NC}"
    else
        echo -e "${RED}❌ Не удалось установить вебхук. Ответ: $RESPONSE${NC}"
        echo -e "${YELLOW}Попробуйте установить вручную:${NC}"
        echo "curl -X POST 'https://api.telegram.org/bot$BOT_TOKEN/setWebhook' -d 'url=$WEBHOOK_URL&secret_token=$WEBHOOK_SECRET'"
    fi
}

install_cabinet() {
    echo -e "${BLUE}${BOLD}➜ Установка Bedolaga Cabinet${NC}"
    if [[ -z "$CABINET_DOMAIN" ]]; then
        echo -e "${RED}❌ Не задан домен кабинета. Сначала введите общие данные.${NC}"
        collect_common_data
    fi
    install_docker

    echo -e "${YELLOW}➜ Загрузка файлов Cabinet...${NC}"
    mkdir -p /srv/cabinet
    docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker cp tmp_cabinet:/usr/share/nginx/html/. /srv/cabinet/
    docker rm tmp_cabinet
    chown -R www-data:www-data /srv/cabinet
    echo -e "${GREEN}✅ Файлы Cabinet размещены.${NC}"
}

install_all() {
    echo -e "${BLUE}${BOLD}➜ Полная установка (Bot + Cabinet + Nginx + SSL)${NC}"
    collect_common_data
    HTTPS_PORT=$(find_telegram_port)
    HOST_BOT_PORT=8081
    while is_port_in_use $HOST_BOT_PORT; do
        HOST_BOT_PORT=$((HOST_BOT_PORT + 1))
    done
    install_nginx_ssl
    install_bot
    install_cabinet
    systemctl reload nginx
    echo -e "${GREEN}✅ Полная установка завершена!${NC}"
}

# ---------------------- Удаление ----------------------
remove_bot() {
    echo -e "${RED}➜ Удаление Bedolaga Bot${NC}"
    cd /opt/remnawave-bedolaga-telegram-bot 2>/dev/null && docker compose down -v || true
    rm -rf /opt/remnawave-bedolaga-telegram-bot
    echo -e "${GREEN}✅ Бот удалён.${NC}"
}

remove_cabinet() {
    echo -e "${RED}➜ Удаление Bedolaga Cabinet${NC}"
    rm -rf /srv/cabinet
    echo -e "${GREEN}✅ Cabinet удалён.${NC}"
}

remove_nginx_ssl() {
    echo -e "${RED}➜ Удаление Nginx конфигураций и SSL${NC}"
    rm -f /etc/nginx/sites-available/bedolaga-webhook
    rm -f /etc/nginx/sites-available/bedolaga-cabinet
    rm -f /etc/nginx/sites-enabled/bedolaga-webhook
    rm -f /etc/nginx/sites-enabled/bedolaga-cabinet
    systemctl reload nginx
    if [[ -n "$STATE_MAIN_DOMAIN" ]]; then
        certbot delete --cert-name "$STATE_MAIN_DOMAIN" 2>/dev/null || true
    fi
    echo -e "${GREEN}✅ Конфигурации Nginx и SSL удалены.${NC}"
}

# ---------------------- Меню с рекомендациями ----------------------
show_menu() {
    clear
    echo -e "${CYAN}${BOLD}========================================${NC}"
    echo -e "${CYAN}${BOLD}  Установщик Bedolaga Bot + Cabinet   ${NC}"
    echo -e "${CYAN}${BOLD}  Версия 4.0.0 (с диагностикой)      ${NC}"
    echo -e "${CYAN}${BOLD}========================================${NC}"
    echo -e ""
    print_state
    echo -e ""
    echo -e "${BOLD}Рекомендация:${NC}"
    # Формируем рекомендацию
    if [[ "$STATE_DOCKER_INSTALLED" == false ]] || [[ "$STATE_NGINX_INSTALLED" == false ]] || [[ "$STATE_BOT_INSTALLED" == false ]] || [[ "$STATE_CABINET_INSTALLED" == false ]]; then
        if [[ "$STATE_DOCKER_INSTALLED" == false ]] || [[ "$STATE_NGINX_INSTALLED" == false ]]; then
            echo -e "  ${GREEN}➜ Рекомендуется выбрать пункт 1 (полная установка)${NC}"
        elif [[ "$STATE_BOT_INSTALLED" == false ]] && [[ "$STATE_CABINET_INSTALLED" == false ]]; then
            echo -e "  ${GREEN}➜ Рекомендуется выбрать пункт 5 (установить бота и кабинет)${NC}"
        elif [[ "$STATE_BOT_INSTALLED" == false ]]; then
            echo -e "  ${GREEN}➜ Рекомендуется выбрать пункт 3 (установить только бота)${NC}"
        elif [[ "$STATE_CABINET_INSTALLED" == false ]]; then
            echo -e "  ${GREEN}➜ Рекомендуется выбрать пункт 4 (установить только кабинет)${NC}"
        fi
    else
        echo -e "  ${YELLOW}➜ Все компоненты уже установлены. Вы можете обновить или удалить их.${NC}"
    fi
    echo -e ""
    echo -e "${BOLD}Выберите действие:${NC}"
    echo -e "  ${GREEN}1${NC}) Установить всё (Bot + Cabinet + Nginx + SSL)"
    echo -e "  ${GREEN}2${NC}) Установить только Nginx и SSL (для существующих бота/кабинета)"
    echo -e "  ${GREEN}3${NC}) Установить только Bot (с Docker и вебхуком)"
    echo -e "  ${GREEN}4${NC}) Установить только Cabinet (фронтенд)"
    echo -e "  ${GREEN}5${NC}) Установить Bot + Cabinet (без Nginx/SSL, если они уже есть)"
    echo -e "  ${RED}6${NC}) Удалить Bot"
    echo -e "  ${RED}7${NC}) Удалить Cabinet"
    echo -e "  ${RED}8${NC}) Удалить Nginx конфигурации и SSL"
    echo -e "  ${RED}9${NC}) Полное удаление (Bot + Cabinet + Nginx + SSL)"
    echo -e "  ${CYAN}0${NC}) Выход"
    echo ""
    read -p "Введите номер: " choice
    case $choice in
        1) install_all ;;
        2) install_nginx_ssl ;;
        3) install_bot ;;
        4) install_cabinet ;;
        5)
            install_bot
            install_cabinet
            ;;
        6) remove_bot ;;
        7) remove_cabinet ;;
        8) remove_nginx_ssl ;;
        9)
            remove_bot
            remove_cabinet
            remove_nginx_ssl
            echo -e "${GREEN}✅ Полное удаление завершено.${NC}"
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}Неверный выбор.${NC}"; sleep 2 ;;
    esac
    read -p "Нажмите Enter, чтобы продолжить..."
}

# ---------------------- Запуск ----------------------
diagnose
while true; do
    show_menu
done
