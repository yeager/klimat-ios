# Klimat för iPhone

Klimat är en SwiftUI-app för iOS 17 och senare. Den har engelskt gränssnitt samt svenska, spanska, franska, tyska, förenklad kinesiska, hindi, arabiska, brasiliansk portugisiska, japanska, bengali, ryska, indonesiska, turkiska, urdu, marathi, telugu, tamil, vietnamesiska, koreanska, italienska och persiska, egen appikon, sökning efter lokala Daikin-, Mitsubishi- och Gree-adaptrar, Apple Home-integration och styrning via det lokala nätverket. Appen heter Klimat på hemskärmen.

## Bygg

Öppna `KlimatMobile.xcodeproj` i Xcode och bygg schemat `KlimatMobile`. Projektet kan också genereras från `project.yml` med XcodeGen.

## Direktanslutning

Klimat söker efter kompatibla Daikin-, Mitsubishi- och Gree-adaptrar på samma privata Wi-Fi-nät som iPhone använder. De kan också läggas till med IP-adress. Daikin-stödet gäller adaptrar med det äldre lokala HTTP-API:t. Mitsubishi-stödet gäller MAC-577-adaptrar med det lokala `/smart`-gränssnittet och använder AES-krypterad trafik. Gree-stödet gäller kompatibla Smart WiFi-moduler som använder Gree-protokollet på UDP-port 7000; appen parar lokalt och sparar enhetsnyckeln i iOS-nyckelringen. Status, ström, temperatur, läge och fläkt styrs direkt över Wi-Fi utan internet eller moln. Mitsubishi-protokollet bygger på referensen [pymitsubishi](https://github.com/pymitsubishi/pymitsubishi); Gree-protokollet bygger på [gree-climate](https://github.com/thesmokinator/gree-climate). Licenser anges i `THIRD_PARTY_NOTICES.md`.

Klimat kan också läsa och styra HomeKit-termostater och värme-/kylreglage som användaren redan har lagt till i Apple Home. Åtkomst begärs först när användaren väljer Apple Home. Enheten måste exponera HomeKits klimatreglage; stöd för alla funktioner varierar mellan tillverkare.

MELCloud Classic finns som valfri molnanslutning för Mitsubishi-konton. Den kräver internet. Lösenordet skickas direkt till MELCloud för inloggning och sparas inte av appen. Sessionsnyckeln sparas i iOS-nyckelringen. API:t är inofficiellt och integrationen behöver verifieras med ett aktivt konto och fysisk enhet; andra tillverkares molntjänster är inte anslutna.

Vilka modeller som fungerar beror på Wi-Fi-adapter, firmware och protokollversion. Stödet för Mitsubishi och Gree är ännu inte verifierat mot fysisk AC-hårdvara. Appen söker i det privata IPv4-subnät som iPhone använder via Wi-Fi och hämtar enhetsstatus endast från svar som matchar respektive protokoll. Subnät större än 512 adresser avböjs. Det här är inte en generell sökning efter alla AC-märken. Apple Home stöder redan parade HomeKit-enheter. MELCloud Classic kan ansluta via internet; andra molntjänster är inte anslutna. Klimat sparar inte MELCloud-lösenordet och lagrar sessionsnyckeln i iOS-nyckelringen.

## Kvar före försäljning

Klimat har lokal styrning för kompatibla Daikin-, Mitsubishi- och Gree-adaptrar. Gree och Mitsubishi behöver fortfarande provas mot fysisk AC-hårdvara. Developer Mode måste också aktiveras på den ihopparade iPhonen innan appen kan köras där.

Före publicering återstår därför hårdvaruverifiering, en signerad iOS-version, skärmbilder, support- och integritetssidor samt färdig butikspresentation. App Store Connect visar redan grundpriset 39,00 kr i Sverige. Kontoinnehavaren behöver godkänna Apples avtal för betalappar innan Klimat kan säljas.

## Fler lokala apparater

Gree-protokollet är nu implementerat för kompatibla Wi-Fi-moduler. Det använder lokal UDP-trafik på port 7000 med AES-baserad bindning och status-/kommandotrafik. Enhetsstöd behöver verifieras mot fysiska modeller innan bredare kompatibilitetslöften. [Gree-protokollbibliotek](https://github.com/thesmokinator/gree-climate) · [Gree-enhetsmanual](https://www.greecomfort.com/assets/our-products/vireo-r32/documents/vireo-r32-service-manual-a.pdf).

Midea/Comfee och flera ommärkta märken har också LAN-styrning, men dokumenterade Midea-flöden hämtar normalt en enhetsspecifik token/nyckel från Mideas moln vid första parkopplingen. Därför prioriteras det efter ett helt lokalt Gree-flöde, om inte enheten kan provisioneras utan moln. [Midea LAN-projektets parkopplings- och nyckeldokumentation](https://github.com/midea-lan/midea-local#finding-your-device).
