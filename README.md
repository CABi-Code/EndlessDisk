# Монтирование VK Cloud (S3) как сетевого диска в Windows через rclone

Простая и удобная инструкция по подключению хранилища VK Cloud как обычного диска (например, `V:`) в Windows с помощью **rclone** + **WinFsp**.

---

## 🎯 Что даёт этот способ

- Хранилище VK Cloud работает как обычный диск в Проводнике
- Поддержка кэширования, быстрого чтения и записи
- Автоматическое монтирование при старте Windows (можно настроить)
- Полная совместимость с S3 API VK Cloud

---

## ✅ Требования

- Windows 10 / 11 (64-bit)
- [rclone](https://rclone.org/downloads/)
- [WinFsp](https://winfsp.dev/rel/)
- Аккаунт с баккетами (Object Storage) в [VK Cloud](https://msk.cloud.vk.com/app) 

---

## 🚀 Установка

### 1. Установка WinFsp
1. Скачайте последнюю версию с официального сайта: [https://winfsp.dev/rel/](https://winfsp.dev/rel/)
2. Установите как обычную программу.

### 2. Установка rclone

1. Скачайте **rclone** для Windows: [https://rclone.org/downloads/](https://rclone.org/downloads/)
2. Распакуйте архив.
3. Переместите файл `rclone.exe` в папку `C:\rclone`.

### 3. Добавление rclone в PATH

1. Нажмите `Win` → введите «**Переменные среды**» → выберите **«Изменить переменные среды системы»**.
2. Нажмите кнопку **«Переменные среды...»**.
3. В разделе **«Переменные пользователя»** найдите `Path` → нажмите **«Изменить»**.
4. Нажмите **«Создать»** и добавьте путь:  
   `C:\rclone`
5. Нажмите ОК во всех окнах.

Проверьте установку, открыв новую командную строку:

```bash
rclone version
```

---

## 🔧 Настройка подключения к VK Cloud

### Вариант 1: Через веб-интерфейс (рекомендуется)

```bash
rclone rcd --rc-web-gui
```

Откроется браузер. Перейдите во вкладку **Configs → Create new**.

- **Name**: `VKDisk`
- **Type**: `Amazon S3`
- **Provider**: `Any other S3 compatible provider`
- **Access Key ID**: ваш Access Key из панели VK Cloud
- **Secret Access Key**: ваш Secret Key из панели VK Cloud
- **Endpoint**: `hb.bizmrg.com`

Остальные параметры можно оставить по умолчанию.

### Вариант 2: Через консоль

```bash
rclone config
```

Следуйте инструкции:

- `n` → new remote
- `name`: `VKDisk`
- `Storage`: `4` (или `s3`)
- `provider`: `Other` (Any other S3 compatible provider)
- `access_key_id`: ваш Access Key
- `secret_access_key`: ваш Secret Key
- `endpoint`: `hb.bizmrg.com`
- Остальное — Enter (по умолчанию)

---

## ▶️ Монтирование диска

Основная команда для монтирования:

```bash
rclone mount VKDisk:vk-disk V: ^
  --links ^
  --vfs-cache-mode full ^
  --vfs-cache-max-size 20G ^
  --vfs-read-chunk-size 64M ^
  --vfs-read-chunk-size-limit 1G ^
  --buffer-size 128M ^
  --vfs-cache-max-age 24h ^
  --transfers 16 ^
  --vfs-cache-poll-interval 15s ^
  --dir-cache-time 10s ^
  --volname "VK Диск" ^
  --vfs-disk-space-total-size 100G ^
  --no-console
```

**Важно:**
- Замените `VKDisk:vk-disk` на ваше имя remote и название bucket'а
- Можно изменить букву диска (`V:` на любой свободный)

---

## Полезные команды

- **Проверить подключения**: `rclone listremotes`
- **Посмотреть содержимое**: `rclone ls VKDisk:vk-disk`
- **Размонтировать диск**: `rclone unmount V:`
- **Запуск с отображением лога** (для отладки): уберите `--no-console`

---

## Автозагрузка (по желанию)

Можно создать `.bat` файл и добавить его в автозагрузку Windows.

Создайте файл `mount_vkcloud.bat`:

```bat
@echo off
rclone mount VKDisk:vk-disk V: --links --vfs-cache-mode full --vfs-cache-max-size 20G --vfs-read-chunk-size 64M --buffer-size 128M --vfs-cache-max-age 24h --transfers 16 --no-console --vfs-cache-poll-interval 15s --dir-cache-time 10s --volname "VK Диск"
```

---

**Готово!** Теперь у вас есть быстрый сетевой диск на базе VK Cloud.

Если возникнут вопросы — пишите.
