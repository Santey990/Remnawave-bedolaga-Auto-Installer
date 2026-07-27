setup_caddy_for_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Настройка Caddy для Bedolaga Bot + Cabinet${NC}\n"
    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Bedolaga Bot не установлен.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    # Определяем домены автоматически
    BOT_DOMAIN=""
    CABINET_DOMAIN=""
    [ -f "/opt/bedolaga-bot/.env" ] && BOT_DOMAIN=$(grep -E "^WEBHOOK_URL=" /opt/bedolaga-bot/.env | sed -E 's|^WEBHOOK_URL=https?://([^:/]+).*$|\1|')
    [ -f "/opt/bedolaga-bot/.env" ] && CABINET_DOMAIN=$(grep -E "^CABINET_URL=" /opt/bedolaga-bot/.env | sed -E 's|^CABINET_URL=https?://([^:/]+).*$|\1|')

    if [ -z "$BOT_DOMAIN" ]; then
        read -p "🌐 Введите домен для БОТА: " BOT_DOMAIN
    fi
    if [ -z "$CABINET_DOMAIN" ] && [ -d "/opt/bedolaga-cabinet" ]; then
        echo -e "${YELLOW}Не удалось автоматически определить домен для Cabinet.${NC}"
        read -p "🌐 Введите домен для CABINET (или оставьте пустым для пропуска): " CABINET_DOMAIN
    fi

    if [ -n "$BOT_DOMAIN" ]; then
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
    else
        echo -e "${RED}❌ Домен бота не указан, пропускаем.${NC}"
    fi

    if [ -n "$CABINET_DOMAIN" ]; then
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

    cd /opt/remnawave/caddy
    docker compose down && docker compose up -d
    docker network connect remnawave_bot_network caddy 2>/dev/null || true
    docker network connect bedolaga-bot_bot_network caddy 2>/dev/null || true
    docker network connect bedolaga-cabinet_default caddy 2>/dev/null || true

    if [ -n "$CABINET_DOMAIN" ] && [ -f "/opt/bedolaga-bot/.env" ]; then
        if ! grep -q "CABINET_ENABLED=true" /opt/bedolaga-bot/.env; then
            echo -e "${YELLOW}⚠️  Добавляем настройки Cabinet в .env бота...${NC}"
            CABINET_JWT_SECRET=$(openssl rand -hex 32)
            cat >> /opt/bedolaga-bot/.env <<EOC

# Bedolaga Cabinet (добавлено автоматически)
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
CABINET_URL=https://$CABINET_DOMAIN
EOC
            cd /opt/bedolaga-bot && docker compose restart
        fi
    fi

    echo -e "${GREEN}✅ Настройка Caddy завершена!${NC}"
    if [ -n "$BOT_DOMAIN" ]; then
        echo -e "🌐 Бот: https://$BOT_DOMAIN:$CADDY_HTTPS_PORT"
    fi
    if [ -n "$CABINET_DOMAIN" ]; then
        echo -e "🗄️  Cabinet: https://$CABINET_DOMAIN:$CADDY_HTTPS_PORT"
    fi
    read -p "Нажмите Enter..."
}
