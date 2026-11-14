# Klimat för iPhone

Klimat är en SwiftUI-app för iOS 17 och senare. Den har engelskt gränssnitt samt svenska, spanska, franska, tyska, förenklad kinesiska, hindi, arabiska, brasiliansk portugisiska, japanska, bengali, ryska, indonesiska, turkiska, urdu, marathi, telugu och tamil, egen appikon, sökning efter lokala Daikin-adaptrar, Apple Home-integration och styrning via det lokala nätverket. Appen heter Klimat på hemskärmen.

## Bygg

Öppna `KlimatMobile.xcodeproj` i Xcode och bygg schemat `KlimatMobile`. Projektet kan också genereras från `project.yml` med XcodeGen.

## Direktanslutning

Ange Daikin-adapterns IP-adress. När adaptern har stöd för Daikins äldre lokala HTTP-API läser appen aktuell status och skickar ström-, temperatur-, läges- och fläktkommandon direkt över Wi-Fi. Det fungerar utan internetanslutning, tillverkarinloggning eller molntjänst så länge iPhone och AC är anslutna till samma lokala Wi-Fi-nätverk.

Klimat kan också läsa och styra HomeKit-termostater och värme-/kylreglage som användaren redan har lagt till i Apple Home. Åtkomst begärs först när användaren väljer Apple Home. Enheten måste exponera HomeKits klimatreglage; stöd för alla funktioner varierar mellan tillverkare.

Vilka Daikin-modeller som fungerar beror på Wi-Fi-adaptern och firmware. Stödet är ännu inte verifierat mot fysisk AC-hårdvara. På användarens begäran söker appen i det privata IPv4-subnät som iPhone använder via Wi-Fi. Den testar Daikins lokala HTTP-statusadress och hämtar full status endast från svar som matchar API:t. Subnät större än 512 adresser avböjs. Detta hittar äldre kompatibla Daikin-adaptrar; det är inte en generell sökning efter alla AC-märken. Apple Home stöder redan parade HomeKit-enheter. Övriga lokala protokoll och molnanslutningar är inte inkopplade. Gränssnittet ber inte om eller sparar kontouppgifter för dessa tjänster.

## Kvar före försäljning

Nästa lokala adaptrar att lägga till är Mitsubishi Electric MAC-577IF-2E, Midea/Comfee och Gree. Därefter behövs bredare, protokollspecifik enhetssökning, verifiering på riktig iPhone och AC-hårdvara, signering samt App Store Connect-metadata. För priset 39 kr ska kontoinnehavaren godkänna Apples avtal för betalappar och välja pris i App Store Connect.
