/* PredictBar marketing site — interactions
   count-up · menu-bar metric cycle · copy-to-clipboard · tabs · scroll-reveal */
(function () {
  "use strict";

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- sticky nav shadow ---------- */
  var nav = document.getElementById("nav");
  function onScroll() {
    if (nav) nav.classList.toggle("is-scrolled", window.scrollY > 8);
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ---------- count-up numbers in the sim ---------- */
  function formatNum(el, value) {
    var prefix = el.dataset.prefix || "";
    var suffix = el.dataset.suffix || "";
    var arrow = el.dataset.arrow ? " ▲" : "";
    var decimals = (el.dataset.count.indexOf(".") > -1) ? 2 : 0;
    // ROI shown to one decimal, dollars to two
    if (suffix === "%") decimals = 1;
    return prefix + value.toFixed(decimals) + suffix + arrow;
  }

  function countUp(el) {
    var target = parseFloat(el.dataset.count);
    if (isNaN(target)) return;
    if (reduceMotion) {
      el.textContent = formatNum(el, target);
      return;
    }
    var duration = 1100;
    var start = null;
    function step(ts) {
      if (start === null) start = ts;
      var p = Math.min((ts - start) / duration, 1);
      var eased = 1 - Math.pow(1 - p, 3); // easeOutCubic
      el.textContent = formatNum(el, target * eased);
      if (p < 1) {
        requestAnimationFrame(step);
      } else {
        el.textContent = formatNum(el, target);
        el.classList.add("pulse");
        el.addEventListener("animationend", function () { el.classList.remove("pulse"); }, { once: true });
      }
    }
    requestAnimationFrame(step);
  }

  function runCountUp() {
    var nums = document.querySelectorAll("[data-count]");
    nums.forEach(function (el, i) {
      if (reduceMotion) { countUp(el); return; }
      setTimeout(function () { countUp(el); }, 250 + i * 130);
    });
  }

  // Trigger count-up when the sim enters view (or immediately if already visible)
  var sim = document.querySelector(".hero__sim");
  var counted = false;
  function maybeCount() {
    if (counted || !sim) return;
    var r = sim.getBoundingClientRect();
    if (r.top < window.innerHeight && r.bottom > 0) {
      counted = true;
      runCountUp();
    }
  }
  maybeCount();
  window.addEventListener("scroll", maybeCount, { passive: true });
  window.addEventListener("load", maybeCount);

  /* ---------- menu-bar metric cycle ---------- */
  var metrics = [
    { value: "$56.39" },   // Cash Out
    { value: "+22.8%" },   // ROI
    { value: "+$10.49" },  // P&L
    { value: "$66.88" },   // Portfolio
    { value: "$124.50" }   // Balance
  ];
  var mbValue = document.getElementById("mbValue");
  var mbPill = document.getElementById("mbPill");
  var idx = 0;
  var cycleTimer = null;

  function showMetric(i) {
    if (!mbValue) return;
    mbValue.textContent = metrics[i].value;
    if (!reduceMotion) {
      mbValue.animate(
        [{ opacity: 0, transform: "translateY(-4px)" }, { opacity: 1, transform: "none" }],
        { duration: 280, easing: "ease" }
      );
    }
  }
  function nextMetric() {
    idx = (idx + 1) % metrics.length;
    showMetric(idx);
  }
  function startCycle() {
    if (reduceMotion || cycleTimer) return;
    cycleTimer = setInterval(nextMetric, 3000);
  }
  function stopCycle() {
    if (cycleTimer) { clearInterval(cycleTimer); cycleTimer = null; }
  }
  if (mbPill) {
    mbPill.addEventListener("click", function () {
      stopCycle();
      nextMetric();
      // resume auto-cycle a few seconds after manual interaction
      setTimeout(startCycle, 6000);
    });
  }
  // Pause cycling when the tab is hidden
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) stopCycle(); else startCycle();
  });
  startCycle();

  /* ---------- copy-to-clipboard ---------- */
  var toast = document.getElementById("toast");
  var toastTimer = null;
  function showToast(msg) {
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add("is-show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove("is-show"); }, 1900);
  }
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); resolve(); }
      catch (e) { reject(e); }
      document.body.removeChild(ta);
    });
  }
  document.querySelectorAll(".copy-cmd").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var cmd = btn.dataset.cmd;
      if (!cmd) return;
      copyText(cmd).then(function () {
        showToast("Copied: " + cmd);
        btn.classList.add("is-copied");
        var label = btn.querySelector(".cmd-chip__copy");
        if (label) {
          var prev = label.textContent;
          label.textContent = "Copied";
          setTimeout(function () { label.textContent = prev; btn.classList.remove("is-copied"); }, 1800);
        } else {
          setTimeout(function () { btn.classList.remove("is-copied"); }, 1800);
        }
      }).catch(function () {
        showToast("Press ⌘C to copy");
      });
    });
  });

  /* ---------- alert-type preview ---------- */
  var ALERTS = {
    roi: {
      time: "now",
      title: "📈 High ROI — Nikola Jokić MVP",
      body: 'Position hit <b class="text-gain">+78.6%</b> ROI (threshold 60%). Cash-out value <b>$20.50</b>.'
    },
    profit: {
      time: "now",
      title: "🎯 Profit target hit — France World Cup",
      body: 'P&L reached <b class="text-gain">+$2.28</b>, crossing your <b>+$2.00</b> goal.'
    },
    price: {
      time: "now",
      title: "🔔 Price target — Bitcoin above $150k",
      body: 'Sell price touched <b class="text-mint">$0.44</b> — your target was <b>$0.42</b>.'
    },
    stop: {
      time: "now",
      title: "🛑 Stop-loss triggered — Fed rate cut",
      body: 'Price fell to <b>$0.48</b>, below your <b>$0.50</b> stop. Down <b class="text-loss">−$2.80</b>.'
    },
    arb: {
      time: "now",
      title: "⚖️ Arbitrage opportunity",
      body: 'Hedge detected — lock in <b class="text-gain">+$3.10</b> guaranteed across both sides.'
    }
  };
  var alertNotif = document.getElementById("alertNotif");
  var alertTitle = document.getElementById("alertTitle");
  var alertBody = document.getElementById("alertBody");
  var alertTime = document.getElementById("alertTime");
  var chips = document.querySelectorAll(".chip[data-alert]");

  function setAlert(key, animate) {
    var a = ALERTS[key];
    if (!a || !alertTitle) return;
    alertTitle.textContent = a.title;
    alertBody.innerHTML = a.body;
    if (alertTime) alertTime.textContent = a.time;
    if (animate && !reduceMotion && alertNotif) {
      alertNotif.classList.remove("is-swap");
      void alertNotif.offsetWidth; // force reflow to restart the animation
      alertNotif.classList.add("is-swap");
    }
  }
  chips.forEach(function (chip) {
    chip.addEventListener("click", function () {
      chips.forEach(function (c) {
        var on = c === chip;
        c.classList.toggle("is-active", on);
        c.setAttribute("aria-pressed", on ? "true" : "false");
      });
      setAlert(chip.dataset.alert, true);
    });
  });

  /* ---------- install tabs ---------- */
  var tabs = document.querySelectorAll(".tab");
  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      var name = tab.dataset.tab;
      tabs.forEach(function (t) {
        var on = t === tab;
        t.classList.toggle("is-active", on);
        t.setAttribute("aria-selected", on ? "true" : "false");
      });
      document.querySelectorAll(".tab-panel").forEach(function (p) {
        p.classList.toggle("is-active", p.dataset.panel === name);
      });
    });
  });

  /* ---------- scroll reveal ---------- */
  var reveals = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    reveals.forEach(function (el) { el.classList.add("is-in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add("is-in");
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
    reveals.forEach(function (el) { io.observe(el); });
  }
})();
