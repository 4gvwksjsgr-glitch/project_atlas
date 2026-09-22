/// Separatore decimale scelto dall'utente quando il file è ambiguo.
///
/// [auto] non risolve mai un'ambiguità in silenzio: se il file non è
/// interpretabile in modo deterministico la riga resta in attesa di scelta.
enum NumberFormatPreference { auto, commaDecimal, dotDecimal }

/// Ordine dei campi data scelto dall'utente quando giorno e mese sono ambigui.
enum DateFormatPreference { auto, ymd, dmy, mdy }
