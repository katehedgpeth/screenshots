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

function handle_image(type) {
  return (data) => {
    try {
      const img_container = document.getElementById(data.name + "--" + type);
      img_container.classList.remove("image--loading");
      img_container.style.flexGrow = "1";
      img_container.addEventListener("click", toggle_image_width);
      const img = new Image();
      img.src = type + "/" + data.name + ".png"
      img_container.append(img);
      run_diff(data.name);
    } catch (error) {
      console.error(error);
    }
  }
}

function handle_error(data) {
  console.log("error", data)
}

export function toggle_image_width(e) {
  console.log("image clicked", e.currentTarget.style.flexGrow);
  e.currentTarget.style.flexGrow = e.currentTarget.style.flexGrow == "1" ? "4" : "1";
  return false;
}
export default socket
