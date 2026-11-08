# Familien-Wichteln · Amigo Secreto

Einfache zweisprachige (Deutsch/Spanisch) Wichtel-Seite für die Familie.

- `index.html` – die komplette Seite (statisch, ohne Build)
- `supabase/schema.sql` – Datenbank (Supabase-Projekt `wichteln`)

## So funktioniert es
- **Organisatorin** öffnet `…/#a=<admin-link>`: Teilnehmer, Gruppen, Ausschlüsse, Auslosung.
- **Teilnehmer** öffnen ihren persönlichen Link `…/#p=<token>` – keine Anmeldung, kein Passwort.
- **Ein Link für alle** `…/#j=<code>`: Jeder tippt auf seinen Namen; danach ist der Name gesperrt.
  Die Organisatorin kann einen Namen mit 🔓 wieder freigeben. Wer fehlt, kann sich dort neu eintragen.
- Personen in derselben **Gruppe** (Paare, „Kolumbien“) ziehen sich nicht gegenseitig.
  Zusätzliche Ausschlüsse gelten immer in beide Richtungen.
- Die Auslosung passiert auf dem Server; niemand – auch die Organisatorin nicht – sieht die Zuteilung.
