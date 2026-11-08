# Familien-Wichteln · Amigo Secreto

Einfache zweisprachige (Deutsch/Spanisch) Wichtel-Seite für die Familie.

- `index.html` – die komplette Seite (statisch, ohne Build)
- `supabase/schema.sql` – Datenbank (Supabase-Projekt `wichteln`)

## So funktioniert es
- **Organisatorin** öffnet `…/#a=<admin-link>`: Teilnehmer, Gruppen, Ausschlüsse, Auslosung.
- **Teilnehmer** öffnen ihren persönlichen Link `…/#p=<token>` – keine Anmeldung, kein Passwort.
- **Selbst eintragen** über den Familien-Link `…/#j=<code>`.
- Personen in derselben **Gruppe** (Paare, „Kolumbien“) ziehen sich nicht gegenseitig.
  Zusätzliche Ausschlüsse gelten immer in beide Richtungen.
- Die Auslosung passiert auf dem Server; niemand – auch die Organisatorin nicht – sieht die Zuteilung.
