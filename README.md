# HAG Technik – Einrichtung

Die App besteht aus einer Seite (GitHub Pages) und einer Datenbank mit Login (Supabase). Jede Person bekommt ein eigenes Konto.

## 1. Supabase
1. Auf supabase.com ein neues Projekt anlegen (empfohlen: ein eigenes, nicht das der anderen App, weil Konten und Admin-Regel sonst geteilt werden).
2. Im Dashboard links **SQL Editor** öffnen, den kompletten Inhalt von `schema.sql` einfügen und **Run** drücken. Nur einmal ausführen. (Der Orga-Bereich ist darin schon enthalten. Falls `schema.sql` bei dir schon in einer älteren Fassung gelaufen ist, führe stattdessen nacheinander `update_orga.sql`, `update_features.sql`, `update_groups_notes.sql` und `update_access_food.sql` aus. Alle vier dürfen mehrfach laufen.)
3. **Project Settings > API**: *Project URL* und *anon public key* kopieren.
4. **Authentication > Providers > Email**: Optional „Confirm email" ausschalten, dann können sich alle ohne E-Mail-Bestätigung sofort anmelden.

## 2. Zugangsdaten eintragen
In `index.html` oben im Block `window.HAG_CONFIG` die URL und den anon key einsetzen. Der anon key ist öffentlich gedacht. Geschützt sind die Daten durch die Regeln aus `schema.sql`.

## 3. GitHub Pages
1. Neues Repository anlegen und alle Dateien dieses Ordners hochladen (`index.html`, `logo.png`, `manifest.webmanifest`, `sw.js`, `icon-192.png`, `icon-512.png`; die `.sql`-Dateien und `README.md` dürfen auch dabei sein).
2. **Settings > Pages**: Source „Deploy from a branch", Branch `main`, Ordner `/ (root)`, speichern.
3. Nach ungefähr einer Minute ist die App unter `https://<name>.github.io/<repo>/` erreichbar.
4. In Supabase unter **Authentication > URL Configuration** diese Adresse als *Site URL* eintragen, damit Links in E-Mails (Bestätigung, Passwort zurücksetzen) richtig ankommen.

## 4. Erster Start
- Wer sich **zuerst** registriert, wird automatisch Admin. Das solltest du sein.
- Lege **sofort** im Reiter **Konto** das **Zugangs-Passwort** fest. Ohne das kann sich niemand sonst registrieren, mit dem Passwort kommen nur die hinein, die es von dir bekommen.
- Im Reiter **Konto** legst du außerdem den Admin-Code fest. Wer ihn eingibt, wird Admin. Admins können außerdem im Team-Bereich andere zu Admins machen.
- Admins pflegen die Technikliste und dürfen fremde Termine ändern. Alle anderen tragen eigene Termine ein und melden sich an und ab.

## Miettechnik, Vorbereitung, Personenbedarf
- **Miettechnik:** Bei der Technik gibt es den Schalter „Mietbar (gehört nicht der Schule)" mit einem Feld für den Vermieter. Mietbare Technik steht in einer eigenen Gruppe und ist grün markiert, auch in der Auswahl beim Termin.
- **Event und Vorbereitung:** Jeder Termin ist entweder ein Event oder eine Vorbereitung, zum Beispiel „Technik abholen" oder „Aufbau". Eine Vorbereitung gehört zu einem Event, hat eigene Zeiten und eigene Anmeldungen und erscheint gestrichelt in der Farbe ihres Events. Im Event steht die Liste seiner Vorbereitungen mit dem Knopf „+ Vorbereitung".
- **Personenbedarf:** Pro Termin „Mindestens benötigt" (es können sich trotzdem mehr eintragen) oder „Maximal eingeplant". Ist das Maximum erreicht, landen alle weiteren auf der Backup-Liste. Die Reihenfolge richtet sich danach, wer zuerst zugesagt hat. Sagt jemand ab, rückt die nächste Person automatisch nach. Autos von Backup-Personen zählen erst, wenn sie nachgerückt sind.

## Zugangs-Passwort für neue Mitglieder
Damit über den Link nicht irgendwer ins Team kommt, braucht jede neue Person beim Konto-Erstellen ein **Zugangs-Passwort**. Das legt ein Admin in der App unter **Konto** fest und gibt es nur an das Team weiter. Es wird auch in der Datenbank geprüft, nicht nur in der Oberfläche. Nur das allererste Konto (du, es wird automatisch Admin) braucht keins. **Lege das Zugangs-Passwort direkt nach deiner eigenen Registrierung fest.** Solange keins gesetzt ist, kann sich niemand Neues registrieren. Ein neues Passwort ersetzt das alte, bestehende Konten bleiben.

## Verpflegung
Bei jedem Event gibt es die Felder „Was gibt es zu essen?“ und „Wer bezahlt?“. Sie stehen im Detail des Termins. Eintragen und ändern können sie der Ersteller und Admins.

## Termine und Aufgaben bearbeiten
Events und Vorbereitungen dürfen nur Admins und der Ersteller bearbeiten oder löschen. Das wird auch in der Datenbank erzwungen. Im Kalender haben Vorbereitungen die Farbe ihres Events, sind aber gestrichelt und ohne Füllung. Events sind kräftig mit Balken.

## Notizen
Im Reiter **Notizen** schreibt jeder schnell auf, was ihm aufgefallen ist. Jede Person hat eine eigene Farbe, bei jeder Notiz steht die Uhrzeit, und die Notizen sind nach Tagen gruppiert. Filtern geht nach Zeit (Heute, 7 Tage, 30 Tage, Alle), nach Person, nach Thema und per Suchfeld. Die Themen erkennt die App selbst: Wörter, die in mindestens zwei Notizen vorkommen (zum Beispiel Akku oder Beamer), werden zu Chips. Mit einem Hashtag wie `#Reparatur` legst du ein Thema selbst fest. Der Verfasser hat bei seinen Notizen ein Häkchen zum Löschen und kann das direkt danach rückgängig machen. Admins können jede Notiz löschen.

## Gruppen
Unter **Konto** legen Admins Gruppen an, benennen sie um und ordnen Teammitglieder zu (eine Person kann in mehreren Gruppen sein). Beim Eintragen eines Termins oder einer Vorbereitung wählst du unter „Wer wird angesprochen?“, für wen er gilt. Ohne Auswahl gilt er für alle. Das Häkchen „Bei neuen Terminen standardmäßig ansprechen“ legt fest, welche Gruppen dort schon vorausgewählt sind. So kann zum Beispiel eine Gruppe nur bei Bedarf dazukommen.

Wer nicht angesprochen ist, sieht den Termin weiterhin (gedämpft mit „Nicht für dich“), bekommt kein rotes Ausrufezeichen und kann sich nicht eintragen. Das wird auch in der Datenbank durchgesetzt. Auf der Startseite blendet der Schalter „Für mich“ fremde Termine aus. Der Orga-Bereich bleibt allein den Admins vorbehalten.

## Orga-Bereich (nur Admins)
Der Orga-Bereich hat zwei Reiter: **Aktuell** (offene Aufgaben als Liste oder Kalender) und **Bisherige** (erledigte Aufgaben, nach Jahr sortiert, als Archiv für die nächsten Male). Über das Auswahlfeld „Alle Events und Themen“ siehst du alles zu einem Event, zum Beispiel „Halloweenparty“: die offenen Aufgaben, die erledigten aus den Jahren davor und die Vorbereitungen aus dem Kalender. Jede Aufgabe hat ein Feld „Thema oder Event“. Es wird vom verknüpften Termin übernommen und bleibt erhalten, auch wenn der Termin später gelöscht wird. Mit „jedes Jahr wiederholen“ kommt das Thema in die nächste Runde mit. Aufgaben mit Eventbezug haben im Orga-Kalender die Farbe ihres Events. Hast du ein Event gewählt, kannst du zusätzlich das Jahr auswählen. Erledigte Aufgaben haben einen grünen Haken statt Durchstreichen, und mit „In den Kalender kopieren“ legst du sie als neue offene Aufgabe mit demselben Datum wieder an (zum Beispiel als Vorlage für dieses Jahr).

## Auf den Homebildschirm
- **iPhone (Safari):** Teilen-Symbol, dann „Zum Home-Bildschirm".
- **Android (Chrome):** Menü mit den drei Punkten, dann „App installieren" oder „Zum Startbildschirm hinzufügen".

## Logo austauschen
Das HAG-Technik-Logo ist schon eingebaut: `logo.png` (Kopfzeile und Anmeldung) sowie `icon-192.png` und `icon-512.png` (Homebildschirm). Zum Austauschen die Dateien durch eigene PNGs ersetzen, die Icons quadratisch.
