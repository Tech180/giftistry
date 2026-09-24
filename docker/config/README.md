# Config for Compose

```bash
cp config.example.json config.json
```

`config.json` is ignored by git. The api/worker entrypoint chowns `/etc/giftistry` (this directory) so onboarding can save settings. Schema for production DBs is applied by the API on boot ([docs/schema.md](../../docs/schema.md)).
