#!/bin/bash

# ============================================
# Just Remnawave Auto Installer (Nginx + Let's Encrypt)
# Автоматическое получение и продление сертификатов через ACME
# Автор: tneangel / Santey990
# Версия: 2.0 (Nginx + Certbot)
# ============================================

# Цвета
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ошибка: Скрипт нужно запускать от имени root (sudo).${NC}"
    exit 1
fi

# Глобальный алиас
create_alias() {
    if [ ! -f /usr/local/bin/rw-installer ]; then
        echo -e "${YELLOW}📥 Скачиваем скрипт для глобального доступа...${NC}"
        curl -Ls https://raw.githubusercontent.com/Santey990/Remnawave-bedolaga-Auto-Installer/main/setup.sh -o /usr/local/bin/rw-installer
        chmod +x /usr/local/bin/rw-installer
        echo -e "${GREEN}✅ Создан глобальный алиас: теперь можно запускать командой ${BOLD}rw-installer${NC}${GREEN} из любой директории.${NC}"
    fi
}

# Логотип
show_logo() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║   ⚡ Remnawave + Bedolaga Auto Installer (Let's Encrypt) ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Установка Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker не найден. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}✅ Docker успешно установлен.${NC}"
    else
        echo -e "${GREEN}✅ Docker уже установлен.${NC}"
    fi
}

# ============================================
# NGINX + LET'S ENCRYPT (ACME)
# ============================================

install_nginx_certbot() {
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}📦 Устанавливаем Nginx, Certbot и плагин...${NC}"
        apt-get update -qq
        apt-get install -y -qq nginx certbot python3-certbot-nginx
        systemctl enable nginx
        systemctl start nginx
        echo -e "${GREEN}✅ Nginx и Certbot установлены.${NC}"
    else
        echo -e "${GREEN}✅ Nginx уже установлен.${NC}"
        if ! command -v certbot &> /dev/null; then
            apt-get install -y -qq certbot python3-certbot-nginx
        fi
    fi
}

add_nginx_block() {
    local domain="$1"
    local config_content="$2"   # содержимое location / и т.д.
    local available="/etc/nginx/sites-available/$domain"
    local enabled="/etc/nginx/sites-enabled/$domain"
    local email="admin@${domain}"   # можно изменить на ваш email

    # Создаём конфиг ТОЛЬКО на порту 80 (без SSL)
    cat > "$available" <<EOF
server {
    listen 80;
    server_name $domain;
    root /var/www/html;

    location /.well-known/acme-challenge/ {
        allow all;
        root /var/www/html;
    }

    location / {
        # Временно проксируем (certbot позже добавит SSL)
        $config_content
    }
}
EOF

    if [ ! -L "$enabled" ]; then
        ln -s "$available" "$enabled"
    fi

    echo -e "${GREEN}✅ Конфиг Nginx для $domain создан (порт 80).${NC}"
    nginx -t && systemctl reload nginx

    # Получаем сертификат через certbot (автоматически добавит SSL-блок)
    echo -e "${YELLOW}🔐 Запрашиваем Let's Encrypt сертификат для $domain...${NC}"
    certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" --redirect --quiet
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Сертификат успешно получен и применён.${NC}"
    else
        echo -e "${RED}❌ Не удалось получить сертификат. Проверьте доступность домена из интернета и открытый порт 80.${NC}"
        echo -e "${YELLOW}⚠️  Сайт будет работать по HTTP, но HTTPS недоступен.${NC}"
    fi
}

remove_nginx_block() {
    local domain="$1"
    local available="/etc/nginx/sites-available/$domain"
    local enabled="/etc/nginx/sites-enabled/$domain"

    if [ -f "$available" ]; then
        rm -f "$available"
        echo -e "${GREEN}✅ Конфиг для $domain удалён.${NC}"
    fi
    if [ -L "$enabled" ]; then
        rm -f "$enabled"
    fi

    # Удаляем сертификат (опционально)
    certbot delete --cert-name "$domain" --non-interactive 2>/dev/null
    echo -e "${GREEN}✅ Сертификат для $domain удалён (если существовал).${NC}"

    nginx -t && systemctl reload nginx
}

ensure_nginx_running() {
    if ! systemctl is-active --quiet nginx; then
        echo -e "${YELLOW}⚠️  Nginx не запущен. Запускаем...${NC}"
        systemctl start nginx
    fi
    if ! command -v nginx &> /dev/null; then
        echo -e "${RED}❌ Nginx не установлен. Установите через пункт меню или вручную.${NC}"
        return 1
    fi
    return 0
}

# ============================================
# ОПЦИЯ 1: REMNAWAVE (Panel + Node)
# ============================================

install_panel() {
    show_logo
    echo -e "${BLUE}${BOLD}🚀 Установка Remnawave Panel + Subscription Page${NC}\n"

    read -p "🌐 Введите домен для ПАНЕЛИ (например panel.myvpn.com): " PANEL_DOMAIN
    read -p "🌐 Введите домен для СТРАНИЦЫ ПОДПИСКИ (например sub.myvpn.com): " SUB_DOMAIN

    if [ -z "$PANEL_DOMAIN" ] || [ -z "$SUB_DOMAIN" ]; then
        echo -e "${RED}❌ Ошибка: Домены не могут быть пустыми!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    install_docker
    install_nginx_certbot
    ensure_nginx_running

    echo -e "\n${YELLOW}📥 Шаг 1. Скачиваем конфигурационные файлы...${NC}"
    mkdir -p /opt/remnawave && cd /opt/remnawave
    curl -s -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
    curl -s -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample

    echo -e "${YELLOW}🔐 Шаг 2. Генерируем секретные ключи...${NC}"
    sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
    sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env
    sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
    sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env

    pw=$(openssl rand -hex 24)
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
    sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env

    echo -e "${YELLOW}🌐 Шаг 3. Настраиваем домены...${NC}"
    sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$PANEL_DOMAIN|" .env
    sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_DOMAIN|" .env

    # Добавляем проброс портов на localhost в docker-compose.yml
    echo -e "${YELLOW}🔧 Шаг 4. Настраиваем проброс портов для Nginx...${NC}"
    sed -i '/remnawave:/,/^[^ ]/ {
        /ports:/d
        /environment:/a\    ports:\n      - "127.0.0.1:3000:3000"
    }' docker-compose.yml

    echo -e "${YELLOW}🚀 Шаг 5. Запускаем основную панель...${NC}"
    docker compose up -d
    echo -e "${GREEN}✅ Панель запущена. Ожидаем инициализацию БД...${NC}"
    sleep 20

    echo -e "\n${YELLOW}🔧 Шаг 6. Настраиваем Nginx для панели...${NC}"
    PANEL_BLOCK="
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
    "
    add_nginx_block "$PANEL_DOMAIN" "$PANEL_BLOCK"

    echo -e "\n${YELLOW}${BOLD}⚠️  ВАЖНО: Создайте API Token в админке!${NC}"
    echo -e "1. Откройте в браузере: ${CYAN}https://$PANEL_DOMAIN${NC}"
    echo -e "2. Зарегистрируйтесь (первый вход)"
    echo -e "3. Перейдите в ${BOLD}Settings → API Tokens${NC} и создайте токен"
    echo -e "4. Скопируйте его и вставьте ниже\n"
    read -p "🔑 Вставьте API TOKEN: " API_TOKEN

    if [ -z "$API_TOKEN" ]; then
        echo -e "${RED}❌ Токен не введён. Страница подписки не будет установлена.${NC}"
    else
        echo -e "\n${YELLOW}📄 Шаг 7. Устанавливаем страницу подписки...${NC}"
        mkdir -p /opt/remnawave/subscription && cd /opt/remnawave/subscription

        cat > .env <<EOF
APP_PORT=3010
REMNAWAVE_PANEL_URL=http://remnawave:3000
REMNAWAVE_API_TOKEN=$API_TOKEN
TRUST_PROXY=1
EOF

        cat > docker-compose.yml <<EOF
services:
    remnawave-subscription-page:
        image: remnawave/subscription-page:latest
        container_name: remnawave-subscription-page
        hostname: remnawave-subscription-page
        restart: always
        env_file:
            - .env
        ports:
            - '127.0.0.1:3010:3010'
        networks:
            - remnawave-network
networks:
    remnawave-network:
        driver: bridge
        external: true
EOF
        docker compose up -d
        echo -e "${GREEN}✅ Страница подписки запущена.${NC}"

        echo -e "${YELLOW}🔄 Шаг 8. Добавляем домен подписки в Nginx...${NC}"
        SUB_BLOCK="
        location / {
            proxy_pass http://127.0.0.1:3010;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
        }
        "
        add_nginx_block "$SUB_DOMAIN" "$SUB_BLOCK"
    fi

    echo -e "\n${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ УСТАНОВКА ПАНЕЛИ ЗАВЕРШЕНА! 🎉                     ║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}🌐 Админка:  ${BOLD}https://$PANEL_DOMAIN${NC}"
    echo -e "${CYAN}📄 Подписка: ${BOLD}https://$SUB_DOMAIN${NC}"
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

install_node() {
    show_logo
    echo -e "${BLUE}${BOLD}🖥️  Установка Remnawave Node${NC}\n"
    echo -e "${YELLOW}⚠️  Нода устанавливается на ОТДЕЛЬНЫЙ сервер!${NC}\n"

    install_docker

    read -p "🔑 Введите SECRET KEY ноды (из панели): " NODE_SECRET
    read -p "🔌 Введите NODE PORT (по умолчанию 2222): " NODE_PORT

    if [ -z "$NODE_PORT" ]; then
        NODE_PORT=2222
    fi

    if [ -z "$NODE_SECRET" ]; then
        echo -e "${RED}❌ Ошибка: Secret Key обязателен!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "\n${YELLOW}📥 Настраиваем ноду...${NC}"
    mkdir -p /opt/remnanode && cd /opt/remnanode

    cat > docker-compose.yml <<EOF
services:
    remnanode:
        image: remnawave/node:latest
        container_name: remnanode
        hostname: remnanode
        restart: always
        network_mode: host
        environment:
            - NODE_PORT=$NODE_PORT
            - SECRET_KEY=$NODE_SECRET
EOF

    echo -e "${YELLOW}🚀 Запускаем ноду...${NC}"
    docker compose up -d
    echo -e "${GREEN}✅ Нода запущена!${NC}"

    echo -e "\n${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         ✅ НОДА УСТАНОВЛЕНА! 🎉                          ║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}⚠️  ВАЖНО: Закройте порт ${BOLD}$NODE_PORT${NC}${YELLOW} в фаерволе ноды"
    echo -e "   для всех, КРОМЕ IP-адреса основной панели!${NC}"
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_components() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление компонентов Remnawave${NC}\n"

    echo -e "${BOLD}Что хотите обновить?${NC}"
    echo -e "  ${CYAN}1)${NC} 🚀 Обновить Панель + Страницу подписки"
    echo -e "  ${CYAN}2)${NC} 🖥️  Обновить Ноду"
    echo -e "  ${CYAN}0)${NC} 🔙 Назад"
    echo ""
    read -p "${CYAN}▶${NC} Ваш выбор: " update_choice

    case $update_choice in
        1) update_panel ;;
        2) update_node ;;
        0) return ;;
        *)
            echo -e "${RED}❌ Неверный выбор.${NC}"
            sleep 2
            ;;
    esac
}

update_panel() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Panel + Subscription Page${NC}\n"

    if [ ! -d "/opt/remnawave" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnawave не найдена.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем основную панель...${NC}"
    cd /opt/remnawave
    docker compose pull
    docker compose down
    docker compose up -d
    echo -e "${GREEN}✅ Панель обновлена.${NC}"

    if [ -d "/opt/remnawave/subscription" ]; then
        echo -e "${YELLOW}📄 Обновляем страницу подписки...${NC}"
        cd /opt/remnawave/subscription
        docker compose pull
        docker compose down
        docker compose up -d
        echo -e "${GREEN}✅ Страница подписки обновлена.${NC}"
    fi

    docker image prune -f
    echo -e "\n${GREEN}✅ ОБНОВЛЕНИЕ ЗАВЕРШЕНО!${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_node() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Node${NC}\n"

    if [ ! -d "/opt/remnanode" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnanode не найдена.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    cd /opt/remnanode
    docker compose pull
    docker compose down
    docker compose up -d
    docker image prune -f
    echo -e "${GREEN}✅ Нода обновлена.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 2: BEDOLAGA (Bot + MiniAPP)
# ============================================

show_bedolaga_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}💰 Bedolaga (Bot + MiniAPP)${NC}\n"
        echo -e "  ${CYAN}1)${NC} Установить Bedolaga Bot"
        echo -e "  ${CYAN}2)${NC} Установить MiniAPP (Cabinet)"
        echo -e "  ${CYAN}3)${NC} Обновить компоненты"
        echo -e "  ${CYAN}4)${NC} 🌐 Настроить Nginx для Bedolaga"
        echo -e "  ${CYAN}0)${NC} Назад"
        read -p "${CYAN}▶${NC} Ваш выбор: " choice

        case $choice in
            1) install_bedolaga ;;
            2) install_cabinet ;;
            3) update_bedolaga ;;
            4) setup_nginx_for_bedolaga ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

install_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}💰 Установка Bedolaga Bot${NC}\n"

    install_docker
    install_nginx_certbot
    ensure_nginx_running

    echo -e "${YELLOW}Где устанавливается бот?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    read -p "${CYAN}▶${NC} Ваш выбор: " server_location

    if [[ "$server_location" == "1" ]]; then
        REMNAWAVE_API_URL="http://remnawave:3000"
        echo -e "${GREEN}✅ Используется внутренний адрес: $REMNAWAVE_API_URL${NC}"
    else
        read -p "🌐 Введите домен панели Remnawave: " PANEL_DOMAIN
        REMNAWAVE_API_URL="https://$PANEL_DOMAIN"
    fi

    read -p "🤖 BOT_TOKEN (от @BotFather): " BOT_TOKEN
    read -p "👤 ADMIN_IDS (Telegram ID через запятую): " ADMIN_IDS
    read -p "🔑 REMNAWAVE_API_KEY (API ключ из панели): " REMNAWAVE_API_KEY
    read -p "🌐 Домен для бота (например bedolaga.myvpn.com): " BEDOLAGA_DOMAIN

    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    WEBHOOK_SECRET_TOKEN=$(openssl rand -hex 32)
    WEB_API_DEFAULT_TOKEN=$(openssl rand -hex 32)

    mkdir -p /opt/bedolaga-bot && cd /opt/bedolaga-bot
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git .

    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
REMNAWAVE_API_URL=$REMNAWAVE_API_URL
REMNAWAVE_API_KEY=$REMNAWAVE_API_KEY
REMNAWAVE_AUTH_TYPE=api_key
POSTGRES_DB=remnawave_bot
POSTGRES_USER=remnawave_user
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
BOT_RUN_MODE=webhook
WEBHOOK_URL=https://$BEDOLAGA_DOMAIN
WEBHOOK_PATH=/webhook
WEBHOOK_SECRET_TOKEN=$WEBHOOK_SECRET_TOKEN
WEBHOOK_DROP_PENDING_UPDATES=true
WEBHOOK_MAX_QUEUE_SIZE=1024
WEBHOOK_WORKERS=4
WEBHOOK_ENQUEUE_TIMEOUT=0.1
WEBHOOK_WORKER_SHUTDOWN_TIMEOUT=30.0
WEB_API_DEFAULT_TOKEN=$WEB_API_DEFAULT_TOKEN
WEB_API_ENABLED=true
WEB_API_HOST=0.0.0.0
WEB_API_PORT=8080
WEB_API_ALLOWED_ORIGINS=*
EOF

    mkdir -p ./logs ./data ./data/backups ./data/referral_qr
    chmod -R 755 ./logs ./data
    chown -R 1000:1000 ./logs ./data

    # Пробрасываем порт 8080 на localhost
    cat > docker-compose.yml <<EOF
services:
    remnawave_bot:
        build: .
        container_name: remnawave_bot
        restart: always
        ports:
            - "127.0.0.1:8080:8080"
        env_file:
            - .env
        volumes:
            - ./logs:/app/logs
            - ./data:/app/data
EOF

    docker compose up -d

    # Настройка Nginx для бота
    BEDOLAGA_BLOCK="
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    "
    add_nginx_block "$BEDOLAGA_DOMAIN" "$BEDOLAGA_BLOCK"

    echo -e "${GREEN}✅ Bedolaga Bot успешно установлен!${NC}"
    echo -e "🌐 Бот: https://$BEDOLAGA_DOMAIN\n"
    read -p "Нажмите Enter для возврата в меню..."
}

install_cabinet() {
    show_logo
    echo -e "${BLUE}${BOLD}🗄️  Установка MiniAPP (Cabinet)${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Сначала установите Bedolaga Bot!${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    read -p "🌐 Домен для Cabinet (например cabinet.myvpn.com): " CABINET_DOMAIN
    read -p "📱 Telegram Bot Username (без @): " BOT_USERNAME
    read -p "🏷️  Название приложения: " APP_NAME

    CABINET_JWT_SECRET=$(openssl rand -hex 32)

    # Добавляем настройки в .env бота
    cd /opt/bedolaga-bot
    if ! grep -q "CABINET_ENABLED=true" .env; then
        cat >> .env <<EOF

# Bedolaga Cabinet
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
CABINET_URL=https://$CABINET_DOMAIN
EOF
    fi

    echo -e "${YELLOW}📥 Клонируем Cabinet...${NC}"
    cd /opt
    git clone https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git
    cd bedolaga-cabinet

    echo -e "${YELLOW}📝 Создаём .env для Cabinet...${NC}"
    cat > .env <<EOF
VITE_API_URL=/api
VITE_TELEGRAM_BOT_USERNAME=$BOT_USERNAME
VITE_APP_NAME=$APP_NAME
VITE_APP_LOGO=V
EOF

    echo -e "${YELLOW}📥 Собираем и копируем файлы...${NC}"
    docker compose build
    docker create --name tmp_cabinet cabinet_frontend
    rm -rf ./cabinet-dist
    docker cp tmp_cabinet:/usr/share/nginx/html ./cabinet-dist
    docker rm tmp_cabinet

    mkdir -p /srv/cabinet
    cp -r ./cabinet-dist/* /srv/cabinet/

    # Создаем контейнер для Cabinet (nginx, который раздаёт статику)
    cat > docker-compose.yml <<EOF
services:
    cabinet_frontend:
        image: nginx:alpine
        container_name: cabinet_frontend
        restart: always
        ports:
            - "127.0.0.1:8081:80"
        volumes:
            - /srv/cabinet:/usr/share/nginx/html:ro
EOF
    docker compose up -d

    # Настраиваем Nginx для Cabinet
    CABINET_BLOCK="
    location /api/ {
        rewrite ^/api/(.*) /\$1 break;
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
    "
    add_nginx_block "$CABINET_DOMAIN" "$CABINET_BLOCK"

    echo -e "${GREEN}✅ MiniAPP (Cabinet) успешно установлен!${NC}"
    echo -e "🗄️  Cabinet: https://$CABINET_DOMAIN\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Bedolaga компонентов${NC}\n"

    if [ -d "/opt/bedolaga-bot" ]; then
        echo -e "${YELLOW}Обновляем Bot...${NC}"
        cd /opt/bedolaga-bot
        git pull origin main
        docker compose down
        docker compose up -d --build
    fi

    if [ -d "/opt/bedolaga-cabinet" ]; then
        echo -e "${YELLOW}Обновляем Cabinet...${NC}"
        cd /opt/bedolaga-cabinet
        docker compose build
        docker compose up -d
    fi

    docker image prune -f
    echo -e "${GREEN}✅ Обновление Bedolaga завершено!${NC}\n"
    read -p "Нажмите Enter..."
}

setup_nginx_for_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Настройка Nginx для Bedolaga Bot + Cabinet${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Bedolaga Bot не установлен (нет /opt/bedolaga-bot).${NC}"
        echo -e "Сначала установите бота через пункт меню 2 → 1."
        read -p "Нажмите Enter для возврата..."
        return
    fi

    ensure_nginx_running || return

    # Определяем существующие домены из конфигов
    BOT_DOMAIN=""
    CABINET_DOMAIN=""
    for conf in /etc/nginx/sites-available/*; do
        if [ -f "$conf" ]; then
            if grep -q "proxy_pass http://127.0.0.1:8080" "$conf"; then
                BOT_DOMAIN=$(basename "$conf")
            fi
            if grep -q "proxy_pass http://127.0.0.1:8081" "$conf"; then
                CABINET_DOMAIN=$(basename "$conf")
            fi
        fi
    done

    if [ -z "$BOT_DOMAIN" ]; then
        read -p "🌐 Введите домен для Bedolaga Bot: " BOT_DOMAIN
    fi
    if [ -z "$CABINET_DOMAIN" ] && [ -d "/opt/bedolaga-cabinet" ]; then
        read -p "🌐 Введите домен для Cabinet: " CABINET_DOMAIN
    fi

    echo -e "\n${CYAN}${BOLD}Найденные/введённые домены:${NC}"
    echo -e "  🤖 Бот:      ${BOLD}$BOT_DOMAIN${NC}"
    [ -n "$CABINET_DOMAIN" ] && echo -e "  🗄️  Cabinet:  ${BOLD}$CABINET_DOMAIN${NC}"

    read -p "Всё верно? (y — продолжить, n — изменить): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        read -p "🌐 Введите новый домен для БОТА: " BOT_DOMAIN
        if [ -n "$CABINET_DOMAIN" ]; then
            read -p "🌐 Введите новый домен для CABINET: " CABINET_DOMAIN
        fi
    fi

    # Пересоздаём конфиги, если они уже есть, удалим старые
    if [ -f "/etc/nginx/sites-available/$BOT_DOMAIN" ]; then
        remove_nginx_block "$BOT_DOMAIN"
    fi
    if [ -n "$CABINET_DOMAIN" ] && [ -f "/etc/nginx/sites-available/$CABINET_DOMAIN" ]; then
        remove_nginx_block "$CABINET_DOMAIN"
    fi

    # Добавляем блок для бота
    BOT_BLOCK="
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    "
    add_nginx_block "$BOT_DOMAIN" "$BOT_BLOCK"

    if [ -n "$CABINET_DOMAIN" ]; then
        CABINET_BLOCK="
        location /api/ {
            rewrite ^/api/(.*) /\$1 break;
            proxy_pass http://127.0.0.1:8080;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
        }
        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
        }
        "
        add_nginx_block "$CABINET_DOMAIN" "$CABINET_BLOCK"
    fi

    echo -e "\n${GREEN}${BOLD}✅ Настройка Nginx для Bedolaga завершена!${NC}"
    echo -e "🌐 Бот: https://$BOT_DOMAIN"
    [ -n "$CABINET_DOMAIN" ] && echo -e "🗄️  Cabinet: https://$CABINET_DOMAIN"
    read -p "Нажмите Enter для возврата..."
}

# ============================================
# ОПЦИЯ 3: REMNAWAVE ADMIN WEB + BOT
# ============================================

install_admin_bot() {
    show_logo
    echo -e "${BLUE}${BOLD}🤖 Установка Remnawave Admin Web + Bot${NC}\n"

    install_docker
    install_nginx_certbot
    ensure_nginx_running

    echo -e "${YELLOW}Где устанавливается Admin Bot?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    read -p "${CYAN}▶${NC} Ваш выбор: " server_location

    if [[ "$server_location" == "1" ]]; then
        API_BASE_URL="http://remnawave:3000"
    else
        read -p "🌐 Введите домен панели: " PANEL_DOMAIN
        API_BASE_URL="https://$PANEL_DOMAIN"
    fi

    read -p "🤖 BOT_TOKEN (от @BotFather): " BOT_TOKEN
    read -p "🔑 API_TOKEN (из панели): " API_TOKEN
    read -p "👤 ADMINS (Telegram ID через запятую): " ADMINS
    read -p "📱 TELEGRAM_BOT_USERNAME (без @): " BOT_USERNAME
    read -p "🌐 Домен для веб-панели (например admin.myvpn.com): " ADMIN_DOMAIN

    WEB_SECRET_KEY=$(openssl rand -hex 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 24)

    mkdir -p /opt/remnawave-admin && cd /opt/remnawave-admin
    git clone https://github.com/Case211/remnawave-admin.git .

    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
API_BASE_URL=$API_BASE_URL
API_TOKEN=$API_TOKEN
ADMINS=$ADMINS
DEFAULT_LOCALE=ru
LOG_LEVEL=INFO
WEBHOOK_PORT=9090
WEB_SECRET_KEY=$WEB_SECRET_KEY
POSTGRES_USER=remnawave
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=remnawave_bot
DATABASE_URL=postgresql://remnawave:$POSTGRES_PASSWORD@remnawave-admin-db:5432/remnawave_bot
WEB_CORS_ORIGINS=https://$ADMIN_DOMAIN
TELEGRAM_BOT_USERNAME=$BOT_USERNAME
WEB_BACKEND_PORT=9091
WEB_FRONTEND_PORT=13000
EOF

    # Создаём compose с пробросом портов
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  web-frontend:
    image: case211/remnawave-admin-frontend:latest
    container_name: web-frontend
    restart: always
    ports:
      - "127.0.0.1:13000:80"
    env_file:
      - .env
  web-backend:
    image: case211/remnawave-admin-backend:latest
    container_name: web-backend
    restart: always
    ports:
      - "127.0.0.1:9091:9091"
    env_file:
      - .env
    depends_on:
      - db
  db:
    image: postgres:15
    container_name: remnawave-admin-db
    restart: always
    environment:
      POSTGRES_USER: remnawave
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
      POSTGRES_DB: remnawave_bot
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
EOF

    docker compose up -d

    # Настройка Nginx
    ADMIN_BLOCK="
    location /api/ {
        rewrite ^/api/(.*) /\$1 break;
        proxy_pass http://127.0.0.1:9091;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    location / {
        proxy_pass http://127.0.0.1:13000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
    "
    add_nginx_block "$ADMIN_DOMAIN" "$ADMIN_BLOCK"

    echo -e "${GREEN}✅ Remnawave Admin Web + Bot установлен!${NC}"
    echo -e "🌐 Веб-панель: https://$ADMIN_DOMAIN\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 4: CLOUDFLARE WARP
# ============================================

install_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Установка Cloudflare WARP${NC}\n"

    install_docker

    echo -e "${YELLOW}📥 Запускаем официальный скрипт установки warp-native...${NC}"
    bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)

    echo -e "${GREEN}✅ WARP успешно установлен!${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

uninstall_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🗑️  Удаление Cloudflare WARP${NC}\n"

    echo -e "${YELLOW}📥 Запускаем официальный скрипт удаления...${NC}"
    bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/uninstall.sh) || true

    echo -e "${GREEN}✅ WARP успешно удалён.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 5: БЭКАПЫ
# ============================================

run_backup() {
    show_logo
    echo -e "${BLUE}${BOLD}💾 Запуск скрипта бэкапов${NC}\n"

    if [ ! -f "/tmp/backup-restore.sh" ]; then
        echo -e "${YELLOW}📥 Скачиваем скрипт бэкапов...${NC}"
        curl -Ls https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh -o /tmp/backup-restore.sh
        chmod +x /tmp/backup-restore.sh
        echo -e "${GREEN}✅ Скрипт скачан.${NC}\n"
    fi

    echo -e "${YELLOW}Запускаем скрипт бэкапов...${NC}\n"
    bash /tmp/backup-restore.sh

    echo -e "\n${GREEN}✅ Скрипт бэкапов завершён.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 6: ЛОГИ
# ============================================

show_logs_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}📋 Просмотр логов${NC}\n"
        echo -e "${BOLD}Выберите компонент:${NC}"
        echo -e "  ${CYAN}1)${NC} 🚀 Логи панели Remnawave"
        echo -e "  ${CYAN}2)${NC} 📄 Логи страницы подписки"
        echo -e "  ${CYAN}3)${NC} 🌐 Логи Nginx"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "${CYAN}▶${NC} Ваш выбор: " log_choice

        case $log_choice in
            1) show_panel_logs ;;
            2) show_subscription_logs ;;
            3) show_nginx_logs ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

show_panel_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}🚀 Логи панели Remnawave${NC}\n"

    if [ ! -d "/opt/remnawave" ]; then
        echo -e "${RED}❌ Папка /opt/remnawave не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    cd /opt/remnawave
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100
}

show_subscription_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}📄 Логи страницы подписки${NC}\n"

    if [ ! -d "/opt/remnawave/subscription" ]; then
        echo -e "${RED}❌ Папка /opt/remnawave/subscription не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    cd /opt/remnawave/subscription
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100
}

show_nginx_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Логи Nginx${NC}\n"
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода${NC}\n"
    tail -f /var/log/nginx/access.log /var/log/nginx/error.log
}

# ============================================
# УДАЛЕНИЕ КОМПОНЕНТОВ
# ============================================

show_uninstall_menu() {
    while true; do
        show_logo
        echo -e "${RED}${BOLD}🗑️  Удаление компонентов${NC}\n"
        echo -e "${YELLOW}ВНИМАНИЕ: Удаление безвозвратно!${NC}\n"
        echo -e "  ${CYAN}1)${NC} Удалить Remnawave Panel (включая подписку)"
        echo -e "  ${CYAN}2)${NC} Удалить Bedolaga Bot"
        echo -e "  ${CYAN}3)${NC} Удалить Bedolaga Cabinet"
        echo -e "  ${CYAN}4)${NC} Удалить Nginx (весь прокси и сертификаты)"
        echo -e "  ${CYAN}5)${NC} Удалить Cloudflare DDNS"
        echo -e "  ${CYAN}6)${NC} Удалить Cloudflare WARP"
        echo -e "  ${CYAN}7)${NC} Удалить ВСЁ (полная очистка)"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "${CYAN}▶${NC} Ваш выбор: " uninstall_choice

        case $uninstall_choice in
            1) uninstall_panel ;;
            2) uninstall_bedolaga_bot ;;
            3) uninstall_cabinet ;;
            4) uninstall_nginx ;;
            5) uninstall_ddns ;;
            6) uninstall_warp ;;
            7) uninstall_all ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

uninstall_panel() {
    show_logo
    echo -e "${RED}${BOLD}🗑️  Удаление Remnawave Panel${NC}\n"
    read -p "Вы уверены, что хотите удалить панель и все её данные? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    if [ -d "/opt/remnawave" ]; then
        cd /opt/remnawave
        docker compose down -v 2>/dev/null
        cd ..
        rm -rf /opt/remnawave
        echo -e "${GREEN}✅ Панель Remnawave удалена.${NC}"
    else
        echo -e "${YELLOW}⚠️  Панель не найдена.${NC}"
    fi

    # Удаляем конфиги Nginx для доменов, связанных с панелью
    for conf in /etc/nginx/sites-available/*; do
        if [ -f "$conf" ]; then
            if grep -q "proxy_pass http://127.0.0.1:3000" "$conf" || grep -q "proxy_pass http://127.0.0.1:3010" "$conf"; then
                domain=$(basename "$conf")
                remove_nginx_block "$domain"
            fi
        fi
    done

    echo -e "${GREEN}✅ Удаление панели завершено.${NC}"
    read -p "Нажмите Enter для возврата..."
}

uninstall_bedolaga_bot() {
    show_logo
    echo -e "${RED}${BOLD}🗑️  Удаление Bedolaga Bot${NC}\n"
    read -p "Вы уверены, что хотите удалить бота? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    # Определяем домен из конфига
    BOT_DOMAIN=""
    for conf in /etc/nginx/sites-available/*; do
        if [ -f "$conf" ] && grep -q "proxy_pass http://127.0.0.1:8080" "$conf"; then
            BOT_DOMAIN=$(basename "$conf")
            break
        fi
    done

    if [ -d "/opt/bedolaga-bot" ]; then
        cd /opt/bedolaga-bot
        docker compose down -v 2>/dev/null
        cd ..
        rm -rf /opt/bedolaga-bot
        echo -e "${GREEN}✅ Bedolaga Bot удалён.${NC}"
    else
        echo -e "${YELLOW}⚠️  Бот не найден.${NC}"
    fi

    if [ -n "$BOT_DOMAIN" ]; then
        remove_nginx_block "$BOT_DOMAIN"
    fi

    echo -e "${GREEN}✅ Удаление бота завершено.${NC}"
    read -p "Нажмите Enter для возврата..."
}

uninstall_cabinet() {
    show_logo
    echo -e "${RED}${BOLD}🗑️  Удаление Bedolaga Cabinet${NC}\n"
    read -p "Вы уверены, что хотите удалить Cabinet? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    CABINET_DOMAIN=""
    for conf in /etc/nginx/sites-available/*; do
        if [ -f "$conf" ] && grep -q "proxy_pass http://127.0.0.1:8081" "$conf"; then
            CABINET_DOMAIN=$(basename "$conf")
            break
        fi
    done

    if [ -d "/opt/bedolaga-cabinet" ]; then
        cd /opt/bedolaga-cabinet
        docker compose down -v 2>/dev/null
        cd ..
        rm -rf /opt/bedolaga-cabinet
        echo -e "${GREEN}✅ Bedolaga Cabinet удалён.${NC}"
    else
        echo -e "${YELLOW}⚠️  Cabinet не найден.${NC}"
    fi

    if [ -d "/srv/cabinet" ]; then
        rm -rf /srv/cabinet
        echo -e "${GREEN}✅ Статика кабинета удалена.${NC}"
    fi

    if [ -n "$CABINET_DOMAIN" ]; then
        remove_nginx_block "$CABINET_DOMAIN"
    fi

    echo -e "${GREEN}✅ Удаление Cabinet завершено.${NC}"
    read -p "Нажмите Enter для возврата..."
}

uninstall_nginx() {
    show_logo
    echo -e "${RED}${BOLD}🗑️  Удаление Nginx и всех конфигов${NC}\n"
    read -p "Вы уверены, что хотите удалить Nginx и все сертификаты? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    systemctl stop nginx
    systemctl disable nginx
    apt-get purge -y nginx nginx-common certbot python3-certbot-nginx

    rm -rf /etc/nginx/sites-available/*
    rm -rf /etc/nginx/sites-enabled/*

    # Удаляем все сертификаты Let's Encrypt
    for cert in /etc/letsencrypt/live/*; do
        if [ -d "$cert" ]; then
            certbot delete --cert-name "$(basename "$cert")" --non-interactive 2>/dev/null
        fi
    done

    echo -e "${GREEN}✅ Nginx и сертификаты удалены.${NC}"
    read -p "Нажмите Enter для возврата..."
}

uninstall_ddns() {
    show_logo
    echo -e "${RED}${BOLD}🗑️  Удаление Cloudflare DDNS${NC}\n"
    read -p "Вы уверены, что хотите удалить DDNS? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    systemctl stop cloudflare-ddns.timer 2>/dev/null
    systemctl disable cloudflare-ddns.timer 2>/dev/null
    systemctl stop cloudflare-ddns.service 2>/dev/null
    systemctl disable cloudflare-ddns.service 2>/dev/null

    rm -f /etc/systemd/system/cloudflare-ddns.timer
    rm -f /etc/systemd/system/cloudflare-ddns.service
    systemctl daemon-reload

    rm -rf /opt/cloudflare-ddns

    echo -e "${GREEN}✅ Cloudflare DDNS удалён.${NC}"
    read -p "Нажмите Enter для возврата..."
}

uninstall_all() {
    show_logo
    echo -e "${RED}${BOLD}🗑️  ПОЛНАЯ ОЧИСТКА ВСЕХ КОМПОНЕНТОВ${NC}\n"
    read -p "ВНИМАНИЕ! Это удалит всё: панель, бота, кабинет, Nginx, DDNS, WARP. Продолжить? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    uninstall_panel
    uninstall_bedolaga_bot
    uninstall_cabinet
    uninstall_nginx
    uninstall_ddns
    uninstall_warp

    docker system prune -af --volumes 2>/dev/null

    echo -e "${GREEN}${BOLD}✅ Полная очистка завершена!${NC}"
    read -p "Нажмите Enter для возврата..."
}

# ============================================
# ОПЦИЯ 7: CLOUDFLARE DDNS (выбор записей)
# ============================================

install_cloudflare_ddns() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Настройка Cloudflare DDNS (выбор записей)${NC}\n"
    echo -e "Этот скрипт покажет все DNS-записи в зоне и позволит выбрать,"
    echo -e "какие из них автоматически обновлять при смене IP.\n"

    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}📦 Устанавливаем jq...${NC}"
        apt-get update -qq && apt-get install -y -qq jq curl >/dev/null 2>&1
    fi

    read -p "🔑 Введите ваш Cloudflare API Token (с правами Zone:Read и DNS:Edit): " CF_API_TOKEN
    if [ -z "$CF_API_TOKEN" ]; then
        echo -e "${RED}❌ API Token обязателен!${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    read -p "🌐 Введите домен зоны (например, example.com): " ZONE_NAME
    if [ -z "$ZONE_NAME" ]; then
        echo -e "${RED}❌ Домен зоны обязателен!${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    echo -e "\n${YELLOW}⏳ Проверяем API токен и получаем zone_id...${NC}"
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
        echo -e "${RED}❌ Не удалось получить zone_id. Проверьте API токен и домен.${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi
    echo -e "${GREEN}✅ Zone ID получен: $ZONE_ID${NC}"

    echo -e "\n${BOLD}Какой тип записей показывать?${NC}"
    echo "  1) Только A (IPv4)"
    echo "  2) Только AAAA (IPv6)"
    echo "  3) Все (A и AAAA)"
    read -p "${CYAN}▶${NC} Ваш выбор (1-3): " type_choice
    case $type_choice in
        1) RECORD_TYPES="A" ;;
        2) RECORD_TYPES="AAAA" ;;
        3) RECORD_TYPES="A,AAAA" ;;
        *) echo -e "${RED}❌ Неверный выбор. Используем A.${NC}"; RECORD_TYPES="A" ;;
    esac

    echo -e "\n${YELLOW}📡 Получаем список записей...${NC}"
    RECORDS_JSON="[]"
    IFS=',' read -ra TYPES <<< "$RECORD_TYPES"
    for TYPE in "${TYPES[@]}"; do
        RESP=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$TYPE&per_page=100" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json")
        if echo "$RESP" | jq -e '.success == true' >/dev/null; then
            RECORDS_JSON=$(echo "$RECORDS_JSON" | jq --argjson new "$(echo "$RESP" | jq '.result')" '. + $new')
        else
            ERR_MSG=$(echo "$RESP" | jq -r '.errors[0].message // "Неизвестная ошибка"')
            echo -e "${RED}❌ Ошибка получения записей типа $TYPE: $ERR_MSG${NC}"
        fi
    done

    RECORD_COUNT=$(echo "$RECORDS_JSON" | jq 'length')
    if ! [[ "$RECORD_COUNT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Не удалось получить количество записей. Проверьте токен и зону.${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    if [ "$RECORD_COUNT" -eq 0 ]; then
        echo -e "${RED}❌ В зоне $ZONE_NAME не найдено записей типов $RECORD_TYPES.${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    echo -e "\n${CYAN}${BOLD}Список записей в зоне $ZONE_NAME:${NC}"
    echo "  № | Имя записи                | Тип | Содержимое"
    echo "----+---------------------------+-----+------------------"
    INDEX=1
    declare -a RECORD_NAMES_ARRAY
    while IFS= read -r line; do
        NAME=$(echo "$line" | jq -r '.name')
        TYPE=$(echo "$line" | jq -r '.type')
        CONTENT=$(echo "$line" | jq -r '.content')
        printf "  %2d | %-25s | %-3s | %s\n" $INDEX "$NAME" "$TYPE" "$CONTENT"
        RECORD_NAMES_ARRAY[$INDEX]="$NAME:$TYPE"
        ((INDEX++))
    done < <(echo "$RECORDS_JSON" | jq -c '.[]')

    echo ""
    read -p "Введите номера записей, которые нужно обновлять (через запятую, например 1,3,5) или 'all' для всех: " SELECTION
    if [ -z "$SELECTION" ]; then
        echo -e "${RED}❌ Выбор не сделан. Отмена.${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    SELECTED_RECORDS=()
    if [ "$SELECTION" == "all" ]; then
        for i in "${!RECORD_NAMES_ARRAY[@]}"; do
            if [ -n "${RECORD_NAMES_ARRAY[$i]}" ]; then
                SELECTED_RECORDS+=("${RECORD_NAMES_ARRAY[$i]}")
            fi
        done
    else
        IFS=',' read -ra INDICES <<< "$SELECTION"
        for idx in "${INDICES[@]}"; do
            idx=$(echo "$idx" | xargs)
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -lt "$INDEX" ]; then
                SELECTED_RECORDS+=("${RECORD_NAMES_ARRAY[$idx]}")
            else
                echo -e "${YELLOW}⚠️  Номер $idx неверен, пропускаем.${NC}"
            fi
        done
    fi

    if [ ${#SELECTED_RECORDS[@]} -eq 0 ]; then
        echo -e "${RED}❌ Не выбрано ни одной корректной записи. Отмена.${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    echo -e "\n${GREEN}Будут обновляться записи:${NC}"
    for rec in "${SELECTED_RECORDS[@]}"; do
        echo "  - $rec"
    done
    read -p "Продолжить? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Отмена.${NC}"
        read -p "Нажмите Enter для возврата..."
        return
    fi

    mkdir -p /opt/cloudflare-ddns

    cat > /opt/cloudflare-ddns/update.sh <<'EOF'
#!/bin/bash

CF_API_TOKEN="__TOKEN__"
ZONE_ID="__ZONE_ID__"
RECORDS="__RECORDS__"

get_ip() {
    local type=$1
    if [ "$type" == "A" ]; then
        curl -s -4 https://api.ipify.org
    elif [ "$type" == "AAAA" ]; then
        curl -s -6 https://api6.ipify.org
    else
        echo ""
    fi
}

for record in $RECORDS; do
    NAME=$(echo $record | cut -d: -f1)
    TYPE=$(echo $record | cut -d: -f2)
    CURRENT_IP=$(get_ip $TYPE)
    if [ -z "$CURRENT_IP" ]; then
        echo "❌ Не удалось получить IP для $NAME ($TYPE)"
        continue
    fi

    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$TYPE&name=$NAME" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
        echo "❌ Запись $NAME не найдена. Создаём..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$TYPE\",\"name\":\"$NAME\",\"content\":\"$CURRENT_IP\",\"ttl\":120,\"proxied\":false}" > /dev/null
        echo "✅ Запись $NAME создана с IP $CURRENT_IP"
    else
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$TYPE\",\"name\":\"$NAME\",\"content\":\"$CURRENT_IP\",\"ttl\":120,\"proxied\":false}" > /dev/null
        echo "✅ Запись $NAME обновлена: $CURRENT_IP"
    fi
done
EOF

    RECORDS_STR=""
    for rec in "${SELECTED_RECORDS[@]}"; do
        RECORDS_STR="$RECORDS_STR $rec"
    done
    RECORDS_STR=$(echo "$RECORDS_STR" | sed 's/^ //')

    sed -i "s|__TOKEN__|$CF_API_TOKEN|g" /opt/cloudflare-ddns/update.sh
    sed -i "s|__ZONE_ID__|$ZONE_ID|g" /opt/cloudflare-ddns/update.sh
    sed -i "s|__RECORDS__|$RECORDS_STR|g" /opt/cloudflare-ddns/update.sh

    chmod +x /opt/cloudflare-ddns/update.sh

    cat > /etc/systemd/system/cloudflare-ddns.service <<EOF
[Unit]
Description=Cloudflare DDNS Updater (multi-record)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/cloudflare-ddns/update.sh
User=root
EOF

    cat > /etc/systemd/system/cloudflare-ddns.timer <<EOF
[Unit]
Description=Cloudflare DDNS timer (every 5 minutes)
Requires=cloudflare-ddns.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable cloudflare-ddns.timer
    systemctl start cloudflare-ddns.timer

    echo -e "${YELLOW}🔄 Выполняем первое обновление...${NC}"
    /opt/cloudflare-ddns/update.sh

    echo -e "\n${GREEN}${BOLD}✅ Cloudflare DDNS настроен для выбранных записей:${NC}"
    for rec in "${SELECTED_RECORDS[@]}"; do
        echo "  - $rec"
    done
    echo -e "⏱️  Обновление каждые 5 минут (таймер active)"
    echo -e "📋 Лог: journalctl -u cloudflare-ddns -f"
    echo -e "🔄 Принудительный запуск: systemctl start cloudflare-ddns"
    echo -e ""
    read -p "Нажмите Enter для возврата..."
}

# ============================================
# ПОДМЕНЮ
# ============================================

show_remnawave_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🚀 Remnawave${NC}\n"
        echo -e "  ${CYAN}1)${NC} 🚀 Установить Панель + Страницу подписки"
        echo -e "  ${CYAN}2)${NC} 🖥️  Установить Ноду"
        echo -e "  ${CYAN}3)${NC} 🔄 Обновить компоненты"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "${CYAN}▶${NC} Ваш выбор: " choice

        case $choice in
            1) install_panel ;;
            2) install_node ;;
            3) update_components ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

show_warp_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🌐 Cloudflare WARP${NC}\n"
        echo -e "  ${CYAN}1)${NC} 🌐 Установить Cloudflare WARP"
        echo -e "  ${CYAN}2)${NC} 🗑️  Удалить Cloudflare WARP"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "${CYAN}▶${NC} Ваш выбор: " choice

        case $choice in
            1) install_warp ;;
            2) uninstall_warp ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

# ============================================
# ГЛАВНОЕ МЕНЮ
# ============================================

while true; do
    show_logo
    create_alias

    echo -e "${BOLD}Выберите раздел:${NC}"
    echo -e "  ${CYAN}1)${NC} 🚀 Remnawave"
    echo -e "  ${CYAN}2)${NC} 💰 Bedolaga (Bot + MiniAPP)"
    echo -e "  ${CYAN}3)${NC} 🤖 Remnawave Admin Web + Bot"
    echo -e "  ${CYAN}4)${NC} 🌐 Cloudflare WARP"
    echo -e "  ${CYAN}5)${NC} 💾 Бэкапы"
    echo -e "  ${CYAN}6)${NC} 📋 Логи"
    echo -e "  ${CYAN}7)${NC} 🌐 Cloudflare DDNS (выбор записей)"
    echo -e "  ${CYAN}8)${NC} 🗑️  Удаление компонентов"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}0)${NC} 🚪 Выход"
    read -p "${CYAN}▶${NC} Ваш выбор: " main_choice

    case $main_choice in
        1) show_remnawave_menu ;;
        2) show_bedolaga_menu ;;
        3) install_admin_bot ;;
        4) show_warp_menu ;;
        5) run_backup ;;
        6) show_logs_menu ;;
        7) install_cloudflare_ddns ;;
        8) show_uninstall_menu ;;
        0) echo -e "${GREEN}👋 До свидания!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
    esac
done
