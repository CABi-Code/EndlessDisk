
Требуется rclone и winfsp

rclone скачать тут : https://rclone.org/downloads/
winfsp скачвать тут : https://winfsp.dev/rel/


настройка rclone

Переместить содержимое с rclone.exe в папку C:\rclone

Создать переменную среды rclone
	1. Нажать клавишу Win, введите «перемен»
	2. В открывшемся окне нажмите кнопку «Переменные среды...» (Environment Variables) внизу.
	3. В разделе «Переменные пользователя» найдите строку Path и нажмите «Изменить...» (Edit).
	4. В появившемся списке нажмите «Создать» (New) и вставьте путь к папке: C:\rclone.
	5. Нажмите ОК во всех окнах.

Проверить в консоли
	rclone version

Команда чтоб открыть веб-интерфейс
rclone rcd --rc-web-gui
	Нужна вкладка Configs -> Создать новый
	Set up Remote Config
		Name of this drive: VKDisk
		Select : Amazon S3 ....
	Set up Drive
		Choose your S3 provider	: Any other S3 compatible provider
		AWS Access Key ID	: Access Key из панели VK Cloud
		AWS Secret Access Key	: Secret Key из панели VK Cloud
		Endpoint for S3 API	: hb.bizmrg.com

или через консоль:
Storage: Пишите 4 (или s3).
Provider: Ищите в списке Any other S3 compatible provider (обычно это в самом конце, пункт Other).
env_auth: Просто жмите Enter (оставит false).
access_key_id: Вставьте ваш Access Key из панели VK Cloud.
secret_access_key: Вставьте ваш Secret Key.
region: Просто жмите Enter (оставьте пустым).
endpoint: Введите вручную: hb.bizmrg.com
location_constraint: Просто Enter.
acl: Просто Enter.
Edit advanced config? Пишите n (Нет)



Команда чтоб запустить диск
rclone mount VKDisk:vk-disk V: --links --vfs-cache-mode full --vfs-cache-max-size 20G --vfs-read-chunk-size 64M --vfs-read-chunk-size-limit 1G --buffer-size 128M --vfs-cache-max-age 24h --transfers 16 --no-console --vfs-cache-poll-interval 15s --dir-cache-time 10s --volname "VK диск" --vfs-disk-space-total-size 100G

Заменить VKDisk:vk-disk на ваши параметры
