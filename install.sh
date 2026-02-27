#!/usr/bin/env bash
set -e

ENV_EXAMPLE=".env.example"
ENV_FILE=".env"

# --------------------------------------------------
# Kontroller
# --------------------------------------------------
if [ ! -f "$ENV_EXAMPLE" ]; then
  echo "❌ $ENV_EXAMPLE bulunamadı."
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo "✅ $ENV_EXAMPLE → $ENV_FILE kopyalandı"
else
  echo "ℹ️  $ENV_FILE mevcut, güncellenecek"
fi

# --------------------------------------------------
# Yardımcı Fonksiyonlar
# --------------------------------------------------
gen_password() {
  openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20
}

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

set_env_once() {
  local key="$1"
  local value="$2"

  local current
  current=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)

  if [ -z "$current" ]; then
    set_env "$key" "$value"
  fi
}

# --------------------------------------------------
# Kullanıcıdan Gerekli Bilgiler
# --------------------------------------------------
read -rp "COOLIFY_SERVER_HOSTNAME (örn: coolify.example.com): " COOLIFY_SERVER_HOSTNAME

echo
echo "--- Veritabanı ---"
read -rp "DB_HOST (boş bırakılırsa: postgres): " INPUT_DB_HOST
DB_HOST="${INPUT_DB_HOST:-postgres}"
read -rp "DB_USERNAME (boş bırakılırsa: coolify): " INPUT_DB_USERNAME
DB_USERNAME="${INPUT_DB_USERNAME:-coolify}"
read -rsp "DB_PASSWORD: " DB_PASSWORD
echo

# --------------------------------------------------
# Veri Dizinleri
# --------------------------------------------------
for dir in ssh applications databases services backups webhooks-during-maintenance; do
  mkdir -p ".docker/coolify/data/$dir"
done
echo "✅ .docker/coolify/data/ dizinleri hazırlandı"

# --------------------------------------------------
# Docker Network
# --------------------------------------------------
NETWORK_NAME="coolify"
if docker network inspect "$NETWORK_NAME" > /dev/null 2>&1; then
  echo "ℹ️  Docker network '$NETWORK_NAME' zaten mevcut"
else
  docker network create "$NETWORK_NAME"
  echo "✅ Docker network '$NETWORK_NAME' oluşturuldu"
fi

# --------------------------------------------------
# .env Güncelle
# --------------------------------------------------
set_env COOLIFY_SERVER_HOSTNAME "$COOLIFY_SERVER_HOSTNAME"
set_env APP_URL                 "https://${COOLIFY_SERVER_HOSTNAME}"
set_env PUSHER_HOST             "${COOLIFY_SERVER_HOSTNAME}"
set_env DB_HOST                 "$DB_HOST"
set_env DB_USERNAME             "$DB_USERNAME"
set_env DB_PASSWORD             "$DB_PASSWORD"

# Secret'lar — mevcut değerlerin üzerine yazılmaz
set_env_once APP_ID            "$(openssl rand -hex 16)"
set_env_once APP_KEY           "base64:$(openssl rand -base64 32)"
set_env_once REDIS_PASSWORD    "$(gen_password)"
set_env_once PUSHER_APP_ID     "$(openssl rand -hex 16)"
set_env_once PUSHER_APP_KEY    "$(openssl rand -hex 16)"
set_env_once PUSHER_APP_SECRET "$(openssl rand -hex 32)"

# --------------------------------------------------
# Sonuçları Göster
# --------------------------------------------------
echo
echo "==============================================="
echo "✅ Coolify .env başarıyla hazırlandı!"
echo "-----------------------------------------------"
echo "🌐 Hostname : https://$COOLIFY_SERVER_HOSTNAME"
echo "-----------------------------------------------"
echo "⚠️  Kurulum sonrası ZORUNLU adımlar:"
echo ""
echo "  1. Servisleri başlat:"
echo "     docker compose -f docker-compose.production.yml up -d"
echo ""
echo "  2. İlk kurulum sihirbazını tamamla:"
echo "     https://$COOLIFY_SERVER_HOSTNAME/install"
echo ""
echo "  3. Settings → Server → Proxy seçeneğini"
echo "     'None' olarak ayarla."
echo "     (Mevcut Traefik korunur, çakışma olmaz)"
echo "==============================================="
