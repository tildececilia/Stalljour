# Stalljour 🐴

Webbapp för att schemalägga jourpass i stall — fodringar, utsläpp och insläpp.

- **Boka själv** — veckoschema där alla ser vem som tar vilket pass
- **Grupper** med roterande veckoansvar (var N:e vecka)
- **Rättvis fördelning** — måltal per profil, viktat efter antal hästar, med roterande extrapass
- **Inloggning med mejl-länk** — inga lösenord

## Struktur

| Mapp/fil | Vad |
|---|---|
| `docs/` | Själva appen (statisk HTML/JS/CSS) — serveras via GitHub Pages |
| `db/schema.sql` | Databasstruktur (Supabase/PostgreSQL) |
| `db/auth-migration.sql` | Migrering till mejl-baserat medlemskap |
| `db/security.sql` | Säkerhetsregler (Row Level Security) |
| `dev-server.js` | Lokal utvecklingsserver: `node dev-server.js` → http://localhost:5178 |

Backend: [Supabase](https://supabase.com) (PostgreSQL + Auth). Nyckeln i `docs/config.js` är den publika webbläsar-nyckeln; åtkomst styrs av säkerhetsreglerna i databasen.
