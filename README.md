# WhatsApp Proxy — Interactive Setup Script

Интерактивный bash-скрипт для быстрой установки [WhatsApp Proxy](https://github.com/WhatsApp/proxy) на VPS. Ведёт пошагово, задаёт все нужные вопросы и настраивает всё автоматически.

## Быстрый старт

Подключитесь к вашему VPS и выполните:

```bash
curl -sL https://raw.githubusercontent.com/medvedicos/WhatsApp-Proxy/main/setup-whatsapp-proxy.sh | sudo bash
```

## Что делает скрипт

Проведёт через 7 шагов:

| Шаг | Что происходит |
|-----|----------------|
| 1 | Проверка системы — ОС, пакетный менеджер, публичный IP |
| 2 | Установка Docker и Docker Compose (если не установлены) |
| 3 | Выбор метода установки: готовый образ DockerHub или сборка из исходников |
| 4 | Настройка портов (минимальный / стандартный / полный / свой набор) |
| 5 | Открытие портов в файрволе (UFW / firewalld / iptables) |
| 6 | Выбор режима запуска: systemd-сервис / Docker Compose / docker run |
| 7 | Итог: адрес для подключения и полезные команды |

## Требования

- Ubuntu / Debian / CentOS / любой Linux с bash
- Минимум 512 MB RAM
- Открытые порты на стороне VPS провайдера

## Порты

| Порт | Назначение |
|------|-----------|
| 443  | HTTPS (основной, рекомендуется) |
| 80   | HTTP |
| 5222 | XMPP / Jabber (WhatsApp default) |
| 587  | Медиафайлы (whatsapp.net) |
| 7777 | Медиафайлы (whatsapp.net) |
| 8199 | Страница статистики HAProxy |
| 8080 / 8443 / 8222 | PROXY protocol (для балансировщиков нагрузки) |

> Для обхода блокировок достаточно открыть только **443** и **587**.

## Как подключиться из WhatsApp

1. Откройте **WhatsApp → Настройки → Хранилище и данные → Прокси**
2. Включите **Использовать прокси**
3. Введите IP-адрес вашего сервера
4. Нажмите **Сохранить**

## Полезные команды после установки

```bash
# Статус контейнера
docker ps

# Логи
docker logs whatsapp_proxy

# Перезапуск (systemd)
systemctl restart whatsapp-proxy

# Страница статистики HAProxy
http://<ваш-ip>:8199
```

## Основано на

[github.com/WhatsApp/proxy](https://github.com/WhatsApp/proxy) — официальный репозиторий Meta / WhatsApp.
