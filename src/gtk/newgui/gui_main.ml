(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

open Printf2
open Options
open Gettext
open Gui_global
open GMain
open GtkBase
open Gdk

module O = Gui_options
module M = Gui_messages
module Com = Gui_com
module G = Gui_global
module Mi = Gui_misc

(*module Gui_rooms = Gui_rooms2*)
let chmod_config () =
	let base_config = 
	    (Filename.concat CommonOptions.home_basedir ".mldonkey_gui.ini")
	in
	let save_config =
		base_config^".old"
	in
	begin
	if Sys.file_exists base_config then
		Unix.chmod base_config 0o600
	else
		()
	end;
	begin
	if Sys.file_exists save_config then
		Unix.chmod save_config 0o600
	else
		()
	end
  
let _ = 
  (try Options.load O.mldonkey_gui_ini with
      Sys_error _ ->
	(try Options.save O.mldonkey_gui_ini with _ -> ())
     | e ->
        lprintf "Exception %s in load options %s" 
	 (Printexc2.to_string e)
	 (Options.options_file_name O.mldonkey_gui_ini);
        lprint_newline ();
  );
  let args = 
    ("-dump_msg", Arg.Unit (fun _ ->
          Options.save Gui_messages.message_file
      ), ": update internationalisation message file")::
    Options.simple_args O.mldonkey_gui_ini in
  Arg.parse args (Arg.usage args)  "mlgui: the GUI to use with mldonkey"
  
(* Check bindings *)
let _ = 
  if !!O.keymap_global = [] then
    (
     let a = O.add_binding O.keymap_global in
     a "A-s" M.a_page_servers;
     a "A-d" M.a_page_downloads;
     a "A-f" M.a_page_friends;
     a "A-q" M.a_page_queries;
     a "A-r" M.a_page_results;
     a "A-m" M.a_page_rooms ;
     a "A-u" M.a_page_uploads;
     a "A-o" M.a_page_options;
     a "A-c" M.a_page_console;
     a "A-h" M.a_page_help;
     a "A-Left" M.a_previous_page;
     a "A-Right" M.a_next_page;
     a "C-r" M.a_reconnect;
     a "C-q" M.a_exit ;
    );
  if !!O.keymap_servers = [] then
    (
     let a = O.add_binding O.keymap_servers in
     a "C-c" M.a_connect;
     a "C-m" M.a_connect_more;
     a "C-a" M.a_select_all;
    );
  if !!O.keymap_downloads = [] then
    (
     let a = O.add_binding O.keymap_downloads in
     a "C-c" M.a_cancel_download;
     a "CS-s" M.a_save_all_files;
     a "C-s" M.a_menu_save_file;
     a "C-a" M.a_select_all;
    );
  if !!O.keymap_friends = [] then
    (
     let a = O.add_binding O.keymap_friends in
     a "C-d" M.a_download_selection;
     a "C-x" M.a_remove_friend;
     a "C-a" M.a_select_all;
    );
  if !!O.keymap_queries = [] then
    (
     let a = O.add_binding O.keymap_queries in
     ()
    );
  if !!O.keymap_results = [] then
    (
     let a = O.add_binding O.keymap_results in
     ()
    );
  if !!O.keymap_console = [] then
    (
     let a = O.add_binding O.keymap_console in
     ()
    )

(** {2 Handling core messages} *)

open CommonTypes
open GuiTypes
open GuiProto
  

let verbose_gui_messages = ref false
    

let value_reader gui t =
  try
    
    if !verbose_gui_messages then begin
        lprintf "MESSAGE RECEIVED: %s" 
          (string_of_to_gui t);
        lprint_newline ();
        
      end;
    
    
    match t with
    | Console text ->
        gui#tab_console#insert text
    
    | Network_info n ->
        begin
          try
            let box_net = gui#tab_networks in
            let (box, i) = Gui_networks.retrieve_net_box n.network_netname box_net in
            begin
              try
                let nn = Hashtbl.find Gui_global.networks n.network_netnum in
            nn.net_enabled <- n.network_enabled;
                (* Printf.printf "Gui_main net exist %d : %s : %b\n" nn.net_num nn.net_name nn.net_enabled;
                flush stdout; *)
                Gui_networks.fill_box box i nn.net_enabled nn.net_displayed true;
                gui#tab_queries#update_wcombos
          with _ ->
              let nn = {
                  net_num = n.network_netnum;
                  net_name = n.network_netname;
                  net_enabled = n.network_enabled;
                  net_displayed = true;
                } in
                (* Printf.printf "Gui_main net new %d : %s : %b\n" nn.net_num nn.net_name nn.net_enabled;
                flush stdout;*)
                Gui_networks.fill_box box i nn.net_enabled nn.net_displayed true;
                ignore (box#wtog_net#connect#toggled ~callback:(fun _ ->
                    (* nn.net_enabled <- not nn.net_enabled; *) (* Not necessary - wait for the core answer instead *)
                    (* Printf.printf "Gui_main callback wtog %d : %s : %b - wtog state %b\n"
                      nn.net_num nn.net_name nn.net_enabled box#wtog_net#active;
                    flush stdout;*)
                    Com.send (EnableNetwork (nn.net_num,
                        box#wtog_net#active)
                    )));
                ignore (box#wchk_net#connect#toggled ~callback:(fun _ ->
                    nn.net_displayed <- not nn.net_displayed;
                    networks_filtered := (if nn.net_displayed then
                        List2.removeq nn.net_num !networks_filtered
                      else nn.net_num :: !networks_filtered);
                    (* Printf.printf "Gui_main callback wcheck %d : %s : %b\n" nn.net_num nn.net_name nn.net_displayed;
                    flush stdout;*)
                    gui#tab_servers#h_server_filter_networks;
                    gui#tab_queries#h_search_filter_networks;
                    Gui_networks.fill_box box i nn.net_enabled nn.net_displayed true
                ));
              Hashtbl.add Gui_global.networks n.network_netnum nn;
                gui#tab_queries#update_wcombos;
              ()
        end
    
          with _ -> ()

        end

    | Client_stats s ->
        gui#tab_uploads#wl_status#set_text
          (Printf.sprintf "Shared: %5d/%-12s   U/D bytes/s: %7d[%5d]/%-7d[%5d]" 
            s.nshared_files 
            (Gui_misc.size_of_int64 s.upload_counter)
          (s.tcp_upload_rate + s.udp_upload_rate) s.udp_upload_rate
          (s.tcp_download_rate + s.udp_download_rate) s.udp_download_rate
        );
        gui#tab_graph#set_upload_rate (s.tcp_upload_rate + s.udp_upload_rate);
        gui#tab_graph#set_download_rate (s.tcp_download_rate + s.udp_download_rate)
    
    | CoreProtocol v -> 
        Gui_com.gui_protocol_used := min v GuiEncoding.best_gui_version;
        lprintf "Using protocol %d for communications" !Gui_com.gui_protocol_used;
        lprint_newline ();
        gui#label_connect_status#set_text (gettext M.connected);
        Com.send (Password (!!O.login, !!O.password))
    
    | Search_result (num,r) -> 
        begin try
            let r = Hashtbl.find G.results r in
            gui#tab_queries#h_search_result num r
          with _ -> 
              lprintf "Exception in Search_result %d %d" num r;
              lprint_newline ();
        end
    
    | Search_waiting (num,waiting) -> 
        gui#tab_queries#h_search_waiting num waiting
    
    | File_add_source (num, src) -> 
        gui#tab_downloads#h_file_location num src
    
    | File_remove_source (num, src) -> 
        gui#tab_downloads#h_file_remove_location num src
    
    | File_downloaded (num, downloaded, rate, last_seen) ->
        gui#tab_downloads#h_file_downloaded num downloaded rate;
        gui#tab_downloads#h_file_last_seen num last_seen
    
    | File_update_availability (file_num, client_num, avail) ->
        gui#tab_downloads#h_file_availability file_num client_num avail
    
    | File_info f ->
(*        lprintf "FILE INFO"; lprint_newline (); *)
        gui#tab_downloads#h_file_info f
    
    | Server_info s ->
(*        lprintf "server info"; lprint_newline (); *)
        gui#tab_servers#h_server_info s
    
    | Server_state (key,state) ->
        gui#tab_servers#h_server_state key state
    
    | Server_busy (key,nusers, nfiles) ->
        gui#tab_servers#h_server_busy key nusers nfiles
    
    | Server_user (key, user) ->
(*        lprintf "server user %d %d" key user; lprint_newline (); *)
        if not (Hashtbl.mem G.users user) then begin
(*            lprintf "Unknown user %d" user; lprint_newline ();*)
            Gui_com.send (GetUser_info user);
          end else 
          begin
            gui#tab_servers#h_server_user key user
          end
    
    | Room_info room ->
(*        lprintf "Room info %d" room.room_num; lprint_newline (); *)
        gui#tab_rooms#room_info room
    
    | User_info user ->
        let user = try 
            let u = Hashtbl.find G.users user.user_num  in
            u.user_tags <- user.user_tags;
            u
          with Not_found ->
              Hashtbl.add G.users user.user_num user; 
              user
        in
(*        lprintf "user_info %s/%d" user.user_name user.user_server; lprint_newline (); *)
        gui#tab_servers#h_server_user user.user_server user.user_num;
        Gui_rooms.user_info user
    
    | Room_add_user (num, user_num) -> 
        
        begin try
            gui#tab_rooms#add_room_user num user_num
          with e ->
              lprintf "Exception in Room_user %d %d" num user_num;
              lprint_newline ();
        end
    
    | Room_remove_user (num, user_num) -> 
        
        begin try
            gui#tab_rooms#remove_room_user num user_num
          with e ->
              lprintf "Exception in Room_user %d %d" num user_num;
              lprint_newline ();
        end
    
    | Options_info list ->
(*        lprintf "Options_info"; lprint_newline ();*)
        let rec iter list =
          match list with
            [] -> ()
          | (name, value) :: tail ->
              (
                try
                  let reference = 
                    List.assoc name Gui_options.client_options_assocs 
                  in                  
                  reference := value;
                  Gui_config.add_option_value name reference
                with _ -> 
                    Gui_config.add_option_value name (ref value)
              );
              iter tail
        in
        iter list
    
    | Add_section_option (section, message, option, optype) ->
        let line = message, optype, option in
        (try
            let options = List.assoc section !client_sections in
            if not (List.mem line !options) then
              options := !options @ [line]
        with _ ->
            client_sections := !client_sections  @[section, ref [line]]
        )          
    
    | Add_plugin_option (section, message, option, optype) ->
        let line = message, optype, option in
        (try
            let options = List.assoc section !plugins_sections in
            if not (List.mem line !options) then
              options := !options @ [line]
        with _ ->
            plugins_sections := !plugins_sections  @[section, ref [line]]
        )          
        
    | DefineSearches l ->
        gui#tab_queries#h_define_searches l
    
    | Client_state (num, state) ->
      (* lprintf "Client_state" ; lprint_newline (); *)
        gui#tab_friends#h_update_friend_state (num , state);
        gui#tab_uploads#h_update_client_state (num , state);
        gui#tab_downloads#h_update_client_state (num , state)
    
    | Client_friend (num, friend_kind) ->
        gui#tab_friends#h_update_friend_type (num , friend_kind);
        gui#tab_uploads#h_update_client_type (num , friend_kind);
        gui#tab_downloads#h_update_client_type (num , friend_kind)
    
    | Result_info r ->
        
        if not (Hashtbl.mem G.results r.result_num) then
          Hashtbl.add G.results r.result_num r
    
    | Client_file (num , dirname, file_num) ->
(* Here, the dirname is forgotten: it should be used to build a tree
  when possible... *)
        gui#tab_friends#h_add_friend_files (num , dirname, file_num)

    | Client_info c -> 
(*        lprintf "Client_info"; lprint_newline (); *)
        gui#tab_friends#h_update_friend c;
        gui#tab_uploads#h_update_client c;
        gui#tab_downloads#h_update_client c

(* A VOIR : Ca sert �  quoi le bouzin ci-dessous ?
ben, ca sert a mettre a jour la liste des locations affichees pour un
fichier selectionne. Si ca marche toujours dans ton interface, pas de
  probleme ...
        begin
          match !current_file with
            None -> ()
          | Some file ->
              let num = c.client_num in
              match file.file_more_info with
                None -> ()
              | Some fmi ->
                  if array_memq num fmi.file_known_locations ||
                    array_memq num fmi.file_indirect_locations then
                    let c = Hashtbl.find locations c.client_num in
                    if is_connected c.client_state then incr nclocations;
                    MyCList.update clist_file_locations c.client_num c
        end
*)


    | Room_message (_, PrivateMessage(num, mes) )
    | Room_message (0, PublicMessage(num, mes) )
    | MessageFromClient (num, mes) ->
	(
	 try
           let box_uploaders = gui#tab_uploads#box_uploaders in
           let (row , c ) = box_uploaders#find_client num in
	   let d = gui#tab_friends#get_dialog c in
	   d#handle_message mes
	 with
            Not_found ->
              try
                match t with
                  Room_message (num, msg) ->
                    gui#tab_rooms#add_room_message num msg                
                | _ -> raise Not_found
              with Not_found ->
                  lprintf "Client %d not found in reader.MessageFromClient" num;
                  lprint_newline ()
        )    
        
    | Room_message (num, msg) ->
        begin try
            gui#tab_rooms#add_room_message num msg
          with e ->
              lprintf "Exception in Room_message %d" num;
              lprint_newline ();
        end

    | (DownloadedFiles _|DownloadFiles _|ConnectedServers _) -> assert false

    | Shared_file_info si ->
        gui#tab_uploads#h_shared_file_info si

    | CleanTables (clients, servers) ->
        gui#tab_servers#clean_table servers;
        gui#tab_downloads#clean_table clients;
        gui#tab_uploads#clean_table clients
        
    | Shared_file_upload (num,size,requests) ->
        gui#tab_uploads#h_shared_file_upload num size requests
    | Shared_file_unshared _ ->  ()
    | BadPassword -> 
        GToolbox.message_box ~title: "Bad Password" 
        "Authorization Failed\nPlease, open the File->Settings menu and
          enter a valid password"
  with e ->
      lprintf "Exception %s in reader" (Printexc2.to_string e);
      lprint_newline ()

      
let generate_connect_menu gui =
  let add_item hostname port =
    let menu_item =
      let label = Printf.sprintf "%s:%d" hostname port in
      GMenu.menu_item ~label: label
      ~packing:gui#cores_menu#add ()
      in
    ignore (menu_item#connect#activate ~callback:(fun _ ->
          O.hostname =:= hostname;
          O.port =:= port;
          Com.reconnect gui value_reader BasicSocket.Closed_by_user
      ));
  in
  List.iter (fun child -> child#destroy ()) gui#cores_menu#children;
  List.iter (fun (h,port) ->  add_item h port) !!O.history;
  let _ = GMenu.menu_item ~packing:(gui#cores_menu#add) () in
 List.iter (fun (h,port) ->  add_item h port) !G.scanned_ports


let window_about _ =
  let window =
    GWindow.window ~position:`CENTER_ALWAYS ~kind:`POPUP
      ~width:375 ~height:275 ()
  in
  Widget.realize window#as_widget ;
  Widget.set_app_paintable window#as_widget true;
  let splash_screen = O.gdk_pix M.o_xpm_splash_screen in
  let wpix = `PIXMAP(splash_screen#pixmap) in
  Window.set_back_pixmap window#misc#window wpix;
  ignore (window#event#add [`BUTTON_PRESS]);
  let vbox =
    GPack.vbox ~homogeneous:false
      ~packing:(window#add) ()
  in
  let vbox_ =
    GPack.vbox ~homogeneous:false
      ~packing:(vbox#pack ~fill:true ~expand:true) ()
  in
  let hbox =
    GPack.hbox ~homogeneous:false
      ~packing:(vbox#pack ~fill:true ~expand:false) ()
  in
  let label =
    GMisc.label ~line_wrap:true ~text:(Printf.sprintf "v. %s" Autoconf.current_version)
      ~justify:`LEFT ~packing:(hbox#pack ~fill:true ~expand:false ~padding:10) ()
  in
  ignore (window#event#connect#button_press
    ~callback:(fun e ->
      GdkEvent.get_type e = `BUTTON_PRESS &&
      (
        window#destroy ();
        true
      )
  ));
  window#show ()


let main () =
  let gui = new Gui_window.window () in
  let w = gui#window in
  let quit () = 
    chmod_config (); 
    CommonGlobals.exit_properly 0
  in
  chmod_config (); 
  window_about ();
  Gui_config.update_toolbars_style gui;
  Gui_config.update_list_bg gui;
  Gui_config.update_graphs gui;
  Gui_config.update_availability_column gui;
  Gui_config.update_icons gui;

  List.iter (fun (menu, init) ->
      let _Menu = GMenu.menu_item ~label:menu  ~packing:(gui#menubar#add) ()
      in
      let im_menu = GMenu.menu ~packing:(_Menu#set_submenu) () in
      init im_menu
  ) !Gui_global.top_menus;
  (* Here there is an error (see the message "exit_properly (exception %s)") in a console when you close directly the window)
     #connect#destroy is too late : the window is already destroyed.
     Call #event#connect#delete instead to make operations before destroying the window *)
  (* ignore (w#connect#destroy quit); *)
  ignore (w#event#connect#delete (fun _ ->
                                     quit ();
                                     true)
  );
  console_message := (fun s -> 

(*
      lprintf "to primary"; lprint_newline ();
      let e = gui#tab_console#text in
  
      ignore (GtkBase.Selection.owner_set e#as_widget `PRIMARY 0);
(*      ignore(e#misc#grab_selection `PRIMARY); *)
(*      e#misc#add_selection_target ~target:"string" `PRIMARY; 
      ignore (e#misc#connect#selection_get (fun sel ~info ~time ->
            lprintf "request selection"; lprint_newline ();
            sel#return s
        )); *)
      ignore (e#event#connect#selection_clear  (fun sel ->
            lprintf "selection cleared"; lprint_newline ();
            true
        ));
      ignore (e#event#connect#selection_request (fun sel ->
            lprintf "Selection request"; lprint_newline ();
            true
        ));
      ignore (e#event#connect#selection_notify (fun sel ->
            lprintf "Selection notify"; lprint_newline ();
            true
));
  *)
      gui#tab_console#insert s);

  CommonGlobals.do_at_exit (fun _ ->
      Gui_misc.save_gui_options gui;
      Gui_com.disconnect gui BasicSocket.Closed_by_user);  
(** menu actions *)
(*
  ignore (gui#itemQuit#connect#activate (fun () ->
        CommonGlobals.exit_properly 0)) ;
*)
  ignore (gui#buttonQuit#connect#clicked (fun () ->
        CommonGlobals.exit_properly 0)) ;
(*
  ignore (gui#itemKill#connect#activate (fun () -> Com.send KillServer));
*)
  ignore (gui#buttonKill#connect#clicked (fun () -> Com.send KillServer));

  ignore (gui#itemReconnect#connect#activate 
      (fun () ->Com.reconnect gui value_reader BasicSocket.Closed_by_user));
  ignore (gui#itemDisconnect#connect#activate 
	    (fun () -> Com.disconnect gui BasicSocket.Closed_by_user));

  ignore (gui#itemServers#connect#activate (fun () -> gui#notebook#goto_page 1));
  ignore (gui#itemDownloads#connect#activate (fun () -> gui#notebook#goto_page 2));
  ignore (gui#itemFriends#connect#activate (fun () -> gui#notebook#goto_page 3));
  ignore (gui#itemResults#connect#activate (fun () -> gui#notebook#goto_page 4));
  ignore (gui#itemRooms#connect#activate (fun () -> gui#notebook#goto_page 5));
  ignore (gui#itemUploads#connect#activate (fun () -> gui#notebook#goto_page 6));
  ignore (gui#itemConsole#connect#activate (fun () -> gui#notebook#goto_page 7));
  ignore (gui#itemHelp#connect#activate (fun () -> gui#notebook#goto_page 8));

(*
  ignore (gui#itemOptions#connect#activate (fun () -> Gui_config.edit_options gui));
*)
  ignore (gui#buttonOptions#connect#clicked (fun () -> Gui_config.edit_options gui));
  ignore (gui#buttonAbout#connect#clicked (fun () -> window_about ()));

  ignore (gui#itemScanPorts#connect#activate (fun _ ->
        Com.scan_ports () 
    ));

  ignore (gui#buttonGui#connect#clicked (fun () -> gui#g_menu#popup ~button:1 ~time:0));

  ignore (gui#buttonIm#connect#clicked (fun () ->
    Gui_im.main_window#window#show ()));

  (************ Some hooks ***************)
  option_hook Gui_options.notebook_tab (fun _ ->
      gui#notebook#set_tab_pos !!Gui_options.notebook_tab
  );
  
  (** connection with core *)
  Com.reconnect gui value_reader BasicSocket.Closed_by_user ;
(*  BasicSocket.add_timer 2.0 update_sizes;*)
  let never_connected = ref true in
  BasicSocket.add_timer 1.0 (fun timer ->
      if !G.new_scanned_port then begin
          generate_connect_menu gui
        end;
      
      if !never_connected && not (Com.connected ()) then  begin
          BasicSocket.reactivate_timer timer;
          Com.reconnect gui value_reader BasicSocket.Closed_by_user
        end else
        never_connected := false
  )
  
let _ = 
  CommonGlobals.gui_included := true;
  main ()