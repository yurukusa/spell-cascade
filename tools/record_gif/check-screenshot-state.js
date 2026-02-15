(function(){
    var sl = document.querySelector(".screenshot_list");
    if (!sl) return "NO screenshot_list";
    var imgs = sl.querySelectorAll("img");
    var uploading = sl.querySelectorAll(".uploading_screenshot");
    var items = sl.querySelectorAll(".screenshot_editor");
    return "imgs:" + imgs.length + " uploading:" + uploading.length + " items:" + items.length + " html:" + sl.innerHTML.substring(0, 800);
})()