# Atlas 0.4.1 — исправление «Использование данных» и колонки «Сеть» в диспетчере задач

## 1. Что в Windows 10 отвечает за эту вкладку

Вкладка **Параметры → Сеть и Интернет → Состояние → Использование данных** — это UWP-страница Settings, но данные для неё собирает не она сама, а системный конвейер диагностики:

| Компонент | Роль |
|---|---|
| `DusmSvc` («Data Usage») | Служба, которую вызывает страница Settings. Отдаёт данные о расходе трафика, лимиты, «metered network». |
| `DPS` («Diagnostic Policy Service») | Пишет базу **SRUM** — `%windir%\System32\sru\SRUDB.dat` (в Win11 24H2+ — `SRUM.db`). Именно оттуда страница берёт историю по приложениям. |
| `WdiServiceHost`, `WdiSystemHost` | Хосты Windows Diagnostic Infrastructure; через них выполняются диагностические сценарии, в том числе сбор ресурсов/энергии. |
| `Ndu` (`Ndu.sys`, «Network Data Usage Monitoring Driver») | Драйвер, который считает байты по процессам. Его данные использует и SRUM, и колонка **«Сеть»** в диспетчере задач. |
| `SRUM` | База `SRUDB.dat`; если DPS её не обновляет, страница «Использование данных» пустая. |

Ключевой момент: **оба симптома — пустая страница и `0 Мбит/с` у всех процессов — это один и тот же конвейер `Ndu → SRUM → DusmSvc/DPS`**. Поэтому и чинить их нужно вместе.

Отдельно стоит сказать: в 0.4.1 в `atlas\services.yml` уже **нет** прямого отключения `DPS`/`WdiServiceHost`/`WdiSystemHost` (в 0.3.x оно было, и issue #819 закрывали именно его удалением). Поэтому в 0.4.1 под подозрение попадают остальные вещи, которые трогают тот же конвейер: `AllowTelemetry=0` + autologger `DiagTrack`, `DisableDiagnosticTracing`, WDI-политика PerfTrack, удаление telemetry-компонентов, отвязка NDIS-компонентов/отключение Kernel Debug NIC и `lodctr /r`. Мы вырезали весь этот набор.

`DiagTrack` при этом **оставлен отключаемым**, как в оригинальном Atlas: на запись SRUM он не влияет, а его отключение — штатная часть приватности Atlas.

Полезные подтверждения:

- [Atlas issue #819](https://github.com/Atlas-OS/Atlas/issues/819): страницу «Data usage» ломало отключение `DPS`; это признано и починено в [commit `4c59ccb`](https://github.com/Atlas-OS/Atlas/commit/4c59ccb721adc4c30abbc94d35ee26627a5ae3d2) («fix: data usage»), где `DPS` убрали из отключаемых служб.
- [Atlas issue #1016](https://github.com/Atlas-OS/Atlas/issues/1016): «Task Manager network category & Data Usage not working» — та же связка, обсуждение `DPS`/`DusmSvc`/служб.
- [Microsoft Q&A](https://learn.microsoft.com/ru-ru/answers/questions/3843800/question-3843800): колонка «Сеть» в диспетчере задач лечится `sc config ndu start=auto` — подтверждает роль `Ndu`.

## 2. Что именно вырезано

Все правки помечены комментарием `[DataUsage-fix]`, чтобы их было видно в диффе.

Готовый unified diff всех изменений: `data-usage-fix.patch`.

### 2.1. Службы диагностики

`src/playbook/Configuration/atlas/services.yml`

- Закомментировано отключение `diagnosticshub.standardcollector.service` (было `startup: 4`).
- `DiagTrack` **не трогали** — он остаётся отключаемым, как в оригинале (`startup: 4`).

Остальные службы (OneSyncSvc, TrkWks, PcaSvc, WerSvc, wercplsupport, UCPD, GpuEnergyDrv, NetBT, Intel Telemetry) тоже не трогали — они не входят в конвейер SRUM/Ndu. `Telemetry` здесь — это драйвер Intel (`IntelTA.sys`), а не служба телеметрии Windows; `NetBT` — NetBIOS, тоже не влияет на `Ndu`.

### 2.2. Удаление компонентов Windows

`src/playbook/Configuration/atlas/components.yml`

Пакет `Z-Atlas-NoTelemetry-Package` **больше не устанавливается**. Он вырезает `Unified Telemetry Client`, `Application Experience` (inventory), `SettingsHandlers-SIUF` и другие компоненты, от которых зависит диагностический/SRUM-конвейер. Оставлен только `Z-Atlas-NoDefender-Package`.

Для варианта `defender-enable` теперь выполняется только удаление NoDefender-пакета, без установки NoTelemetry.

### 2.3. Задачи в `tweaks.yml`

Закомментированы (файлы оставлены в репозитории, но не запускаются):

| Задача | Почему |
|---|---|
| `tweaks\networking\atlas-network-settings.yml` | Меняет реестр драйвера сетевого адаптера (`SipsEnabled`, `DMACoalescing`, `ApCompatMode` и т.п.) — вмешательство в NDIS-стек, на котором висит `Ndu`. |
| `tweaks\performance\disable-sleep-study.yml` | Отключает диагностические ETW-логи и задачу `Power Efficiency Diagnostics` — тот же WDI/ETW-стек. |
| `tweaks\performance\system\disable-service-host-split.yml` | Ставит `SvcHostSplitDisable=1` всем службам, меняя изоляцию процессов `DPS`, `DusmSvc`, `WdiServiceHost`. |
| `tweaks\privacy\disable-perf-track.yml` | Политика `WdiScenarioExecutionPolicy` — отключение WDI-сценариев. |
| `tweaks\privacy\telemetry\disable-diagnostic-tracing.yml` | `DisableDiagnosticTracing=1` — отключает диагностическую трассировку, которой пользуются SRUM/DPS. |
| `tweaks\privacy\telemetry\disallow-data-collection.yml` | `AllowTelemetry=0`, отключение autologger `Diagtrack-Listener`, удаление ETL-логов. Главный кандидат на пустую страницу и нули в диспетчере. |
| `tweaks\misc\rebuild-perf-counters.yml` | `lodctr /r` дважды + `winmgmt /resyncperf` — может обнулить/сломать счётчики, которыми пользуются диспетчер задач и потребители SRUM. |

### 2.4. Сетевой стек и устройства

`src/playbook/Configuration/tweaks/scripts/script-devices.yml`

- Убран вызов `Disable-NetAdapterBinding -Name "*" -ComponentID ms_msclient, ms_server, ms_lldp, ms_lltdio, ms_rspndr`.

`src/playbook/Executables/DISABLEPNP.ps1`

- Из списка отключаемых PnP-устройств убран `Microsoft Kernel Debug Network Adapter` (сетевой класс; в issue #1016 его включение возвращало колонку «Сеть»).

`src/playbook/Executables/AtlasModules/Scripts/ScriptWrappers/DisableFileSharing.ps1`

- Убран `Disable-NetAdapterBinding` для `ms_msclient, ms_server, ms_lltdio, ms_rspndr`. Остальные действия скрипта (NetBIOS, профиль сети, firewall, пункты меню) сохранены.

## 3. Что оставлено и почему

- `OneSyncSvc`, `TrkWks`, `PcaSvc`, `WerSvc`, `wercplsupport`, `UCPD`, `GpuEnergyDrv`, `NetBT`, Intel `Telemetry` — не участвуют в SRUM/Ndu.
- `DiagTrack` — отключается как в оригинале; на запись SRUM не влияет.
- `disable-ceip`, `disable-input-telemetry`, `disable-app-launch-tracking`, `disable-user-tracking`, `disable-activity-feed`, рекламные ID и т.п. — прикладная телеметрия/приватность, не SRUM.
- `disable-scheduled-tasks` — `PcaPatchDbTask`, `UCPD velocity`, `UsageDataReporting` (Flighting A/B) не пишут в SRUDB.dat.
- `networking\shares\*` — только SMB-параметры, не `Ndu`.
- `appx.yml`, `start.yml`, `CLEANUP.ps1` — не удаляют SRUM/`DusmSvc`/`Ndu`.

## 4. Как проверить после установки

```powershell
Get-Service DPS,WdiServiceHost,WdiSystemHost,DusmSvc,Ndu,DiagTrack |
    Format-Table Name,Status,StartType -AutoSize

Get-Item "$env:windir\System32\sru\SRU*" |
    Select-Object Name,Length,LastWriteTime
```

Ожидаемо: `DPS`, `DusmSvc`, `Ndu` — Running/Automatic. `WdiServiceHost`/`WdiSystemHost` — Manual (могут быть Stopped, это нормально, они стартуют по триггеру). `DiagTrack` — Disabled/Stopped, это ожидаемо и на Data Usage не влияет.

Дальше:

1. Открыть диспетчер задач → «Процессы» → колонка «Сеть». Запустить Speedtest/загрузку — значения должны меняться сразу.
2. Открыть «Параметры → Сеть и Интернет → Состояние → Использование данных». SRUM пишется примерно раз в час, поэтому страница может обновиться не мгновенно; после генерации трафика подождать 5–60 минут или перезагрузиться.
3. Если `SRUDB.dat` не растёт: остановить `DPS`, переименовать/удалить `SRUDB.dat`, запустить `DPS` — база создастся заново.

## 5. Если Atlas уже установлен

Компоненты, удалённые `Z-Atlas-NoTelemetry-Package`, этим плейбуком не возвращаются: DISM/SFC не восстанавливают вырезанные компоненты. Самый чистый путь — чистая установка Windows + этот плейбук.

Если переустановка невозможна, сначала верните компоненты: запустите `%windir%\AtlasDesktop\8. Troubleshooting\Telemetry Components.cmd` и выберите пункт **2) Remove the NoTelemetry package**. Скрипт делает `Remove-WindowsPackage` и возвращает вырезанные компоненты.

После этого верните службы:

```cmd
sc config DPS start= auto
sc config WdiServiceHost start= demand
sc config WdiSystemHost start= demand
sc config DusmSvc start= auto
sc config Ndu start= auto
net start DPS
net start DusmSvc
```

Плюс вернуть сетевые привязки и Kernel Debug NIC:

```powershell
Get-NetAdapterBinding -Name "*" |
    Where-Object ComponentID -in 'ms_msclient','ms_server','ms_lldp','ms_lltdio','ms_rspndr' |
    Enable-NetAdapterBinding
Enable-PnpDevice -FriendlyName "Microsoft Kernel Debug Network Adapter" -Confirm:$false
```

И снять `AllowTelemetry=0` / autologger, если они остались:

```cmd
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f
```

Если после этого `DusmSvc` не стартует из-за отсутствующих файлов — нужен in-place upgrade (запуск `setup.exe` с ISO с сохранением файлов и приложений).

## 6. Компромиссы

- **NoTelemetry-пакет больше не применяется.** Это главная потеря приватности: компоненты телеметрии остаются. Если нужен компромисс, можно позже собрать отдельный CAB без компонентов, связанных с SRUM (`Unified Telemetry Client`, `Application Experience`, `SettingsHandlers-SIUF`), но это требует пересборки через sxsc и тестирования.
- **Уровень телеметрии** на чистой установке останется Windows-дефолтным (не 0).
- **SMB/LLTD-привязки** остаются включёнными; «Disable File Sharing» всё ещё меняет профиль сети, firewall и NetBIOS, но не отвязывает компоненты NDIS.
- **Твики драйвера адаптера** (`SipsEnabled` и др.) больше не применяются — сетевой стек ближе к стоку.

## 7. Список изменённых файлов

| Файл | Что сделано |
|---|---|
| `src/playbook/Configuration/atlas/services.yml` | Убрано отключение `diagnosticshub.standardcollector.service`; `DiagTrack` оставлен как в оригинале. |
| `src/playbook/Configuration/atlas/components.yml` | Не устанавливается `Z-Atlas-NoTelemetry-Package`. |
| `src/playbook/Configuration/tweaks.yml` | Закомментированы 7 задач, влияющих на диагностику/сеть/счётчики. |
| `src/playbook/Configuration/tweaks/scripts/script-devices.yml` | Убран `Disable-NetAdapterBinding`. |
| `src/playbook/Executables/DISABLEPNP.ps1` | Убран Kernel Debug NIC. |
| `src/playbook/Executables/AtlasModules/Scripts/ScriptWrappers/DisableFileSharing.ps1` | Убран `Disable-NetAdapterBinding`. |
| `src/sxsc/Atlas-NoTelemetry.yaml`, `Atlas-NoTelemetry-Arm.yaml` | Добавлено предупреждение, что пакет намеренно не применяется. |