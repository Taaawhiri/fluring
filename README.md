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

## Compilare

```bash
flutter pub get
flutter build apk --release
```

Serve l'Android SDK installato. L'APK si installa sulla TV con:

```bash
adb connect <ip-della-tv>:5555
adb install build/app/outputs/flutter-apk/app-release.apk
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
