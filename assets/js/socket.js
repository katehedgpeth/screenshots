// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

// To use Phoenix channels, the first step is to import Socket
// and connect at the socket path in "lib/web/endpoint.ex":
import {Socket} from "phoenix"
import {run_diff} from "./diff.js"

let socket = new Socket("/socket", {params: {}})

socket.connect()

// Now that you are connected, you can join channels with a topic:
let channel = socket.channel("screenshots:test", {})

channel.on("test_image", handle_image("test"));
channel.on("ref_image", handle_image("ref"));
channel.on("error", handle_error);

channel.join()
  .receive("ok", resp => { console.log("Joined successfully", resp) })
  .receive("error", resp => { console.log("Unable to join", resp) })

Array.from(document.getElementsByClassName("breakpoint")).forEach(breakpoint => {
  breakpoint.addEventListener("image_passed", on_image_passed(breakpoint));
  breakpoint.addEventListener("image_failed", on_image_failed(breakpoint));
  breakpoint.addEventListener("image_error", on_image_error(breakpoint));
});
Array.from(document.getElementsByClassName("result")).forEach(result => {
  result.addEventListener("image_passed", on_result(result));
  result.addEventListener("image_failed", on_result(result));
  result.addEventListener("image_error", on_result(result));
});

function handle_image(type) {
  return (data) => {
    const img_container = document.getElementById(data.name + "--" + type);
    img_container.classList.remove("image--loading");
    img_container.style.flexGrow = "1";
    img_container.addEventListener("click", toggle_image_width);
    const img = new Image();
    img.src = type + "/" + data.name + ".png"
    img_container.append(img);
    run_diff(data.name);
  }
}

function handle_error(data) {
  console.log("error", data);
  if (data.name && data.type) {
    const img_container = document.getElementById(data.name + "--" + data.type);
    img_container.parentNode.dispatchEvent(new CustomEvent("image_error", {detail: data, bubbles: true}))
  } else {
    console.error("expected error data to have :name and :type keys")
  }
}

function on_image_passed(breakpoint) {
  return (e) => {
    breakpoint.querySelector(".images").style.display = "none";
    breakpoint.classList.add("breakpoint--passed")
    return true;
  }
}

function on_image_failed(breakpoint) {
  return (e) => {
    console.log("breakpoint failed", e.detail);
    breakpoint.classList.add("breakpoint--failed")
    breakpoint.querySelector(".error").textContent = `
      diffBounds: {\n
        top: ${e.detail.diffBounds.top},\n
        left: ${e.detail.diffBounds.left},\n
        bottom: ${e.detail.diffBounds.bottom},\n
        right: ${e.detail.diffBounds.right}\n
      },\n
      dimensionDifference: {\n
        width: ${e.detail.dimensionDifference.width},\n
        height: ${e.detail.dimensionDifference.height}\n
      },\n
      isSameDimensions: ${e.detail.isSameDimensions},\n
      misMatchPercentage: ${e.detail.misMatchPercentage}\n
    `;
    return true;
  }
}

function on_image_error(breakpoint) {
  return (e) => {
    breakpoint.classList.add("breakpoint--error");
    breakpoint.querySelector(".images").style.display = "none";
    breakpoint.querySelector(".error").textContent = e.detail.error.message;
    return true;
  }
}

function on_result(result) {
  return (e) => {
    const breakpoints = Array.from(result.getElementsByClassName("breakpoint"));
    const failed = [];
    const passed = [];
    breakpoints.forEach(sort_breakpoints(failed, passed));
    if (failed.length > 0) {
      result.classList.add("result--failed");
    } else if (failed.length == 0 && passed.length == breakpoints.length) {
      result.classList.add("result--passed");
    }
  }
}

function sort_breakpoints(failed, passed) {
  return (breakpoint) => {
    if (breakpoint.classList.contains("breakpoint--failed")) {
      failed.push(breakpoint);
    } else if (breakpoint.classList.contains("breakpoint--passed")) {
      passed.push(breakpoint);
    }
  }
}

export function toggle_image_width(e) {
  e.currentTarget.style.flexGrow = e.currentTarget.style.flexGrow == "1" ? "4" : "1";
  return false;
}
export default socket
