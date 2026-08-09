/**
 * Atlas billing return page — UX only.
 * Does not call backends. Does not claim payment or Premium succeeded.
 */
(function () {
  "use strict";

  function init() {
    var title = document.getElementById("return-title");
    var body = document.getElementById("return-body");
    if (title) {
      title.textContent = "Stiamo verificando il pagamento.";
    }
    if (body) {
      body.textContent =
        "L'abbonamento verrà aggiornato dopo la conferma.";
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
