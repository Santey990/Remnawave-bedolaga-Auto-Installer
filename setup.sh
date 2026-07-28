#!/bin/bash
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция вывода сообщений
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен запускаться от root (sudo)"
fi

# --- Функции проверки системы ---
check_system() {
    info "Проверка системных требований..."

    # ОС
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            warn "Скрипт оптимизирован для Ubuntu/Debian, но может работать на других системах."
        fi
    else
        warn "Не удалось определить ОС."
    fi

    # Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен. Установите Docker и повторите попытку."
    else
        info "Docker установлен: $(docker --version)"
    fi

    # Docker Compose (проверяем оба варианта)
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        info "Docker Compose (standalone) установлен: $(docker-compose --version)"
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        info "Docker Compose (plugin) установлен: $(docker compose version)"
    else
        error "Docker Compose не установлен. Установите его."
    fi

    # Git
    if ! command -v git &> /dev/null; then
        error "Git не установлен. Установите git: apt install git -y"
    fi

    # Nginx
    if ! command -v nginx &> /dev/null; then
        error "Nginx не установлен. Установите nginx."
    else
        info "Nginx установлен: $(nginx -v 2>&1)"
    fi

    # Certbot
    if ! command -v certbot &> /dev/null; then
        warn "Certbot не найден. Он будет установлен автоматически."
    fi

    # Проверка порта 8080
    if ss -tulpn | grep -q ":8080 "; then
        error "Порт 8080 уже занят. Освободите его или измените порт в .env бота."
    else
        info "Порт 8080 свободен."
    fi

    info "Все системные проверки пройдены."
}

# --- Запрос данных у пользователя ---
get_user_input() {
    echo ""
    info "Введите необходимые данные для установки Bedolaga."

    read -p "Введите основной домен (например, example.com): " MAIN_DOMAIN
    if [[ -z "$MAIN_DOMAIN" ]]; then
        error "Домен не может быть пустым."
    fi

    read -p "Введите поддомен для вебхука бота (например, hooks.$MAIN_DOMAIN): " WEBHOOK_DOMAIN
    if [[ -z "$WEBHOOK_DOMAIN" ]]; then
        WEBHOOK_DOMAIN="hooks.$MAIN_DOMAIN"
        info "Используем поддомен по умолчанию: $WEBHOOK_DOMAIN"
    fi

    read -p "Введите поддомен для веб-кабинета (например, cabinet.$MAIN_DOMAIN): " CABINET_DOMAIN
    if [[ -z "$CABINET_DOMAIN" ]]; then
        CABINET_DOMAIN="cabinet.$MAIN_DOMAIN"
        info "Используем поддомен по умолчанию: $CABINET_DOMAIN"
    fi

    read -p "Введите токен бота от @BotFather: " BOT_TOKEN
    if [[ -z "$BOT_TOKEN" ]]; then
        error "Токен бота обязателен."
    fi

    read -p "Введите ваш Telegram ID (администратор): " ADMIN_IDS
    if [[ -z "$ADMIN_IDS" ]]; then
        error "Telegram ID обязателен."
    fi

    read -p "Введите URL вашей панели Remnawave (например, https://panel.$MAIN_DOMAIN): " REMNAWAVE_API_URL
    if [[ -z "$REMNAWAVE_API_URL" ]]; then
        error "URL панели обязателен."
    fi

    read -p "Введите API-ключ от панели Remnawave: " REMNAWAVE_API_KEY
    if [[ -z "$REMNAWAVE_API_KEY" ]]; then
        error "API-ключ обязателен."
    fi

    # Генерация секретов
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    CABINET_JWT_SECRET=$(openssl rand -hex 32)

    info "Сгенерированы секреты: WEBHOOK_SECRET и CABINET_JWT_SECRET."

    # Сохраняем в переменные для дальнейшего использования
    export MAIN_DOMAIN WEBHOOK_DOMAIN CABINET_DOMAIN BOT_TOKEN ADMIN_IDS \
           REMNAWAVE_API_URL REMNAWAVE_API_KEY WEBHOOK_SECRET CABINET_JWT_SECRET
}

# --- Установка Certbot (если отсутствует) ---
install_certbot() {
    if ! command -v certbot &> /dev/null; then
        info "Устанавливаем Certbot..."
        apt update && apt install -y certbot python3-certbot-nginx
    else
        info "Certbot уже установлен."
    fi
}

# --- Установка бота ---
install_bot() {
    info "Клонируем репозиторий Bedolaga Bot..."
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git /opt/bedolaga-bot || {
        error "Не удалось клонировать репозиторий. Проверьте доступ к GitHub."
    }
    cd /opt/bedolaga-bot

    info "Создаём .env файл..."
    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
REMNAWAVE_API_URL=$REMNAWAVE_API_URL
REMNAWAVE_API_KEY=$REMNAWAVE_API_KEY

# Режим вебхука
BOT_RUN_MODE=webhook
WEBHOOK_URL=https://$WEBHOOK_DOMAIN
WEBHOOK_PATH=/webhook
WEBHOOK_SECRET_TOKEN=$WEBHOOK_SECRET

# API бота
WEB_API_ENABLED=true
WEB_API_PORT=8080
WEB_API_HOST=0.0.0.0
WEB_API_ALLOWED_ORIGINS=https://$CABINET_DOMAIN

# Кабинет
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
EOF

    info "Запускаем контейнеры бота..."
    $COMPOSE_CMD up -d

    # Проверяем, что контейнер запустился
    sleep 5
    if docker ps | grep -q "remnawave_bot"; then
        info "Бот успешно запущен."
    else
        warn "Контейнер бота не запущен. Проверьте логи: $COMPOSE_CMD logs"
    fi
}

# --- Установка Cabinet (статики) ---
install_cabinet() {
    info "Устанавливаем Cabinet..."
    mkdir -p /srv/cabinet

    # Извлекаем файлы из Docker-образа
    docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker cp tmp_cabinet:/usr/share/nginx/html/. /srv/cabinet/
    docker rm tmp_cabinet

    info "Файлы Cabinet скопированы в /srv/cabinet"
}

# --- Настройка Nginx ---
configure_nginx() {
    info "Настраиваем Nginx..."

    # Создаём конфигурационный файл для двух поддоменов
    NGINX_CONF="/etc/nginx/sites-available/bedolaga.conf"
    cat > $NGINX_CONF <<EOF
# Конфигурация для вебхука бота
server {
    listen 80;
    server_name $WEBHOOK_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $WEBHOOK_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Конфигурация для веб-кабинета
server {
    listen 80;
    server_name $CABINET_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $CABINET_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root /srv/cabinet;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Создаём симлинк в sites-enabled
    ln -sf $NGINX_CONF /etc/nginx/sites-enabled/

    # Проверяем конфигурацию
    if nginx -t; then
        info "Конфигурация Nginx проверена успешно."
    else
        error "Ошибка в конфигурации Nginx. Проверьте синтаксис."
    fi

    # Перезагружаем Nginx
    systemctl reload nginx
    info "Nginx перезагружен."
}

# --- Получение SSL-сертификатов для поддоменов ---
obtain_ssl() {
    info "Получаем SSL-сертификаты для поддоменов $WEBHOOK_DOMAIN, $CABINET_DOMAIN..."

    # Проверяем, что DNS записи уже указывают на этот сервер (рекомендация)
    warn "Убедитесь, что DNS записи для $WEBHOOK_DOMAIN и $CABINET_DOMAIN указывают на IP этого сервера."
    read -p "Нажмите Enter, чтобы продолжить, или Ctrl+C для отмены..."

    certbot --nginx -d $WEBHOOK_DOMAIN -d $CABINET_DOMAIN --non-interactive --agree-tos --email admin@$MAIN_DOMAIN --redirect

    if [[ $? -eq 0 ]]; then
        info "SSL-сертификаты успешно получены."
        # Перезагружаем Nginx, чтобы применить новые сертификаты (если certbot не сделал это автоматически)
        systemctl reload nginx
    else
        error "Не удалось получить SSL-сертификаты. Проверьте доступность доменов и DNS."
    fi
}

# --- Финальные проверки ---
final_check() {
    info "Проверяем работу бота и кабинета..."

    # Логи бота
    echo "Последние логи бота:"
    cd /opt/bedolaga-bot
    $COMPOSE_CMD logs --tail=20 remnawave_bot

    info "Установка завершена!"
    echo "--------------------------------------------------"
    echo "Веб-кабинет доступен по адресу: https://$CABINET_DOMAIN"
    echo "Бот должен отвечать на команду /start в Telegram."
    echo "Для просмотра логов: cd /opt/bedolaga-bot && $COMPOSE_CMD logs -f"
    echo "--------------------------------------------------"
}

# --- Основной процесс ---
main() {
    info "Начинаем автоматическую установку Bedolaga Bot и Cabinet..."

    check_system
    get_user_input
    install_certbot
    install_bot
    install_cabinet
    configure_nginx
    obtain_ssl
    final_check
}

main
