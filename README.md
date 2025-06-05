# FB-Traffic-KDE
 Surveillance monitor for FritzBox as KDE Plasmoid Widget

 The FB-Traffic-KDE widget is inspired by the Windows tool Fritz!Box Traffic and provides a similar function for KDE (Linux). The current version has been tested under Plasma5.

Debugging help:
- Restart Plasma interface: kquitapp5 plasmashell && plasmashell &
- Restart: plasmoidviewer --applet com.github.dezi.fboxtraffic
- Re-register service: kpackagetool5 --install ~/.local/share/plasma/plasmoids/com.github.dezi.fboxtraffic
- Update service: kpackagetool5 --upgrade ~/.local/share/plasma/plasmoids/com.github.dezi.fboxtraffic
