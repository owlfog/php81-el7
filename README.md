# PHP 8.1 RPM для CentOS 7

[![Build RPM and publish yum repo](https://github.com/owlfog/php81-el7/actions/workflows/pages.yml/badge.svg?branch=main)](https://github.com/owlfog/php81-el7/actions/workflows/pages.yml)

Сборка PHP `8.1.34-7.el7.rhcustom` для EL7 x86_64 на основе Remi SCL.
Используется официальный SRPM `php81-php-8.1.34-6.remi.src.rpm` с бэкпортами
security-исправлений, включая `CVE-2026-109618` и `CVE-2026-109619`.
Release 7 добавляет определение TLS-констант по заголовкам libcurl, учитывая
бэкпорты EL7 без изменения upstream-номера версии библиотеки.

Сохраняются имена RPM `php81-php-*`, пути `/opt/remi/php81`,
`/etc/opt/remi/php81` и unit `php81-php-fpm`. Конфиги используют
`%config(noreplace)`.

## Быстрый старт

Нужны Docker, Make, доступ к архивным репозиториям и место для сборки.
Docker используется для сборки и тестирования; PHP устанавливается из RPM.

```bash
make rpm JOBS=2
make smoke
make repo
```

Все три шага:

```bash
make all
```

Другой release:

```bash
make rpm RELEASE=7 JOBS=4
```

Результаты:

- `dist/rpms/` — бинарные RPM;
- `dist/srpms/` — исходный RPM;
- `dist/SHA256SUMS` — контрольные суммы;
- `dist/repo/el7/x86_64/` — yum-репозиторий;
- `build/build.log` — компиляция и regression tests;
- `public/` — файлы для GitHub Pages после `make pages`.

## Что внутри

- `docker/Dockerfile.el7` — builder CentOS 7.9 с зависимостями из архивов.
- `docker/el7.repo` — репозитории CentOS, EPEL, Remi и Oracle.
- `packaging/SPECS/php.spec.in` — адаптированный SPEC Remi.
- `packaging/SOURCES/` — исходные патчи, конфиги и публичные ключи.
- `packaging/patches/` — изменения для совместимости и тестов EL7.
- `scripts/build-rpm.sh` — проверка исходников и `rpmbuild`.
- `scripts/smoke-test-rpm.sh` — проверка обновления в отдельном контейнере.
- `scripts/test-curl-tls.sh` — локальный HTTPS/TLS 1.2 тест.
- `scripts/sign-rpms.sh`, `scripts/sign-repo.sh` — подпись RPM и metadata.
- `scripts/create-repo.sh`, `scripts/build-pages.sh` — подготовка yum и Pages.

Сборка включает OCI8/PDO_OCI с Oracle Instant Client 21.16. Расширения
сохраняют PHP/Zend API исходной ветки. Необязательные пакеты устанавливаются
по потребности; весь набор `dist/rpms/*.rpm` устанавливать не требуется.

## Проверки

Архив PHP проверяется по SHA256 и PGP-подписи; файлы из исходного SRPM — по
`packaging/SHA256SUMS`. SPEC применяет security-патчи, проверяет API/ABI и
запускает regression tests. Неожиданные ошибки обязательных тестов прерывают
сборку.

`make smoke` проверяет обновление с предыдущего Remi PHP, совместимость
расширений, сохранение настроек, работу CLI/FPM и замену worker после OOM.
Дополнительно сверяются константы curl и выполняется локальный HTTPS-запрос
по TLS 1.2 с проверкой сертификата и имени сервера.

Проверки используют контейнерные фикстуры. Совместимость конкретного
приложения и его внешних интеграций проверяется отдельно.

## Подпись RPM и yum-репозитория

Нужен RSA-ключ подписи, совместимый с RPM/GnuPG EL7. Закрытый ключ хранится
вне Git и передаётся через `RPM_GPG_PRIVATE_KEY_B64` либо
`RPM_GPG_PRIVATE_KEY_FILE`, доступный внутри контейнера.

```bash
export RPM_GPG_NAME='Rosa Khutor RPM Signing'
make sign-rpms
make repo
make sign-repo
make pages PAGES_BASE_URL=https://owlfog.github.io/php81-el7
```

RPM подписываются до создания metadata: подпись меняет checksum пакета.
Публичный ключ записывается в `dist/RPM-GPG-KEY-rosa-khutor`.
Для ключа с passphrase требуется настроенный механизм неинтерактивной подписи;
текущий workflow автоматически его не настраивает.

## GitHub Actions и Pages

Workflow запускается вручную через `workflow_dispatch`. Push сам по себе
не публикует пакеты. Workflow собирает RPM, запускает smoke, подписывает
пакеты и metadata, затем публикует `public/` в Pages.

Настройки репозитория:

- Pages → Source: `GitHub Actions`;
- secret `RPM_GPG_PRIVATE_KEY_B64` — закрытый ключ в base64;
- variable `RPM_GPG_NAME` — fingerprint или имя ключа;
- variable `PAGES_BASE_URL` — адрес Pages, если отличается от стандартного.

Для стандартного project Pages используются адреса:

- [yum-репозиторий](https://owlfog.github.io/php81-el7/);
- [rosa-php81-el7.repo](https://owlfog.github.io/php81-el7/rosa-php81-el7.repo);
- [публичный GPG-ключ](https://owlfog.github.io/php81-el7/RPM-GPG-KEY-rosa-khutor).

Эти адреса становятся доступны после настройки Pages и успешной публикации.

## Установка и обновление

Перед импортом сверить fingerprint ключа через доверенный канал.

```bash
sudo rpm --import https://owlfog.github.io/php81-el7/RPM-GPG-KEY-rosa-khutor
sudo curl -fsSL \
  -o /etc/yum.repos.d/rosa-php81-el7.repo \
  https://owlfog.github.io/php81-el7/rosa-php81-el7.repo
sudo yum --disablerepo='*' --enablerepo=rosa-php81-el7 makecache
```

Первый `makecache` может запросить подтверждение ключа для metadata.
Не использовать здесь `--assumeno`: он отклоняет и импорт ключа.
Конфигурация репозитория включает `gpgcheck=1`, `repo_gpgcheck=1` и HTTPS.

Установка CLI/FPM:

```bash
sudo yum --disablerepo='*' --enablerepo=rosa-php81-el7 install php81-php-cli php81-php-fpm
```

Если отсутствуют внешние зависимости, их устанавливают из проверенных
репозиториев дистрибутива и Remi. План транзакции нужно проверять до установки.

Просмотр обновления уже установленных PHP-пакетов:

```bash
sudo yum --disablerepo='*' --enablerepo=rosa-php81-el7 --assumeno update 'php81-php*'
```

После проверки плана выполнить команду без `--assumeno` в окно обслуживания.
Сначала сохранить конфиги и точные версии заменяемых RPM для отката.
Проверить `.rpmnew`, затем конфигурацию и модули:

```bash
/opt/remi/php81/root/usr/bin/php -v
/opt/remi/php81/root/usr/bin/php -m
/opt/remi/php81/root/usr/sbin/php-fpm -t
```

Перезапуск FPM и долгоживущих PHP workers выполняется по правилам приложения.
RPM scriptlets также могут перезапустить FPM во время установки.
Для отката используют сохранённые старые RPM всей заменяемой группы,
предварительно проверив `yum --assumeno downgrade /path/to/rollback/*.rpm`.

## Ограничения

PHP 8.1 и CentOS 7 завершили поддержку. Эти RPM не возобновляют upstream
поддержку; переход на поддерживаемые версии планируется отдельно.

EOL security-патч принудительно отключает session upload progress независимо
от INI. При OOM процесс завершается без обычного PHP cleanup и shutdown
callbacks. FPM создаёт замену worker; для CLI следует проверить autorestart
и корректность повторной обработки незавершённых заданий.
