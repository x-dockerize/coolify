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
SSH_USER="$(whoami)"
LOCALHOST_KEY=".docker/coolify/data/ssh/keys/localhost_key"

for dir in ssh ssh/keys applications databases services backups webhooks-during-maintenance; do
  mkdir -p ".docker/coolify/data/$dir"
done

if [ ! -f "$LOCALHOST_KEY" ]; then
  ssh-keygen -t ed25519 -f "$LOCALHOST_KEY" -N "" -C "coolify-localhost" -q
  echo "✅ Localhost SSH anahtarı oluşturuldu"
else
  echo "ℹ️  Localhost SSH anahtarı mevcut, atlanıyor"
fi

mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -v "coolify-localhost" ~/.ssh/authorized_keys > /tmp/ak_tmp 2>/dev/null && mv /tmp/ak_tmp ~/.ssh/authorized_keys || true
cat "${LOCALHOST_KEY}.pub" >> ~/.ssh/authorized_keys
echo "✅ Public key ~/.ssh/authorized_keys'e eklendi/güncellendi"

chmod -R 700 ".docker/coolify/data/ssh"
chown -R 9999:9999 ".docker/coolify/data/ssh" 2>/dev/null || true
echo "✅ .docker/coolify/data/ dizinleri hazırlandı"

# --------------------------------------------------
# Localhost Sunucu Kurulum Scripti
# --------------------------------------------------
cat > "setup-localhost-server.sh" << 'BASH'
#!/usr/bin/env bash
# Kullanım:
#   1. docker compose up -d sonrası çalıştır (SSH izinlerini düzeltir)
#   2. Sihirbazda kullanıcı kaydı sonrası tekrar çalıştır (DB kayıtlarını oluşturur)
set -e

docker exec -u root coolify chown -R 9999:9999 /var/www/html/storage/app/ssh
echo "✓ SSH izinleri düzeltildi"

docker exec -it coolify php artisan tinker --execute="
if (!\DB::table('teams')->where('id', 0)->exists()) {
  echo 'Önce sihirbazda kullanıcı kaydı yapın, sonra tekrar çalıştırın.' . PHP_EOL;
} elseif (\DB::table('servers')->where('id', 0)->exists()) {
  echo 'Localhost sunucusu zaten mevcut.' . PHP_EOL;
} else {
  \$keyContent = trim((string)file_get_contents('/var/www/html/storage/app/ssh/keys/localhost_key'));
  if (empty(\$keyContent)) { echo 'HATA: localhost_key okunamadi.' . PHP_EOL; return; }
  \$pk = new \App\Models\PrivateKey();
  \$pk->uuid = (string)\Str::uuid();
  \$pk->name = 'devops-localhost';
  \$pk->private_key = \$keyContent;
  \$pk->team_id = 0;
  \$pk->save();
  \$keyId = \$pk->id;
  \$sql = 'INSERT INTO servers (id, uuid, name, ip, port, \"user\", team_id, private_key_id, proxy, created_at, updated_at) VALUES (0, gen_random_uuid(), \'devops\', \'host.docker.internal\', 22, \'__SSH_USER__\', 0, ' . \$keyId . ', \'{\"type\":\"NONE\",\"status\":\"stopped\",\"force_stop\":true,\"force_disabled\":false}\', NOW(), NOW())';
  \DB::statement(\$sql);
  \DB::table('server_settings')->insert(['server_id' => 0, 'created_at' => now(), 'updated_at' => now()]);
  echo 'Localhost sunucusu (id=0) olusturuldu.' . PHP_EOL;
}
"
BASH
sed -i "s|__SSH_USER__|$SSH_USER|g" setup-localhost-server.sh
chmod +x setup-localhost-server.sh
echo "✅ setup-localhost-server.sh oluşturuldu"

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
echo "  2. SSH izinlerini düzelt ve localhost sunucu kaydını oluştur:"
echo "     ./setup-localhost-server.sh"
echo "     (sihirbazdan ÖNCE çalıştır)"
echo ""
echo "  3. İlk kurulum sihirbazını tamamla:"
echo "     https://$COOLIFY_SERVER_HOSTNAME/install"
echo ""
echo "  4. Coolify'in kendi proxy'sini devre dışı bırak:"
echo "     docker exec -it coolify php artisan tinker --execute=\""
echo "     \App\Models\Server::all()->each(function(\$s) {"
echo "       \$p = \$s->proxy; \$p['type'] = 'NONE'; \$p['status'] = 'stopped'; \$p['force_stop'] = true;"
echo "       \$s->proxy = \$p; \$s->save(); echo \$s->name . PHP_EOL;"
echo "     });\""
echo "     (Mevcut Traefik korunur, çakışma olmaz)"
echo "==============================================="
