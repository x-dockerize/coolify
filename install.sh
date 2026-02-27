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

# --------------------------------------------------
# Veri Dizinleri
# --------------------------------------------------
for dir in ssh applications databases services backups webhooks-during-maintenance; do
  mkdir -p "/data/coolify/$dir"
done
echo "✅ /data/coolify/ dizinleri hazırlandı"

# --------------------------------------------------
# Veritabanı
# --------------------------------------------------
echo "🗄️  Coolify veritabanı oluşturuluyor..."

DB_PASSWORD_VAL=$(grep "^DB_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2-)

if [ -z "$DB_PASSWORD_VAL" ]; then
  DB_PASSWORD_VAL="$(gen_password)"
  set_env DB_PASSWORD "$DB_PASSWORD_VAL"
fi

docker exec postgres psql -U postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='coolify'" | grep -q 1 || \
  docker exec postgres psql -U postgres -c "CREATE USER coolify WITH PASSWORD '${DB_PASSWORD_VAL}';"

docker exec postgres psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='coolify'" | grep -q 1 || \
  docker exec postgres psql -U postgres -c "CREATE DATABASE coolify OWNER coolify;"

echo "✅ Veritabanı hazır"

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
