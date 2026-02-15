(function() {
    var result = "";

    // Find screenshot-related elements
    var screenshotElems = document.querySelectorAll("[class*='screenshot'], [id*='screenshot'], [name*='screenshot'], [class*='gallery']");
    screenshotElems.forEach(function(e) {
        result += "SCREENSHOT: tag=" + e.tagName + " class=" + e.className.substring(0, 80) + "\n";
    });

    // Find all buttons that mention screenshot/image/gallery
    var buttons = document.querySelectorAll("button, a.button");
    buttons.forEach(function(b) {
        var txt = b.textContent.trim();
        if (txt.toLowerCase().indexOf("screenshot") !== -1 || txt.toLowerCase().indexOf("image") !== -1 || txt.toLowerCase().indexOf("gallery") !== -1 || txt.toLowerCase().indexOf("add") !== -1) {
            result += "BTN: " + txt.substring(0, 60) + " class=" + b.className.substring(0, 60) + "\n";
        }
    });

    // Find file inputs
    var fileInputs = document.querySelectorAll("input[type=file]");
    result += "File inputs: " + fileInputs.length + "\n";
    fileInputs.forEach(function(f) {
        result += "  FILE: name=" + f.name + " accept=" + f.accept + " class=" + f.className + "\n";
    });

    return result;
})()
