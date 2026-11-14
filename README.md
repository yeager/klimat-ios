# Klimat för iPhone

Klimat är en SwiftUI-app för iOS 17 och senare. Den har engelskt gränssnitt samt svenska, spanska, franska, tyska, förenklad kinesiska, hindi, arabiska, brasiliansk portugisiska, japanska, bengali, ryska, indonesiska, turkiska, urdu, marathi, telugu, tamil, vietnamesiska, koreanska, italienska och persiska, egen appikon, sökning efter lokala Daikin- och Mitsubishi MAC-577-adaptrar, Apple Home-integration och styrning via det lokala nätverket. Appen heter Klimat på hemskärmen.

## Bygg

Öppna `KlimatMobile.xcodeproj` i Xcode och bygg schemat `KlimatMobile`. Projektet kan också genereras från `project.yml` med XcodeGen.

## Direktanslutning

Klimat söker efter kompatibla Daikin-adaptrar och Mitsubishi MAC-577 Wi-Fi-adaptrar på samma privata Wi-Fi-nät som iPhone använder. De kan också läggas till med IP-adress. Daikin-stödet gäller adaptrar med det äldre lokala HTTP-API:t. Mitsubishi-stödet gäller MAC-577-adaptrar med det lokala `/smart`-gränssnittet och använder AES-krypterad trafik. Status, ström, temperatur, läge och fläkt styrs direkt över Wi-Fi utan internet eller moln. Mitsubishi-protokollet är baserat på den MIT-licensierade referensen [pymitsubishi](https://github.com/pymitsubishi/pymitsubishi); se `THIRD_PARTY_NOTICES.md`.

Klimat kan också läsa och styra HomeKit-termostater och värme-/kylreglage som användaren redan har lagt till i Apple Home. Åtkomst begärs först när användaren väljer Apple Home. Enheten måste exponera HomeKits klimatreglage; stöd för alla funktioner varierar mellan tillverkare.

Vilka Daikin- och Mitsubishi-modeller som fungerar beror på Wi-Fi-adaptern och firmware. Stödet för Mitsubishi är ännu inte verifierat mot fysisk AC-hårdvara. Appen söker i det privata IPv4-subnät som iPhone använder via Wi-Fi och hämtar enhetsstatus endast från svar som matchar respektive protokoll. Subnät större än 512 adresser avböjs. Det här är inte en generell sökning efter alla AC-märken. Apple Home stöder redan parade HomeKit-enheter. Övriga lokala protokoll och molnanslutningar är inte inkopplade. Gränssnittet ber inte om eller sparar kontouppgifter för dessa tjänster.

## Kvar före försäljning

Nästa lokala adaptrar att lägga till är Midea/Comfee och Gree. Därefter behövs bredare protokollspecifik sökning, verifiering på riktig iPhone och fysisk AC-hårdvara, signering samt App Store Connect-metadata. För priset 39 kr ska kontoinnehavaren godkänna Apples avtal för betalappar och välja pris i App Store Connect.
