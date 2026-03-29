
Требуется rclone и winfsp

rclone скачать тут : https://rclone.org/downloads/
winfsp скачвать тут : https://winfsp.dev/rel/


настройка rclone

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



Команда чтоб запустить диск
rclone mount VKDisk:vk-disk V: --links --vfs-cache-mode full --vfs-cache-max-size 20G --vfs-read-chunk-size 64M --vfs-read-chunk-size-limit 1G --buffer-size 128M --vfs-cache-max-age 24h --transfers 16 --no-console --vfs-cache-poll-interval 15s --dir-cache-time 10s --volname "VK диск" --vfs-disk-space-total-size 100G

Заменить VKDisk:vk-disk на ваши параметры
