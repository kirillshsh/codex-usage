# Codex CLI Usage Tracker

Локальный трекер использования для Codex CLI. Собирает метрики из `~/.codex/sessions` и пишет snapshot JSON, который можно читать из menu bar приложения.

## Что собирается

- Окно `5h` (`session_window`)
- Окно `7d` (`weekly_window`)
- Rolling totals: `24h`, `30d`, `all-time`
- Последний `rate_limits` (если есть в событиях)
- Топ сессий и активная сессия

## Быстрый старт

```bash
python3 codex_usage_tracker/codex_usage_tracker.py report
```

```bash
python3 codex_usage_tracker/codex_usage_tracker.py snapshot \
  --output ~/.codex/usage_tracker/latest_snapshot.json
```

## Автозапуск через launchd

```bash
python3 codex_usage_tracker/codex_usage_tracker.py install-autostart --interval 180
```

Проверка:

```bash
python3 codex_usage_tracker/codex_usage_tracker.py autostart-status
```

Удаление:

```bash
python3 codex_usage_tracker/codex_usage_tracker.py uninstall-autostart
```

## Конфиг (опционально)

Файл: `~/.codex/usage_tracker/config.json`

```json
{
  "session_window_minutes": 300,
  "week_window_minutes": 10080,
  "session_limit_tokens": 500000,
  "week_limit_tokens": 8000000
}
```

Если лимиты заданы, трекер сможет вычислять `used_percent`, когда `rate_limits` недоступны.
