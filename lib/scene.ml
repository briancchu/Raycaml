open Yojson.Basic.Util

type t = { objects: Object.t list; camera: Camera.t; bg_color: Vector.t }

let from_json json = failwith "todo"

let create objects camera bg_color = { objects; camera; bg_color }

let objects scene = scene.objects

let camera scene = scene.camera

let cmp_hit h1 h2 = Stdlib.compare (Hit.distance h1) (Hit.distance h2)

let get_greater_hit h1 h2 =
  match Option.compare cmp_hit h1 h2 with 
  | 1 -> h1
  | _ -> h2

let intersect ray scene = 
  scene.objects
  |> List.map (fun obj -> Object.intersect ray obj)
  |> List.fold_left (get_greater_hit) None