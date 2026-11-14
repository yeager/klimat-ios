# Klimat för iPhone

Klimat är en SwiftUI-app för iOS 17 och senare. Den har svensk kontrollvy, egen appikon, Bonjour-sökning och lokal styrning av kompatibla Daikin-adaptrar. Appen heter Klimat på hemskärmen.

## Bygg

Öppna `KlimatMobile.xcodeproj` i Xcode och bygg schemat `KlimatMobile`. Projektet kan också genereras från `project.yml` med XcodeGen.

## Direktanslutning

Ange Daikin-adapterns IP-adress. När adaptern har stöd för Daikins äldre lokala HTTP-API läser appen aktuell status och skickar ström-, temperatur-, läges- och fläktkommandon direkt över Wi-Fi. Ingen tillverkarinloggning eller molntjänst används för detta.

Vilka Daikin-modeller som fungerar beror på Wi-Fi-adaptern och firmware. Stödet är ännu inte verifierat mot fysisk AC-hårdvara. Bonjour-sökningen hittar endast tjänster som annonseras på nätverket; många AC-adaptrar gör inte det. Övriga lokala protokoll och molnanslutningar är inte inkopplade. Gränssnittet ber inte om eller sparar kontouppgifter för dessa tjänster.

## Kvar före försäljning

Nästa lokala adaptrar att lägga till är Mitsubishi Electric MAC-577IF-2E, Midea/Comfee och Gree. Därefter behövs bredare, protokollspecifik enhetssökning, verifiering på riktig iPhone och AC-hårdvara, signering samt App Store Connect-metadata. För priset 39 kr ska kontoinnehavaren godkänna Apples avtal för betalappar och välja pris i App Store Connect.
