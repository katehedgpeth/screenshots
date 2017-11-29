import resemble from "resemblejs";
Array.from(document.getElementsByClassName("result")).forEach(function(el) {
  var test_image = el.querySelector(".image--test img");
  var ref_image = el.querySelector(".image--ref img");
  resemble(ref_image.src).compareTo(test_image.src).onComplete(function(data) {
    var diff_image = new Image();
    diff_image.src = data.getImageDataUrl()
    el.querySelector(".image--diff").appendChild(diff_image);
  });
});
