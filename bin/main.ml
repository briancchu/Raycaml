(** 
   how to write PPM file:
   - create an output file stream (ex output.ppm)
   - writing to a file in OCaml: open file to obtain an out_channel 
     -- write stuff to the channel 
     -- when done, close the channel (should flush out_channel)
     -- functions: open_out, open_out_bin, flush, close_out, close_out_nerr
     -- standard out_channels: stdout, stderr - need to write a header:
     P3 
     width height 
     maximum size of colors (255)
   - for loop 
     -- outer loop = row 
     -- inner loop = each pixel in that row (columns)
   - three values for red green and blue, %256 to be within 255 bounds
*)
open Yojson.Basic.Util
open Raycaml

(** [shade ray hit scene lights depth] is the color that is produced by [ray]
    producing [hit] in [scene] with [lights] and reflection up to [depth] *)
let rec shade ray hit lights depth scene bg_color =
  let fold_light acc v = Vector.add acc (Light.illuminate hit scene v) in
  let color = List.fold_left fold_light (Vector.create 0. 0. 0.) lights in

  if depth > 0 then
    let v = Vector.mult_constant (Ray.dir ray) ~-.1.0 in
    let norm = Hit.norm hit in
    let new_dir =
      v
      |> Vector.dot_prod norm
      |> ( *. ) 2.0
      |> Vector.mult_constant (Vector.minus norm v)
    in
    let ray = Ray.create (Hit.point hit) new_dir |> Ray.add_start 0.0001 in
    Vector.add color (
      match Scene.intersect ray scene with
      | Some new_hit ->
        hit
        |> Hit.mat
        |> Material.mirror (shade ray new_hit lights (depth - 1) scene bg_color)
      | None ->
        hit
        |> Hit.mat
        |> Material.mirror bg_color
    )
  else color

(** [create_ppm cam lights scene bg_color file w h] writes a ppm file named 
    [file] of [scene] with background color [bg_color], [camera], and [lights]. 
    The ppm file has height [h] and width [w]. *)
let create_ppm camera lights scene bg_color file width height = 
  let oc = open_out file in    (* create or truncate file, return channel *)
  Printf.fprintf oc "P6\n%d %d\n255\n" width height; 
  for i = 0 to pred height do (* write each row *)
    for j = 0 to pred width do (* write each pixel in a row *)
      let v = ((float_of_int i) +. 0.5) /. (float_of_int height) in
      let u = ((float_of_int j) +. 0.5) /. (float_of_int width) in
      let ray = Camera.generate_ray camera u v in
      match Scene.intersect ray scene with
      | Some hit ->
        let color = shade ray hit lights 100 scene bg_color in
        Vector.output_vector color oc
      | None -> 
        Vector.output_vector bg_color oc
    done 
  done;

  output_char oc '\n';
  close_out oc; (* flush and close the channel *)

  print_endline "  Congratulations! Your completed raytraced scene, output as a 
  ppm file, should be located in whatever directory you're currently in. 
  Thank you for using our Raytracer! We hope you had fun."; 


type material = Material.t

type custom_in = {
  objects_in : Object.t list;
  camera_in : Camera.t; 
  bg_color_in : Vector.t;
  light_in : Light.t; 
}

type choice = 
  | Continue
  | Quit

exception Empty

(** [select_words lst] is a choice determined by the list of words [lst].
    If [lst] is empty, meaning that the user didn't input anything, it raises
    the exception [Empty]. If [lst] contains 'quit', meaning the user wants to 
    stop inputting objects, then it returns the choice [Quit]. Otherwise, 
    it is the choice [Continue] *)
let rec select_words lst = 
  match lst with 
  | [] -> raise Empty 
  | "" :: t -> select_words t 
  | "quit" :: _ -> Quit 
  | _ :: _ -> Continue

(** [parse str] returns a list of individual words from [str].*)
let parse str =
  str |> String.split_on_char ' '|> select_words 

(** [get_comma index] is [index] of a comma if it exists,
    otherwise it's an exception. *)
let get_comma index = 
  match index with 
  | Some v -> v 
  | None -> failwith "That is not a valid vector input. Recall that your
  input should include parentheses and three numbers separated by commas. 
  For example: (0.0,1.0,2.0)."

(** [get_float str] is the float value of [str]. The reason float_of_string
    is being implemented in this way is so that a proper error message can be 
    shown to the user. *)
let get_float str = 
  try 
    float_of_string str 
  with _ -> failwith "That is not a float. Please enter a numeric value
  next time. For example: 1 or 1.0"

(** [get_int str] is the integer value of [str]. The reason int_of_string
    is being implemented in this way is so that a proper error message can be 
    shown to the user. *)
let get_int str = 
  try 
    int_of_string str 
  with _ -> failwith "That is not an integer. Please enter an integer value 
  next time with no decimal points. For example: 1"

(** [vector_of_string vec] is the vector created from a string [vec]. If the
    user input is invalid it is an exception.*)  
let vector_of_string vec = 
  let fstcomma = String.index_opt vec ',' in 
  let x = String.sub vec 1 ((get_comma fstcomma) - 1) in 
  let sndcomma = String.index_from_opt vec ((get_comma fstcomma) + 1) ',' in 
  let y = String.sub vec ((get_comma fstcomma) + 1) 
      ((get_comma sndcomma) - (get_comma fstcomma) - 1) in 
  let closep = String.index_from_opt vec ((get_comma sndcomma) + 1) ')' in 
  let z = String.sub vec (get_comma sndcomma + 1) 
      ((get_comma closep) - (get_comma sndcomma) - 1) in
  try 
    Vector.create (get_float x) (get_float y) (get_float z)
  with _ -> failwith "That is not a valid vector input. Recall that your
  input should include parentheses and three numbers separated by commas. 
  For example: (0.0,1.0,2.0)"

(** [get_material] builds the material for an object based on a sequence of user
    inputs.*)
let get_material () =
  print_endline "  Next, we would like to know the material properties of your 
  object. We will start with diffusion. Light is said to be diffused when it 
  hits an object and scatters in a seemingly random way. Our diffuse property 
  has three components: x, which determines the amount of red light scattered;
  y, the amount of green light scattered; and z, the amount of blue light. So, 
  the larger the x value, the more red the object will appear, and so on. 
  Please input the diffusion as a VECTOR (x,y,z), where all values are between 
  0 and 0.9";
  let diffuse = vector_of_string (read_line()) in 
  print_endline "  Next, please input the specular color as a VECTOR (x,y,z)
  with values between 0 and 0.9. A specular highlight is a mirror reflection of 
  a light source. This color value will determine the hue of the light that is 
  reflected, with x corresponding to red, y with green, and z with blue.";
  let spec_co = vector_of_string (read_line()) in 
  print_endline "  Input the specular exponent as a FLOAT. This controls what
  can be thought of as the 'shininess' of the object. The larger the number 
  e.g. 100.0, the more focused the reflection on the object will appear, and 
  thus it will seem shinier. The smaller the number, e.g. 1.0, the more spread 
  out the reflection will be, causing it to appear more dull.";
  let spec_exp = get_float (read_line()) in 
  print_endline "  Please input the reflective property of your object as a 
  VECTOR (x,y,z) with each value between 0 and 0.9. Surfaces can be highly 
  reflective, which causes many shadow rays to bounce off of them, or lowly 
  reflective. This is broken into red, green, and blue components corresponding 
  to x, y, and z respectively.";
  let mirror = vector_of_string (read_line()) in 
  print_endline "  Please input the ambient as a VECTOR (x,y,z) with each value
  between 0 and 0.9. Ambient light is the result of interactions between light 
  sources and the objects in the scene. It appears to be uniform all over. It is
  also separated into red, green, and blue components.";
  let ambient = vector_of_string (read_line()) in
  Material.create diffuse spec_co spec_exp mirror ambient

(** [get_sphere] is the sphere created from the specifications of the user.*)
let get_sphere () = 
  print_endline "  Please enter the radius of the sphere as a FLOAT. For a 
  small sphere, enter a value between 0-0.2. For a medium sphere enter a value 
  between 0.2-0.5. For a large sphere enter a value vetween 0.5-1.0"; 
  let radius = get_float (read_line()) in 
  print_endline "  Please enter the center of the sphere as a VECTOR in the 
  form (x,y,z) including the parentheses and with no spaces. The x coordinate
  represents its left-right position, with negative values on the left hand
  side, and positive values on the right. The y coordinate is vertical 
  position, so negative values on the bottom and positive for the top. The z 
  coordinate controls whether the object is in the foreground or background, 
  so a negative z value pushes the object further back, and a positive one 
  brings the object forward.";
  let center = vector_of_string (read_line()) in 
  let material = get_material () in 
  Object.create_sphere radius center material 

(** [get_triangle] is the triangle created from the specifications of the 
    user.*)
let get_triangle () = 
  print_endline "  We will now enter the vertices of the triangle. Please enter 
  the first vertex of the triangle as a position VECTOR (x,y,z)."; 
  let vert1 = vector_of_string (read_line()) in 
  print_endline "  Please enter the second vertex of the triangle as a position 
  VECTOR (x,y,z)."; 
  let vert2 = vector_of_string (read_line()) in 
  print_endline "  Please enter the third vertex of the triangle as a position 
  VECTOR (x,y,z)."; 
  let vert3 = vector_of_string (read_line()) in 
  let material = get_material () in 
  Object.create_triangle (vert1, vert2, vert3) material

(** [get_camera] is the camera created from the specifications of the
    user. *)
let get_camera () = 
  print_endline "  Next, we would like to know the physical properties of your 
  camera. To begin with, please enter the origin of the camera as a position
  VECTOR (x,y,z)"; 
  let origin = vector_of_string (read_line()) in 
  print_endline 
    "  Next, the target of the camera will be the position that the camera will
  be directly looking at. Please enter the target of the camera as a position 
  VECTOR (x,y,z).";
  let target = vector_of_string (read_line()) in 
  print_endline "  Next, we want to know the aspect ratio for the camera. The
  aspect ratio is ratio of the width to the height for the dimensions of the 
  image. Please enter the aspect ratio of the camera as a FLOAT.";
  let aspect_ratio = get_float (read_line()) in 
  print_endline 
    "  Next, we would like the vertical vector of the camera. This 
  vertical vector is orthogonal to the camera's origin and points upwards in 
  the plane of the camera. Please enter the vertical vector of the camera as a 
  VECTOR (x,y,z).";
  let vertical = vector_of_string (read_line()) in 
  print_endline 
    "  Lastly, for the camera, we would like the vertical field of view of the 
  camera. The vertical field of view is the angle range in radians of what the 
  camera is capable of seeing. Please enter the vertical field of view of the 
  camera as a FLOAT.";
  let vfov = get_float (read_line()) in 
  Camera.create origin target aspect_ratio vertical vfov 

(** [get_light] is the light created from the specifications of the user.*)
let rec get_lights lights = 
  print_endline "  We will now create the lighting using one or more light 
  sources. To describe the lighting, we must first describe the intensity of 
  the lighting as a VECTOR where the magnitude of the intensity is measured in 
  the x, y, and z direction. If you would like to add a light source, please 
  enter the intensity of the light as a VECTOR (x,y,z). If you have ALREADY
  entered ALL the light sources you would like (your scene must have AT LEAST 
  ONE), then please enter 'quit'."; 
  let intensity = read_line() in 
  match (parse intensity) with 
  | Continue -> begin 
      let intens_vec = vector_of_string intensity in
      print_endline "  If you would like a specific position of the light 
  source, please enter it as a position VECTOR (x,y,z) with values between 
  0-0.9. Otherwise, enter 'None'. Entering none will create 'ambient lighting,' 
  while giving your light a position will make it a point source."; 
      let position = read_line() in 
      if position = "None" then get_lights 
          ((Light.create_ambient intens_vec) :: lights)
      else get_lights ((Light.create_point intens_vec 
                          (vector_of_string position)) :: lights)
    end 
  | Quit -> lights
  | exception Empty -> get_lights []



(** [get_scene objs] is the scene created from the specifications of the
    user. The scene contains objects [objs] and a background color determined by 
    the user.*)
let get_scene objlist = 
  print_endline 
    "  We will now create the scene. Please enter the background color
   as a VECTOR (x,y,z) where x, y, and z represent RBG respectively. These 
   values should be between 0 and 1, with 1 corresponding to maximum saturation,
   aka 255 on RGB spectrum, and 0 corresponding to no saturation of that 
   color."; 
  let bg_color = vector_of_string (read_line()) in 
  Scene.create objlist bg_color 

(** [get_file_name] is the string that the user wants to name their ppm file.*)
let get_file_name () = 
  print_endline "  Now, we're almost done. You get to name your ppm file. What 
  would you like your finished product to be called?"; 
  read_line() ^ ".ppm"

(** [get_width] is the width that the user wants their ppm file to have.*)
let get_width () = 
  print_endline "  How wide should your image be in pixels? (enter an INTEGER)";
  get_int (read_line())

(** [get_height] is the height that the user wants their ppm file to have.*)
let get_height () = 
  print_endline "  What should the height of your image be in pixels? (enter an 
  INTEGER)"; 
  get_int (read_line())

(** [get_inputs objs] is the ppm file that the user designs based on a 
    series of inputs.*)
let rec get_inputs objlist = 
  print_endline "  Please enter a valid TYPE of the object you would like to 
  add to the scene (Sphere or Triangle - case sensitive). Or, if you have 
  already entered all of the objects you want, then type 'quit'"; 
  let next_choice = read_line() in 
  match (parse next_choice) with 
  | Continue -> begin 
      let object_type = next_choice in 
      if object_type = "Sphere" then 
        get_inputs ((get_sphere ()) :: objlist) 
      else if object_type = "Triangle" then 
        get_inputs ((get_triangle ()) :: objlist)
      else get_inputs objlist
    end 
  | Quit -> begin 
      let camera = get_camera () in 
      let lights = get_lights [] in 
      let scene = get_scene objlist in 
      let file_name = get_file_name () in 
      let width = get_width () in 
      let height = get_height () in 
      create_ppm camera lights scene (Scene.bg_color scene) file_name width 
        height
    end 
  | exception Empty -> get_inputs []

(** [plain_json] is the ppm file determined by an input json file that 
    contains all the data about the scene. *)
let plain_json () = 
  (* Ask for json file, if didn't get one, print message and exit *)
  let input_json = Yojson.Basic.from_file (Sys.argv.(1)) in
  let camera = input_json |> member "camera" |> Camera.from_json in
  let lights =
    input_json |> member "lights" |> to_list |> List.map Light.from_json in
  let scene = input_json |> Scene.from_json in
  let bg_color = Scene.bg_color scene in
  let file = (Sys.argv.(1) |> String.split_on_char '.' |> List.hd) ^ ".ppm" in
  (* If a commandline argument integer was passed after the scene, use it 
      as the width.
    * Otherwise, default is 320 *)
  let width =
    try int_of_string Sys.argv.(2)
    with _ -> 320
  in
  let height = int_of_float ((float_of_int width) /. 
                             (Camera.get_aspect camera)) in 
  create_ppm camera lights scene bg_color file width height 

let () = 
  if Array.length Sys.argv != 1 then plain_json () else
    (print_endline "  Welcome to RayCaml, our OCaml raytracer."; get_inputs [])