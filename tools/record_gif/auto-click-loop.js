(function() {
    // Set up interval to auto-click first upgrade option every 3 seconds
    if (window._autoClicker) {
        clearInterval(window._autoClicker);
    }

    var clickCount = 0;
    window._autoClicker = setInterval(function() {
        var canvas = document.querySelector('canvas');
        if (!canvas) return;
        var rect = canvas.getBoundingClientRect();
        var cx = rect.width / 2;
        var cy = rect.height * 0.37;

        canvas.dispatchEvent(new MouseEvent('mousedown', {clientX: cx, clientY: cy, bubbles: true}));
        canvas.dispatchEvent(new MouseEvent('mouseup', {clientX: cx, clientY: cy, bubbles: true}));
        canvas.dispatchEvent(new MouseEvent('click', {clientX: cx, clientY: cy, bubbles: true}));
        clickCount++;
    }, 3000);

    // Auto-stop after 12 minutes
    setTimeout(function() {
        clearInterval(window._autoClicker);
    }, 720000);

    return 'Auto-clicker started (every 3s, stops after 12min). Will auto-select upgrades.';
})()
