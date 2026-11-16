# Submissions: pictures and data people send from the app

People open **Settings → Help complete the catalog** in the app. It lists every catalog entry that's missing
something (a picture, a release date, a price, a card's power ...), from `data/_wanted.json`, which the packager
publishes with every package. They pick an entry, fill in what they know (each field is checked by type), add a
picture if one is missing, optionally say how they want to be credited, and send. **Send something else** is the
free-form way: a picture of any part, blader, box or accessory, or something not in the catalog.

Everything comes here with their username. Pictures go into a Drive folder; each picture and each typed-in value is
a row in a Google Sheet. Nothing reaches the app until you decide: you review them in Clasher Studio
(**Data → Submissions**). **Apply** puts the picture or the value on the right row of the open workbook and adds the
credit to that row's `credits` column, which the app shows on the part's page. **Reject** keeps it out.

```
packager --> data/_wanted.json (CDN) --> app: Help complete the catalog
                                              |  POST (values + optional picture)
                                              v
                             Apps Script web app (Code.gs) --> Sheet "Submissions" + Drive folder
                                              ^
Clasher Studio (Data -> Submissions) ---------+  list / picture / mark applied or rejected (admin key)
```

## Set it up (once, about 5 minutes)

1. Create a Google Sheet, e.g. "Clasher submissions".
2. In it, open **Extensions → Apps Script**. Replace `Code.gs` with this folder's `Code.gs`.
3. Optional, to match the scopes: **Project settings → Show "appsscript.json"**, then paste this folder's
   `appsscript.json`.
4. Select `setup` in the function list and click **Run**. Allow the access it asks for (your spreadsheet and your
   Drive). The log prints:
   * `ADMIN_KEY`: for Clasher Studio;
   * `SUBMIT_KEY`: for the app;
   * the link to the new "Clasher submissions" Drive folder.

   It also creates the "Submissions" sheet. The keys are kept in **Project settings → Script properties**.
5. **Deploy → New deployment**, type **Web app**: Execute as **Me**, Who has access **Anyone**. Copy the
   **Web app URL** (it ends in `/exec`).
6. App: build with the URL, the submit key and where the list of what's missing is, then show the settings entry:
   ```bash
   flutter run --dart-define=CONTRIBUTIONS_URL=https://script.google.com/macros/s/XXXX/exec --dart-define=CONTRIBUTIONS_KEY=<SUBMIT_KEY> --dart-define=CONTRIBUTIONS_WANTED_URL=https://cdn.jsdelivr.net/gh/<owner>/<repo>@main/data/_wanted.json
   ```
   Without `CONTRIBUTIONS_WANTED_URL` the page says the list isn't set up and offers only "Send something else".
   See `app_features/README.md` for the three lines to add to the app.
7. Clasher Studio: **Settings → Publishing**, "Submissions web app URL" (the `/exec` URL) and "Submissions admin
   key" (`ADMIN_KEY`). Then **Data → the inbox button (Submissions)**.

After you change `Code.gs`, use **Deploy → Manage deployments → Edit → New version**. That keeps the same URL.

## What's stored

One row per picture, and one row per typed-in value, in "Submissions". Everything sent at once shares a `batch`:

| column | |
|---|---|
| `id` | the submission id (also the start of the picture's file name) |
| `submittedAt`, `status` | when, and `new` / `applied` / `rejected` |
| `kind` | `image` (the main picture, or a blader's portrait), `fullBodyImage` (a blader), `other`, or `value` (a typed-in field) |
| `targetType`, `targetId`, `targetName` | what it's of: the catalog key (`blades`, `lockChips`, `products`, `bladers`, `tcgCards` ...), its id and name; `other` + the note for something not in the catalog |
| `field`, `value` | for `value` rows: the column (e.g. `releaseDate`) and what was typed |
| `username`, `userId` | who sent it (from their sign-in) |
| `credit` | how they want to be credited; their username when they left it empty |
| `note` | anything they added |
| `fileId`, `fileName`, `mimeType`, `bytes` | the picture in the Drive folder |
| `appVersion`, `platform` | the app that sent it |
| `batch` | shared by the rows sent together |
| `reviewedAt`, `reviewNote` | set by Studio (e.g. `Parts_X_Blades #203`) |

Pictures stay private in your Drive; nothing is shared by link. Studio downloads them with the admin key.

## Safeguards in the script
* **Rejected before anything is saved:**
  * a missing username, or an unknown kind or target;
  * no target id (or, for "something else", no note);
  * no consent;
  * neither a picture nor a value; more than 20 values; a value over 300 characters;
  * a value for a column that's never asked for (ids, names, codes, `credits`, `model3d` ...);
  * a full-body picture for something that isn't a blader;
  * anything that isn't a JPEG, PNG or WebP (checked by its first bytes, not its name);
  * pictures over 6 MB (the app sends about 1600 px JPEGs, a few hundred KB).
* **Limits:** each person can send `MAX_PER_HOUR` pictures an hour (20 by default; change it in Script properties).
* **Keys:**
  * `SUBMIT_KEY` keeps random scripts out. It ships inside the app, so it's a speed bump, not a secret.
  * `ADMIN_KEY` is needed to read or change anything; never put it in the app.
* **Sheet safety:**
  * text that Sheets would run as a formula (`=...`, `+...`) is stored as plain text;
  * rows are written under a lock, so two people sending at the same moment can't collide.

## Try it without deploying
`node submissions/test/local_server.js` runs `Code.gs` locally and answers the way Apps Script does (a POST, then
a 302 to the answer). Point the app or Studio at `http://127.0.0.1:8765/exec`, with submit key `sk` and admin key
`admin`. For the list of what's missing, serve a packaged `data/` folder (e.g. `python3 -m http.server 8000` in it)
and use `CONTRIBUTIONS_WANTED_URL=http://127.0.0.1:8000/_wanted.json`. Only `http://127.0.0.1` / `localhost` are accepted over plain http.

## Tests
* `node --test submissions/test/code.test.js`: the script against stand-ins for Sheets, Drive, Cache and Lock
  (11 tests).
* End to end, over real HTTP: start the local server, then run `app_features/test/contributions_e2e_test.dart`
  (with `CONTRIBUTIONS_E2E_URL`; sends pictures and a batch of values) and
  `clasher_st_missing_data/test/features/submissions_e2e_test.dart` (with `SUBMISSIONS_E2E_URL`; reads them back).

## The list of what's missing (`data/_wanted.json`)
`wanted.py` writes it every time `beyblade_data.py` packages. It's served from the CDN next to the other JSON and
is left out of `catalog.zip`, so the app's catalog never changes because of it. Per catalog row with gaps it lists
the missing fields and pictures; per sheet it describes each field: `type` (`number`, `date`, `choice`, `text`,
`image`), `label`, `unit`, `hint` and `choices`. The rules for what counts as missing are the missing data tool's
(optional columns and profiles are skipped). Ids, names, codes, bookkeeping columns, `credits`, `model3d` and
flags are never asked for.
