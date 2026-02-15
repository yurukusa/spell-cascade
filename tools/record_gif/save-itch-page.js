(function(){
    // Find and click the save button
    var buttons = document.querySelectorAll("button, input[type=submit]");
    for (var i = 0; i < buttons.length; i++) {
        var txt = (buttons[i].textContent || buttons[i].value || "").trim().toLowerCase();
        if (txt === "save" || txt === "save & view page") {
            buttons[i].click();
            return "Clicked save button: " + txt;
        }
    }
    // Try the form submit
    var form = document.querySelector("form.edit_game");
    if (form) {
        form.submit();
        return "Submitted edit_game form";
    }
    return "ERROR: No save button found";
})()