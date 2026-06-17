# 3x-ui and VPN Deploy Scripts

## ⚡ 3x-ui Docker Panel

Installer for **3x-ui** Docker Edition with host network mode and UNIX socket support.

### Installation

```bash
bash 3x-ui-docker.sh
```

### Highlights

- **SQLite Database Preservation** — automatically migrates and preserves existing standalone x-ui database if found at `/etc/x-ui/x-ui.db`.
- **UNIX Socket Configuration** — mounts `/dev/shm` to share Unix sockets with Nginx Selfsteal container for stealthy proxying.
- **Port Conflict Checks** — verifies port availability (`80`, `443`, `2053`) before launching container.

---

## 🎭 Caddy Selfsteal (Reality Masking)

Deploy Caddy as a **Reality traffic masking** solution with professional website templates for HTTPS camouflage.

### Installation

Compile and run via the Makefile:
```bash
# Production install
make run ARGS="--domain your-domain.com install"

# Staging test install (uses Let's Encrypt staging to bypass rate limits)
make run ARGS="--domain your-domain.com --test install"
```

Or run the compiled script directly:
```bash
./dist/selfsteal.sh --domain your-domain.com install
```

### Commands

| Command | Description |
|---------|-------------|
| `install` / `uninstall` | Install or remove |
| `up` / `down` / `restart` | Service lifecycle |
| `status` / `logs` | Status & logs |
| `template` | Manage website templates |
| `edit` | Edit Caddyfile |
| `guide` | Reality integration guide |
| `update` | Update script |

### Templates

8 pre-built website templates: `10gag`, `converter`, `downloader`, `filecloud`, `games-site`, `modmanager`, `speedtest`, `YouTube`.

```bash
selfsteal template list              # List templates
selfsteal template install converter # Install template
```

> 🛡️ **v2.8.0:** every template is uniquified per install (no byte-identical fingerprint) and provenance leaks are stripped. HTTP/3 is **off by default** — enable with `--h3`; disable mutation with `--no-randomize`. Use `--test` or `--staging` to run with Let's Encrypt staging environment.

**Xray Reality config:**
```json
{ "realitySettings": { "dest": "127.0.0.1:9443", "serverNames": ["your-domain.com"] } }
```

<details>
<summary><b>🔒 Production Hardening</b></summary>

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow from trusted_ip to any port panel_port
sudo ufw enable
```

</details>

---

## 📊 Monitoring & Logs

```bash
selfsteal status   # Service status
selfsteal logs     # Real-time logs
docker stats       # Resource usage
```

<details>
<summary><b>📋 Log Locations</b></summary>

| Component | Path |
|-----------|------|
| 3x-ui Panel | `/opt/3x-ui/backups/` |
| Caddy / Nginx | `/opt/caddy/logs/` or `/opt/nginx-selfsteal/logs/` |

Log rotation: 50MB max, 5 files kept, compressed automatically.

</details>


### 🐦 NetBird

Quick installer for [NetBird](https://netbird.io/) mesh VPN. Supports CLI, cloud-init, interactive menu, and Ansible modes.

```bash
# CLI installation
bash netbird.sh install --key YOUR-SETUP-KEY

# Auto-install for cloud-init / provisioning
bash netbird.sh init --key YOUR-SETUP-KEY

# Interactive menu
bash netbird.sh menu
```

### Building the Selfsteal Script

The `selfsteal.sh` script is built from modular components located in the `src/` directory. If you are developing and modifying the `selfsteal` script:

1. Edit the relevant files in `src/` (e.g., `src/selfsteal/main.sh`, `src/selfsteal/acme.sh`).
2. Run the build script to compile them:
   ```bash
   bash build.sh src/selfsteal/main.sh > dist/selfsteal.sh
   ```
3. Test your changes by running the compiled script.


---

## 📖 Deep-Dive Research & Workarounds
For advanced details on Deep Packet Inspection (DPI) evasion, the "Siberian Block" behavioral rules, and client configuration optimizations, see the [DPI Research Guide](README-DPI-Research.md) or the developer onboarding [GEMINI.md](GEMINI.md).


> ⚠️ Порт ACME нужен только временно во время получения/обновления сертификата.


#### Преимущества Unix Socket (Nginx)
- **Быстрее**: Нет накладных расходов на TCP стек
- **Безопаснее**: Не занимает сетевой порт
- **Проще**: Нет конфликтов портов

> 🛡️ **Устойчивость к активному пробингу (РКН/ТСПУ).** При активной пробе Reality форвардит соединение на dest, и пробер завершает реальное TLS-рукопожатие напрямую с веб-сервером. Caddy использует Go `crypto/tls` с узнаваемым отпечатком (JARM/JA3S и HTTP/2 SETTINGS), который **нельзя изменить средствами Caddy**. Nginx (OpenSSL) выглядит как обычный сайт. Поэтому при жёстком пробинге **Nginx как dest объективно «тише»** — если бан повторяется даже после отключения h3, переходите на `--nginx`. Также в острые периоды помогает увод Reality с порта 443 на высокий порт (47000+).

### Шаблоны сайтов

Команда `template` позволяет выбрать один из 11 AI-генерированных шаблонов, созданных нейросетью специально для реалистичной маскировки трафика:

#### 🎨 Доступные шаблоны:

1. **😂 10gag - Сайт мемов**: Платформа для просмотра мемов с имитацией видеоконтента
2. **🎬 Converter - Видеостудия-конвертер**: Онлайн сервис для конвертации видео с поддержкой популярных платформ
3. **📁 Convertit - Конвертер файлов**: Универсальный конвертер с проверкой форматов и симуляцией обработки
4. **⬇️ Downloader - Даунлоадер**: Сервис загрузок с системой приглашений и проверками
5. **☁️ FileCloud - Облачное хранилище**: Файлохранилище с красивой формой авторизации и файловым менеджером
6. **🎮 Games-site - Ретро игровой портал**: Сайт с классическими браузерными играми и сгенерированными ИИ обложками
7. **🛠️ ModManager - Мод-менеджер для игр**: Имитация сайта для управления модификациями игр
8. **🚀 SpeedTest - Спидтест**: Тестирование скорости интернет-соединения с русской локализацией
9. **📺 YouTube - Видеохостинг с капчей**: Платформа для видео с бесконечной капчей и плиточным интерфейсом
10. **⚠️ 503 Error v1 - Страница ошибки 503**: Стильная страница ошибки с отображением IP-адреса клиента
11. **⚠️ 503 Error v2 - Страница ошибки 503**: Альтернативный дизайн страницы ошибки

#### 🛡️ Уникализация и защита от фингерпринтинга (с v2.8.0)

Базовые шаблоны публичны и **байт-в-байт** совпадают у всех, кто их ставит — это позволяет цензору хешировать страницу и заносить в чёрный список. Поэтому при установке шаблон **автоматически мутируется**, чтобы каждый сервер был уникален и не совпадал с публичным оригиналом:

- 🎲 **Уникальность каждого инстанса**: случайные `<title>`/бренд/meta, per-install сдвиг палитры (hue-rotate), байт-«шум» в html/css/js, рандомный `?v=`, свежий `favicon.svg` — два сервера никогда не отдают идентичные файлы.
- 🧹 **Зачистка утечек**: удаляются `README.md`/`*.md`/`*.map` из веб-рута (в них были ссылки на исходный репозиторий), глушится «маяк» на `api.ipify.org` в JS, убираются внешние Google Fonts, чинится битый `/vite.svg`, исправляется плейсхолдерный `site.webmanifest`.

| Опция | Описание |
|-------|----------|
| *(по умолчанию)* | Мутация включена — рекомендуется |
| `--no-randomize` | Отключить мутацию (ставить шаблон «как есть», для отладки/репро) |

> ⚠️ **Ограничение:** контент, подгружаемый с иностранных CDN (giphy/unsplash/pexels), вшит в минифицированный бандл — убрать его нельзя без поломки страницы. Самые «тихие» шаблоны — самодостаточные (например, `Convertit`). Мутация ломает совпадение по хешу/заголовкам, но не меняет TLS-отпечаток веб-сервера (см. caveat в разделе «Сравнение Caddy vs Nginx»).

#### 📦 Источник шаблонов

Все шаблоны загружаются из репозитория [sni-templates](https://github.com/SmallPoppa/sni-templates), где содержится полная коллекция AI-генерированных веб-шаблонов с подробными описаниями и превью каждого шаблона. При установке они уникализируются (см. выше).

### Конфигурация Xray Reality

После установки веб-сервера настройте Xray Reality, используя параметры из установки.

#### Nginx с Unix Socket (рекомендуется)

```json
{
    "inbounds": [
        {
            "tag": "VLESS_REALITY_NGINX_SOCKET",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"]
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "xver": 1,
                    "target": "/dev/shm/nginx.sock",
                    "spiderX": "/",
                    "shortIds": [""],
                    "privateKey": "#REPLACE_WITH_YOUR_PRIVATE_KEY",
                    "serverNames": ["reality.example.com"]
                }
            }
        }
    ]
}
```


#### Параметры для замены

| Параметр | Описание |
|----------|----------|
| `target` | `/dev/shm/nginx.sock` (Nginx socket) или `127.0.0.1:9443` (TCP) |
| `xver` | Всегда `1` для proxy_protocol v1 |
| `serverNames` | Ваш домен, указанный при установке |
| `privateKey` | Ваш сгенерированный приватный ключ Reality |
| `shortIds` | Ваши Reality short IDs |

> ⚠️ При добавлении селфстила не забудьте при создании хоста указать принудительно SNI и Host таким же, как у вас указано в `serverNames`.

<img width="438" height="435" alt="изображение" src="https://github.com/user-attachments/assets/57f00a62-1cad-4225-825c-23ed6a779744" />

### ⚠️ Важно: Настройка Unix Socket для Docker

При использовании **Nginx с Unix Socket** и Xray в Docker-контейнере (например, 3x-ui), необходимо обеспечить доступ контейнера к сокету.

#### Проблема
Unix socket создаётся в `/dev/shm/nginx.sock`. Если Xray запущен в Docker-контейнере, он имеет **изолированный** `/dev/shm` и не видит сокет на хосте.

#### Решение
Необходимо пробросить `/dev/shm` в контейнер Xray.

##### Автоматическая настройка (рекомендуется)
При установке скрипт **автоматически обнаруживает** контейнеры `3xui_app`, `xray`, `marzban` и предлагает:
1. **Автоматически исправить** — добавить volume в docker-compose.yml и перезапустить
2. **Показать инструкции** — для ручной настройки
3. **Пропустить** — настроить позже

##### Ручная настройка

Добавьте в `docker-compose.yml` вашего Xray-контейнера:

```yaml
services:
  3xui:  # или xray, marzban и т.д.
    # ... остальные настройки ...
    volumes:
      - /dev/shm:/dev/shm  # ← Добавить эту строку
```

Затем перезапустите контейнер:
```bash
cd /opt/3x-ui  # или путь к вашему docker-compose.yml
docker compose down && docker compose up -d
```

##### Проверка
```bash
## Проверить что сокет существует на хосте
ls -la /dev/shm/nginx.sock

## Проверить что контейнер видит сокет
docker exec 3xui_app ls -la /dev/shm/nginx.sock
```
