// Icona della barra dei menu, disegnata in codice come immagine "template"
// (macOS la colora da solo per il tema chiaro, scuro e per l'evidenziazione).
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, RTStatusIconStyle) {
    RTStatusIconOff,         // radio spenta: solo contorno
    RTStatusIconConnecting,  // in connessione: piena, semitrasparente
    RTStatusIconOn,          // in riproduzione: piena
};

NSImage *RTStatusIconImage(RTStatusIconStyle style);
