type t = { objects: Object.t list; camera: Camera.t }

let from_json json =
  failwith "todo"

let objects scene =
  scene.objects

let camera scene =
  scene.camera
