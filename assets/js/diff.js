import resemble from "resemblejs";
import {toggle_image_width} from "./socket.js";

export function run_diff(img_name) {
  const row_container = document.getElementById(img_name);
  if (row_container.querySelector(".image--ref img") && row_container.querySelector(".image--test img")) {
    resemble("ref/" + img_name + ".png").compareTo("test/" + img_name + ".png").onComplete(function(data) {
      const diff_container = document.getElementById(img_name + "--diff")
      diff_container.classList.remove("image--loading");
      diff_container.style.flexGrow = "1";
      diff_container.addEventListener("click", toggle_image_width);
      if (data.rawMisMatchPercentage > 0) {
        const diff_image = new Image();
        diff_image.src = data.getImageDataUrl()
        diff_container.appendChild(diff_image);
        diff_container.parentNode.dispatchEvent(new CustomEvent("image_failed", {detail: data, bubbles: true}));
      } else {
        diff_container.parentNode.dispatchEvent(new CustomEvent("image_passed", {detail: data, bubbles: true}));
      }
    });
  }
}
