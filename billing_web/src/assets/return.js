/**
 * Atlas billing return page — finite UX only.
 * Does not call backends. Does not claim payment success.
 * Does not fetch or decide plan access.
 */
(function () {
  "use strict";

  var TITLE = "Pagamento inviato";
  var BODY =
    "Puoi tornare ad Atlas. Il piano verrà aggiornato appena Atlas riceve la conferma del pagamento.";
  var HINT =
    "Se la scheda di Atlas è ancora aperta, torna a quella finestra.";

  function tryFocusOpener() {
    try {
      if (window.opener && !window.opener.closed) {
        window.opener.focus();
        return true;
      }
    } catch (_) {
      /* cross-origin or blocked — ignore */
    }
    return false;
  }

  function tryCloseSelf() {
    try {
      window.close();
    } catch (_) {
      /* browsers may ignore — manual return remains valid */
    }
  }

  function onReturnClick() {
    var focused = tryFocusOpener();
    if (focused) {
      tryCloseSelf();
    }
  }

  function init() {
    var title = document.getElementById("return-title");
    var body = document.getElementById("return-body");
    var hint = document.getElementById("return-hint");
    var button = document.getElementById("return-to-atlas");

    if (title) {
      title.textContent = TITLE;
    }
    if (body) {
      body.textContent = BODY;
    }
    if (hint) {
      hint.textContent = HINT;
    }
    if (button) {
      button.addEventListener("click", onReturnClick);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
