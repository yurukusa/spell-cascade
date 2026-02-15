(function() {
    var canvas = document.querySelector('canvas');
    if (!canvas) return 'no canvas';

    // Click center to start the game
    var rect = canvas.getBoundingClientRect();
    var cx = rect.width / 2;
    var cy = rect.height / 2;
    canvas.dispatchEvent(new MouseEvent('mousedown', {clientX: cx, clientY: cy, bubbles: true}));
    canvas.dispatchEvent(new MouseEvent('mouseup', {clientX: cx, clientY: cy, bubbles: true}));
    canvas.dispatchEvent(new MouseEvent('click', {clientX: cx, clientY: cy, bubbles: true}));

    // Set up auto-clicker for upgrades (click first option when level-up appears)
    if (window._autoClicker) clearInterval(window._autoClicker);
    window._autoClicker = setInterval(function() {
        var c = document.querySelector('canvas');
        if (!c) return;
        var r = c.getBoundingClientRect();
        // Click first upgrade option position
        c.dispatchEvent(new MouseEvent('mousedown', {clientX: r.width/2, clientY: r.height*0.37, bubbles: true}));
        c.dispatchEvent(new MouseEvent('mouseup', {clientX: r.width/2, clientY: r.height*0.37, bubbles: true}));
        c.dispatchEvent(new MouseEvent('click', {clientX: r.width/2, clientY: r.height*0.37, bubbles: true}));
    }, 2000);

    // Stop after 2 minutes
    setTimeout(function() { clearInterval(window._autoClicker); }, 120000);

    return 'Game started with auto-clicker';
})()
