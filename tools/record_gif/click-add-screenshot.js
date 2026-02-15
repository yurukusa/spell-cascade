(function() {
    var btn = document.querySelector("button.add_screenshot_btn");
    if (btn) {
        btn.click();
        return "Clicked add screenshot button";
    }
    return "ERROR: add_screenshot_btn not found";
})()
