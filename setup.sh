#!/bin/bash

# ============================================
# Just Remnawave Auto Installer
# Author: tneangel
# Modified by Santey990
# Repository: https://github.com/Santey990/Remnawave-bedolaga-Auto-Installer
# ============================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ошибка: Скрипт нужно запускать от имени root (sudo).${NC}"
    exit 1
fi

# Создание глобального алиаса rw-installer
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
    echo "  ║   ⚡ Remnawave + Bedolaga Auto Installer by Santey990   ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Проверка и установка Docker
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

# Проверка наличия Caddy
check_caddy_installed() {
    if [ -d "/opt/remnawave/caddy" ] && [ -f "/opt/remnawave/caddy/docker-compose.yml" ]; then
        # Проверяем, запущен ли контейнер caddy
        if docker ps --format '{{.Names}}' | grep -q "^caddy$"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Гарантируем запуск Caddy (если не установлен - предлагаем установить)
ensure_caddy_running() {
    if ! check_caddy_installed; then
        echo -e "${YELLOW}⚠️  Caddy не установлен или не запущен.${NC}"
        echo -e "Для работы Bedolaga необходим Caddy."
        echo -e "Вы можете установить его через установку панели Remnawave (пункт 1 → 1)."
        echo -e "Или запустить Caddy отдельно, но это сложнее."
        read -p "Хотите установить Caddy автоматически? (y/n): " install_caddy
        if [[ "$install_caddy" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}🚀 Устанавливаем Caddy...${NC}"
            mkdir -p /opt/remnawave/caddy
            cd /opt/remnawave/caddy
            
            # Создаём docker-compose для Caddy
            cat > docker-compose.yml <<EOF
services:
    caddy:
        image: caddy:2.9
        container_name: caddy
        hostname: caddy
        restart: always
        ports:
            - '0.0.0.0:443:443'
            - '0.0.0.0:80:80'
        networks:
            - remnawave-network
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - caddy-ssl-data:/data
networks:
    remnawave-network:
        name: remnawave-network
        driver: bridge
        external: true
volumes:
    caddy-ssl-data:
        driver: local
        external: false
        name: caddy-ssl-data
EOF

            # Инициализируем блоки
            init_caddy_blocks
            
            # Создаём Caddyfile
            rebuild_caddyfile
            
            # Запускаем Caddy
            docker compose up -d
            echo -e "${GREEN}✅ Caddy установлен и запущен.${NC}"
        else
            echo -e "${RED}❌ Без Caddy бот и кабинет не будут работать. Выход.${NC}"
            read -p "Нажмите Enter для возврата..."
            return 1
        fi
    fi
    return 0
}

# ============================================
# СИСТЕМА БЛОКОВ CADDY
# ============================================

init_caddy_blocks() {
    mkdir -p /opt/remnawave/caddy/blocks
}

add_caddy_block() {
    local domain="$1"
    local block_content="$2"
    local blocks_dir="/opt/remnawave/caddy/blocks"
    
    init_caddy_blocks
    echo "$block_content" > "$blocks_dir/$domain"
    echo -e "${GREEN}✅ Блок для $domain сохранён.${NC}"
    rebuild_caddyfile
}

remove_caddy_block() {
    local domain="$1"
    local blocks_dir="/opt/remnawave/caddy/blocks"
    
    if [ -f "$blocks_dir/$domain" ]; then
        rm -f "$blocks_dir/$domain"
        echo -e "${GREEN}✅ Блок для $domain удалён.${NC}"
        rebuild_caddyfile
    else
        echo -e "${YELLOW}⚠️  Блок для $domain не найден.${NC}"
    fi
}

rebuild_caddyfile() {
    local blocks_dir="/opt/remnawave/caddy/blocks"
    local caddyfile="/opt/remnawave/caddy/Caddyfile"
    
    echo "# Remnawave Caddy Configuration" > "$caddyfile"
    echo "# Auto-generated - do not edit manually" >> "$caddyfile"
    echo "" >> "$caddyfile"
    
    if [ -d "$blocks_dir" ]; then
        for block_file in "$blocks_dir"/*; do
            if [ -f "$block_file" ]; then
                cat "$block_file" >> "$caddyfile"
                echo "" >> "$caddyfile"
            fi
        done
    fi
    
    cat >> "$caddyfile" << 'EOF'
:443 {
    tls internal
    respond 204
}
EOF
    
    echo -e "${GREEN}✅ Caddyfile пересобран.${NC}"
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

    echo -e "${YELLOW}🚀 Шаг 4. Запускаем основную панель...${NC}"
    docker compose up -d
    echo -e "${GREEN}✅ Панель запущена. Ожидаем инициализацию БД...${NC}"
    sleep 20

    echo -e "\n${YELLOW}🔧 Шаг 5. Настраиваем Caddy (HTTPS)...${NC}"
    mkdir -p /opt/remnawave/caddy && cd /opt/remnawave/caddy
    init_caddy_blocks

    PANEL_BLOCK="https://$PANEL_DOMAIN {
    reverse_proxy * http://remnawave:3000
}"
    add_caddy_block "$PANEL_DOMAIN" "$PANEL_BLOCK"

    cat > docker-compose.yml <<EOF
services:
    caddy:
        image: caddy:2.9
        container_name: 'caddy'
        hostname: caddy
        restart: always
        ports:
            - '0.0.0.0:443:443'
            - '0.0.0.0:80:80'
        networks:
            - remnawave-network
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - caddy-ssl-data:/data
networks:
    remnawave-network:
        name: remnawave-network
        driver: bridge
        external: true
volumes:
    caddy-ssl-data:
        driver: local
        external: false
        name: caddy-ssl-data
EOF
    docker compose up -d
    echo -e "${GREEN}✅ Caddy запущен. HTTPS готов.${NC}"

    echo -e "\n${YELLOW}${BOLD}⚠️  ВАЖНО: Создайте API Token в админке!${NC}"
    echo -e "1. Откройте в браузере: ${CYAN}https://$PANEL_DOMAIN${NC}"
    echo -e "2. Зарегистрируйтесь (первый вход)"
    echo -e "3. Перейдите в ${BOLD}Settings → API Tokens${NC} и создайте токен"
    echo -e "4. Скопируйте его и вставьте ниже\n"
    read -p "🔑 Вставьте API TOKEN: " API_TOKEN

    if [ -z "$API_TOKEN" ]; then
        echo -e "${RED}❌ Токен не введён. Страница подписки не будет установлена.${NC}"
    else
        echo -e "\n${YELLOW}📄 Шаг 6. Устанавливаем страницу подписки...${NC}"
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

        echo -e "${YELLOW}🔄 Шаг 7. Добавляем домен подписки в Caddy...${NC}"
        
        SUB_BLOCK="https://$SUB_DOMAIN {
    reverse_proxy * http://remnawave-subscription-page:3010
}"
        add_caddy_block "$SUB_DOMAIN" "$SUB_BLOCK"
        
        cd /opt/remnawave/caddy
        docker compose down && docker compose up -d
        echo -e "${GREEN}✅ Caddy обновлён.${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ УСТАНОВКА ПАНЕЛИ ЗАВЕРШЕНА! 🎉                     ║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}🌐 Админка:  ${BOLD}https://$PANEL_DOMAIN${NC}"
    echo -e "${CYAN}📄 Подписка: ${BOLD}https://$SUB_DOMAIN${NC}"
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 1.2: УСТАНОВКА НОДЫ
# ============================================
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

# ============================================
# ОПЦИЯ 1.3: ОБНОВЛЕНИЕ КОМПОНЕНТОВ
# ============================================
update_components() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление компонентов Remnawave${NC}\n"
    
    echo -e "${BOLD}Что хотите обновить?${NC}"
    echo -e "  ${CYAN}1)${NC} 🚀 Обновить Панель + Страницу подписки"
    echo -e "  ${CYAN}2)${NC} 🖥️  Обновить Ноду"
    echo -e "  ${CYAN}0)${NC} 🔙 Назад"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" update_choice

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
        echo -e "  ${CYAN}4)${NC} 🌐 Настроить Caddy для Bedolaga"
        echo -e "  ${CYAN}0)${NC} Назад"
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

        case $choice in
            1) install_bedolaga ;;
            2) install_cabinet ;;
            3) update_bedolaga ;;
            4) setup_caddy_for_bedolaga ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

install_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}💰 Установка Bedolaga Bot${NC}\n"

    install_docker

    echo -e "${YELLOW}Где устанавливается бот?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" server_location

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

    docker network create remnawave-network 2>/dev/null || true
    docker network create remnawave_bot_network 2>/dev/null || true

    if [[ "$server_location" == "1" ]]; then
        if [ -f "docker-compose.local.yml" ]; then
            rm -f docker-compose.yml
            mv docker-compose.local.yml docker-compose.yml
        fi
    fi

    docker compose up -d

    if [[ "$server_location" == "1" ]]; then
        BEDOLAGA_BLOCK="https://$BEDOLAGA_DOMAIN {
    encode gzip zstd
    handle {
        reverse_proxy remnawave_bot:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            transport http {
                read_buffer 0
            }
        }
    }
}"
        add_caddy_block "$BEDOLAGA_DOMAIN" "$BEDOLAGA_BLOCK"
        
        cd /opt/remnawave/caddy
        docker compose down && docker compose up -d
    fi

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

    # Caddy блок
    CABINET_BLOCK="https://$CABINET_DOMAIN {
    encode gzip zstd
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }
    handle {
        reverse_proxy cabinet_frontend:80
    }
}"
    add_caddy_block "$CABINET_DOMAIN" "$CABINET_BLOCK"
    
    cd /opt/remnawave/caddy
    docker compose down && docker compose up -d

    # Запуск контейнера Cabinet
    cd /opt/bedolaga-cabinet
    docker compose up -d

    # Подключение сети
    echo -e "${YELLOW}🔗 Подключаем Cabinet к сети Caddy...${NC}"
    docker network connect bedolaga-cabinet_default caddy 2>/dev/null || true

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

# ============================================
# ОБНОВЛЕННАЯ ФУНКЦИЯ: НАСТРОЙКА CADDY ДЛЯ BEDOLAGA
# ============================================
setup_caddy_for_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Настройка Caddy для Bedolaga Bot + Cabinet${NC}\n"

    # Проверка наличия бота
    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Bedolaga Bot не установлен (нет /opt/bedolaga-bot).${NC}"
        echo -e "Сначала установите бота через пункт меню 2 → 1."
        read -p "Нажмите Enter для возврата..."
        return
    fi

    # Проверка наличия Caddy
    if ! ensure_caddy_running; then
        return
    fi

    # Определяем домены
    blocks_dir="/opt/remnawave/caddy/blocks"
    BOT_DOMAIN=""
    CABINET_DOMAIN=""

    # Сканируем существующие блоки
    if [ -d "$blocks_dir" ]; then
        for block_file in "$blocks_dir"/*; do
            if [ -f "$block_file" ]; then
                block_content=$(cat "$block_file")
                # Ищем блок для бота (прокси на remnawave_bot:8080)
                if echo "$block_content" | grep -q "reverse_proxy remnawave_bot:8080"; then
                    # Если уже есть блок для бота, не перезаписываем, если только это не блок кабинета
                    # Но блок кабинета тоже может иметь reverse_proxy remnawave_bot:8080 для /api
                    # Поэтому проверяем, есть ли handle /api/* в блоке - если есть, это кабинет
                    if ! echo "$block_content" | grep -q "handle /api/\*"; then
                        BOT_DOMAIN=$(basename "$block_file")
                    fi
                fi
                # Ищем блок для кабинета (прокси на cabinet_frontend:80 или file_server)
                if echo "$block_content" | grep -q "reverse_proxy cabinet_frontend:80" || echo "$block_content" | grep -q "file_server /srv/cabinet"; then
                    CABINET_DOMAIN=$(basename "$block_file")
                fi
            fi
        done
    fi

    # Если не нашли домен бота, пробуем вытянуть из .env бота
    if [ -z "$BOT_DOMAIN" ] && [ -f "/opt/bedolaga-bot/.env" ]; then
        BOT_DOMAIN=$(grep -E "^WEBHOOK_URL=" /opt/bedolaga-bot/.env | sed -E 's|^WEBHOOK_URL=https?://([^:/]+).*$|\1|')
    fi

    # Если не нашли домен кабинета, пробуем из .env кабинета
    if [ -z "$CABINET_DOMAIN" ] && [ -f "/opt/bedolaga-cabinet/.env" ]; then
        CABINET_DOMAIN=$(grep -E "^VITE_API_URL=" /opt/bedolaga-cabinet/.env | sed -E 's|^.*//([^:/]+).*$|\1|')
    fi

    # Если всё ещё пусто – запрашиваем вручную
    if [ -z "$BOT_DOMAIN" ]; then
        echo -e "${YELLOW}Не удалось автоматически определить домен для бота.${NC}"
        read -p "🌐 Введите домен для Bedolaga Bot (например bot.myvpn.com): " BOT_DOMAIN
        if [ -z "$BOT_DOMAIN" ]; then
            echo -e "${RED}❌ Домен не введён. Отмена.${NC}"
            read -p "Нажмите Enter..."
            return
        fi
    fi

    if [ -z "$CABINET_DOMAIN" ]; then
        if [ -d "/opt/bedolaga-cabinet" ]; then
            echo -e "${YELLOW}Не удалось автоматически определить домен для Cabinet.${NC}"
            read -p "🌐 Введите домен для Cabinet (например cabinet.myvpn.com): " CABINET_DOMAIN
            if [ -z "$CABINET_DOMAIN" ]; then
                echo -e "${RED}❌ Домен не введён. Пропускаем настройку кабинета.${NC}"
                CABINET_DOMAIN=""
            fi
        else
            echo -e "${YELLOW}Cabinet не установлен, пропускаем его настройку.${NC}"
        fi
    fi

    # Выводим пользователю найденные/введённые домены и просим подтверждения
    echo -e "\n${CYAN}${BOLD}Найденные домены:${NC}"
    echo -e "  🤖 Бот:      ${BOLD}$BOT_DOMAIN${NC}"
    if [ -n "$CABINET_DOMAIN" ]; then
        echo -e "  🗄️  Cabinet:  ${BOLD}$CABINET_DOMAIN${NC}"
    else
        echo -e "  🗄️  Cabinet:  ${YELLOW}не установлен${NC}"
    fi
    echo ""
    read -p "Всё верно? (y — продолжить, n — изменить домены): " confirm

    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        read -p "🌐 Введите новый домен для БОТА: " BOT_DOMAIN
        if [ -n "$CABINET_DOMAIN" ]; then
            read -p "🌐 Введите новый домен для CABINET: " CABINET_DOMAIN
        fi
    fi

    # Создаём блоки Caddy
    echo -e "\n${YELLOW}🔧 Добавляем/обновляем блоки Caddy...${NC}"

    # Блок для бота (прокси на remnawave_bot:8080)
    BOT_BLOCK="https://$BOT_DOMAIN {
    encode gzip zstd
    handle {
        reverse_proxy remnawave_bot:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            transport http {
                read_buffer 0
            }
        }
    }
}"
    add_caddy_block "$BOT_DOMAIN" "$BOT_BLOCK"

    # Блок для кабинета, если задан
    if [ -n "$CABINET_DOMAIN" ]; then
        # Определяем, как раздаётся кабинет: через контейнер cabinet_frontend или статика
        # Если есть папка /srv/cabinet с файлами, используем file_server
        # Иначе используем reverse_proxy на cabinet_frontend:80
        if [ -d "/srv/cabinet" ] && [ -f "/srv/cabinet/index.html" ]; then
            CABINET_BLOCK="https://$CABINET_DOMAIN {
    encode gzip zstd
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }
    handle {
        root * /srv/cabinet
        file_server
    }
}"
        else
            CABINET_BLOCK="https://$CABINET_DOMAIN {
    encode gzip zstd
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }
    handle {
        reverse_proxy cabinet_frontend:80
    }
}"
        fi
        add_caddy_block "$CABINET_DOMAIN" "$CABINET_BLOCK"
    fi

    # Перезапускаем Caddy
    echo -e "${YELLOW}🔄 Перезапускаем Caddy...${NC}"
    cd /opt/remnawave/caddy
    if [ -f "docker-compose.yml" ]; then
        docker compose down 2>/dev/null
        docker compose up -d
        echo -e "${GREEN}✅ Caddy перезапущен.${NC}"
    else
        echo -e "${RED}❌ Файл docker-compose.yml для Caddy не найден.${NC}"
        echo -e "Пожалуйста, установите Caddy через установку панели."
        read -p "Нажмите Enter..."
        return
    fi

    # Дополнительно: проверяем .env бота на наличие переменных для Cabinet
    if [ -n "$CABINET_DOMAIN" ] && [ -f "/opt/bedolaga-bot/.env" ]; then
        if ! grep -q "CABINET_ENABLED=true" /opt/bedolaga-bot/.env; then
            echo -e "${YELLOW}⚠️  В .env бота отсутствуют настройки Cabinet. Добавляем...${NC}"
            CABINET_JWT_SECRET=$(openssl rand -hex 32)
            cat >> /opt/bedolaga-bot/.env <<EOF

# Bedolaga Cabinet (добавлено автоматически)
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
CABINET_URL=https://$CABINET_DOMAIN
EOF
            echo -e "${GREEN}✅ Настройки Cabinet добавлены. Перезапускаем бота...${NC}"
            cd /opt/bedolaga-bot
            docker compose restart
        fi
    fi

    echo -e "\n${GREEN}${BOLD}✅ Настройка Caddy для Bedolaga завершена!${NC}"
    echo -e "🌐 Бот: https://$BOT_DOMAIN"
    [ -n "$CABINET_DOMAIN" ] && echo -e "🗄️  Cabinet: https://$CABINET_DOMAIN"
    echo -e "\n"
    read -p "Нажмите Enter для возврата..."
}

# ============================================
# ОПЦИЯ 3: REMNAWAVE ADMIN WEB + BOT
# ============================================
install_admin_bot() {
    show_logo
    echo -e "${BLUE}${BOLD}🤖 Установка Remnawave Admin Web + Bot${NC}\n"

    install_docker

    echo -e "${YELLOW}Где устанавливается Admin Bot?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" server_location

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

    docker network create remnawave-network 2>/dev/null || true
    docker compose up -d

    if [[ "$server_location" == "1" ]]; then
        ADMIN_BLOCK="https://$ADMIN_DOMAIN {
    handle {
        reverse_proxy web-frontend:80
    }
    handle /api/* {
        reverse_proxy web-backend:9091 {
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    handle /ws/* {
        reverse_proxy web-backend:9091
    }
}"
        add_caddy_block "$ADMIN_DOMAIN" "$ADMIN_BLOCK"
        
        cd /opt/remnawave/caddy
        docker compose down && docker compose up -d
    fi

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
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" log_choice

        case $log_choice in
            1) show_panel_logs ;;
            2) show_subscription_logs ;;
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
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

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
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

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
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}0)${NC} 🚪 Выход"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" main_choice

    case $main_choice in
        1) show_remnawave_menu ;;
        2) show_bedolaga_menu ;;
        3) install_admin_bot ;;
        4) show_warp_menu ;;
        5) run_backup ;;
        6) show_logs_menu ;;
        0) echo -e "${GREEN}👋 До свидания!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
    esac
done
