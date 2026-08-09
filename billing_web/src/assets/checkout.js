/**
 * Atlas billing checkout page — sandbox Paddle.js UX only.
 * Never grants Premium. Never logs tokens or query strings.
 */
(function () {
  "use strict";

  var EXPECTED_PATH = "/billing/checkout";
  /** Exact Paddle transaction id (docs: ^txn_[a-z\d]{26}$). */
  var TXN_RE = /^txn_[a-z\d]{26}$/;
  /** Exact Paddle sandbox client-side token. */
  var CLIENT_TOKEN_RE = /^test_[a-zA-Z0-9]{27}$/;

  function byId(id) {
    return document.getElementById(id);
  }

  function setMessage(title, body) {
    var titleEl = byId("checkout-title");
    var bodyEl = byId("checkout-body");
    if (titleEl) titleEl.textContent = title;
    if (bodyEl) bodyEl.textContent = body;
  }

  function isLocalHost(hostname) {
    return (
      hostname === "localhost" ||
      hostname === "127.0.0.1" ||
      hostname === "[::1]"
    );
  }

  function readConfig() {
    var cfg = window.AtlasBillingRuntime;
    if (!cfg || typeof cfg !== "object") return null;
    return cfg;
  }

  function hasValidClientToken(cfg) {
    return (
      cfg &&
      cfg.checkoutEnabled === true &&
      typeof cfg.paddleSandboxClientToken === "string" &&
      CLIENT_TOKEN_RE.test(cfg.paddleSandboxClientToken)
    );
  }

  function pathnameOk() {
    return window.location.pathname === EXPECTED_PATH;
  }

  function httpsOk() {
    if (isLocalHost(window.location.hostname)) return true;
    return window.location.protocol === "https:";
  }

  function readPtxn() {
    try {
      return new URLSearchParams(window.location.search).get("_ptxn");
    } catch (_) {
      return null;
    }
  }

  function init() {
    if (!pathnameOk() || !httpsOk()) {
      setMessage(
        "Checkout non disponibile",
        "Apri il collegamento di pagamento fornito dall'applicazione.",
      );
      return;
    }

    var cfg = readConfig();
    if (!hasValidClientToken(cfg)) {
      setMessage(
        "Checkout non disponibile",
        "Il pagamento non è configurato in questo ambiente.",
      );
      return;
    }

    var ptxn = readPtxn();
    if (!ptxn || !TXN_RE.test(ptxn)) {
      setMessage(
        "Collegamento non valido",
        "Questo collegamento di pagamento non è valido o è scaduto.",
      );
      return;
    }

    if (!window.Paddle || typeof window.Paddle.Initialize !== "function") {
      setMessage(
        "Checkout non disponibile",
        "Impossibile avviare il pagamento. Riprova più tardi.",
      );
      return;
    }

    setMessage(
      "Pagamento in corso",
      "Se la finestra di pagamento non si apre, aggiorna la pagina o riprova dal collegamento dell'app.",
    );

    try {
      window.Paddle.Environment.set("sandbox");
      window.Paddle.Initialize({
        token: cfg.paddleSandboxClientToken,
        eventCallback: function (event) {
          if (!event || typeof event.name !== "string") return;
          if (event.name === "checkout.completed") {
            window.location.replace("/billing/return");
            return;
          }
          if (event.name === "checkout.closed") {
            setMessage(
              "Pagamento chiuso",
              "Puoi chiudere questa pagina oppure riprovare dal collegamento dell'applicazione.",
            );
          }
        },
      });
      // Rely on Paddle.js _ptxn auto-open. Do not open checkout via the Paddle JS open API.
    } catch (_) {
      setMessage(
        "Checkout non disponibile",
        "Impossibile avviare il pagamento. Riprova più tardi.",
      );
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
