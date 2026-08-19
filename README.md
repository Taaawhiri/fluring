# Fluring

Un client Flutter per Android TV che mostra le telecamere Ring: griglia di
anteprime navigabile col telecomando, live view a schermo intero premendo OK.

## Come funziona

Ring non pubblica API per sviluppatori. L'app usa gli stessi endpoint privati
dell'app ufficiale Android — gli stessi su cui si basano Home Assistant e
`ring-mqtt`. Funziona bene, ma **Amazon può cambiarli senza preavviso**: è un
progetto per uso personale, non qualcosa da pubblicare come prodotto.

Le telecamere Ring sono cloud-only: non espongono RTSP o ONVIF sulla rete
locale. Per questo l'app parla direttamente coi server Ring e non richiede
nessun bridge, Raspberry Pi o dispositivo sempre acceso in casa.

### Due scelte di progetto

**Anteprime come vista principale, live on-demand.** La griglia mostra gli
snapshot JPEG (endpoint semplice e robusto) aggiornati ogni 30 secondi. Il
WebRTC — la parte fragile, specie su chip TV economici — parte solo quando si
apre una camera. Se lo streaming ha problemi, la griglia resta comunque utile.

**Refresh token persistente.** Email, password e codice 2FA si inseriscono una
volta sola; il refresh token viene salvato in `flutter_secure_storage` e
rinnovato in automatico. Anche l'hardware id è persistente: se cambiasse a ogni
avvio, Ring vedrebbe un nuovo dispositivo e richiederebbe di nuovo il 2FA.

L'intervallo di 30 secondi fra gli snapshot è volutamente lento: Ring applica
rate limit, e una camera a batteria interrogata di continuo si scarica in pochi
giorni.

## Struttura

```
lib/src/ring/     client Ring: auth OAuth, device list, snapshot, WebRTC
lib/src/ui/       schermate: login, griglia, live view, focus D-pad
```

## Installare

L'APK viene compilato da GitHub Actions e pubblicato nelle
[Releases](../../releases): non serve avere l'Android SDK in locale.

Per pubblicare una nuova versione, dalla tab *Actions → Release APK → Run
workflow*, indicando la versione (es. `v0.1.0`): il workflow crea da sé il tag e
la release. In alternativa, da riga di comando:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Il workflow compila, esegue analisi e test, e allega l'APK alla release. Ogni
push su qualsiasi branch fa comunque una build di verifica, il cui APK resta
scaricabile fra gli artifact del run.

Poi si scarica l'APK dalla release e lo si installa sulla TV:

```bash
adb connect <ip-della-tv>:5555
adb install fluring-v0.1.0.apk
```

Sulla TV va prima abilitato il debug ADB in *Impostazioni → Opzioni sviluppatore*.

### Chiave di firma

Senza segreti configurati il workflow firma con le chiavi di debug: l'APK si
installa, ma essendo rigenerate a ogni run **non potrà aggiornare
un'installazione precedente** — andrebbe disinstallato e reinstallato, perdendo
la sessione Ring salvata.

Per una chiave stabile, generala una volta:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias fluring
base64 -w0 release.jks
```

e aggiungi in *Settings → Secrets and variables → Actions* del repository:

| Secret | Valore |
| --- | --- |
| `KEYSTORE_BASE64` | l'output del comando `base64` |
| `KEYSTORE_PASSWORD` | la password del keystore |
| `KEY_ALIAS` | `fluring` |
| `KEY_PASSWORD` | la password della chiave |

Conserva `release.jks`: perdendolo non potrai più pubblicare aggiornamenti
installabili sopra quelli già distribuiti.

### Compilare in locale

```bash
flutter pub get
flutter build apk --release
```

## Navigazione col telecomando

Non c'è touch: tutto passa dal D-pad. `TvFocusable` (in `lib/src/ui/focusable.dart`)
gestisce il focus visibile — bordo colorato e leggero ingrandimento, dimensionati
per essere letti da diversi metri. Accetta come "conferma" i tasti `select`,
`enter`, `space` e il pulsante A dei controller, perché i telecomandi Android TV
mandano codici diversi a seconda del produttore.

Il padding di `tvSafeArea` tiene i contenuti dentro l'area sicura: molte TV
tagliano i bordi dell'immagine.

## Stato

Analisi statica pulita e test del parsing dei modelli passanti. **Non è ancora
stato provato su un dispositivo reale né contro un account Ring vero**: il login,
gli snapshot e soprattutto la negoziazione WebRTC vanno verificati sulla TV.
