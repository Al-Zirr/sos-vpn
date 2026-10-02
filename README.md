# sos-vpn

Аварийное развёртывание VPN (VLESS Reality + панель 3x-ui) на чистом сервере одной командой.

## Запуск

Купить любой сервер: **Debian 12 или Ubuntu 22.04/24.04, x86_64, от 1 ГБ памяти**.
Зайти на него по SSH под root и выполнить:

```
bash <(curl -fsSL https://raw.githubusercontent.com/Al-Zirr/sos-vpn/main/sos.sh)
```

Скрипт спросит, для кого разворачивать:

1. **Анонимтус** — по паролю разворачивает копию существующего сервера.
2. **Новый пользователь** — создаёт всё новое: ключи, клиента, панель. Ничего чужого не использует.

Через 1–2 минуты на экране: адрес панели, логин, пароль, ссылка `vless://` и QR-код.
Ссылку вставить в v2rayN (Windows), Hiddify или v2rayNG (Android), Streisand / FoXray (iPhone).
Итог сохраняется в `/root/sos-result.txt` на сервере.

## Что ставится

- nginx на `127.0.0.1:8444` — цель (dest) для Reality, с настоящим или самоподписанным сертификатом;
- 3x-ui v3.8.5 (Xray 26.9.9), панель на порту 2053 по HTTPS;
- VLESS Reality TCP на порту 443, flow `xtls-rprx-vision`;
- ufw (22, 80, 443, 2053), swap 1 ГБ, ограничение памяти для панели.

Дистрибутив панели скачивается с [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui/releases/tag/v3.8.5),
контрольная сумма зашита в скрипт; запасная копия — в релизах этого репозитория.

## Файлы

| Файл | Что это |
|---|---|
| `sos.sh` | скрипт |
| `bundle-lon.enc`, `bundle-buc.enc` | снимки серверов владельца, зашифрованы AES-256 (PBKDF2, 1 000 000 итераций). Без пароля бесполезны |

## Без вопросов

```
SOS_MODE=new bash <(curl -fsSL https://raw.githubusercontent.com/Al-Zirr/sos-vpn/main/sos.sh)
SOS_MODE=owner SOS_PASS=... SOS_SOURCE=lon SOS_DNS=no bash <(curl -fsSL https://raw.githubusercontent.com/Al-Zirr/sos-vpn/main/sos.sh)
```

Если в конце написано **НЕ ПРОШЁЛ ПРОВЕРКУ** или с устройства подключиться не удаётся —
скорее всего, IP сервера заблокирован у вашего провайдера. Возьмите сервер у другого хостера.
