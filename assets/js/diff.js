import resemble from "resemblejs";

export function run_diff(img_name) {
  const row_container = document.getElementById(img_name);
  if (row_container.querySelector(".image--ref img") && row_container.querySelector(".image--test img")) {
    resemble("ref/" + img_name + ".png").compareTo("test/" + img_name + ".png").onComplete(function(data) {
      console.log(data);
      const diff_container = document.getElementById(img_name + "--diff")
      diff_container.classList.remove("image--loading");
      if (data.rawMisMatchPercentage > 0) {
        var diff_image = new Image();
        diff_image.src = data.getImageDataUrl()
        diff_container.appendChild(diff_image);
      } else {
        diff_container.classList.add("image--passed");
      }
    });
  }
}
